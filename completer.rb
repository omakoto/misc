#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pathname'
require 'pp'

require 'rubygems' # For version check on<1.9
abort "#{$0.sub(/^.*\//, "")} requires ruby >= 2.4" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4')

=begin
- To enable debug output, use:

export COMPLETER_DEBUG=/tmp/completer-debug.txt

- Can also be enabled with -d.
=end

$debug_file = ENV['COMPLETER_DEBUG']
$debug = $debug_file ? true : false
$debug_file ||= "/tmp/completer-debug.txt"
$debug_out = nil

# Whether completion is being performed in case-insensitive mode.
# For simplicity, we just use a global var.
$complete_ignore_case = true

module CompleterRefinements
  refine Kernel do
    # Shod debug output.
    def debug(*msg, &b)
      if !$debug
        return 0
      end
      # If stdout is TTY, assume the script is executed directly for
      # testing, and write log to stderr.
      if $stdout.tty?
        $stderr.puts msg
      else
        $debug_out = open $debug_file, "w" unless $debug_out
        $debug_out.puts msg
        $debug_out.flush
      end
      debug(b.call()) if b
      return 1
    end

    def die(*msg)
      abort "#{__FILE__}: " + msg.join("") + "\n" + caller.map{|x|x.to_s}.join("\n")
    end

    # Shell-escape a single token.
    def shescape(arg)
      if arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/
          return "'" + arg.gsub(/'/, "'\\\\''") + "'"
      else
          return arg;
      end
    end

    # Shell-unescape a single token.
    def unshescape(arg)
      if arg !~ /[\'\"\\]/
        return arg
      end

      ret = ""
      pos = 0
      while pos < arg.length
        ch = arg[pos]

        case ch
        when "'"
          pos += 1
          while pos < arg.length
            ch = arg[pos]
            pos += 1
            if ch == "'"
              break
            end
            ret += ch
          end
        when '"'
          pos += 1
          while pos < arg.length
            ch = arg[pos]
            pos += 1
            if ch == '"'
              break
            elsif ch == '\\'
              if pos < arg.length
               ret += arg[pos]
              end
              pos += 1
            end
            ret += ch
          end
        when '\\'
          pos += 1
          if pos < arg.length
            ret += arg[pos]
            pos += 1
          end
        else
          ret += ch
          pos += 1
        end
      end

      return ret
    end

    # Takes a String or a Candidate and return as a Candidate.
    def as_candidate(value, raw:nil, completed: nil, help: nil)
      if value.instance_of? Candidate
        return value
      elsif value.instance_of? String
        # If a string contains a TAB, the following section is a
        # help string.
        (candidate, s_help) = value.split(/\t/, 2)

        # If a candidate starts with an ESC, it's a raw candidate.
        s_raw = candidate.sub!(/^\x1b/, "") ? true : false

        # If a candidate ends with a BS, it's not a completed
        # candidate.
        s_completed = candidate.sub!(/\x08$/, "") ? false : true

        # If one is provided as an argument, use it.
        raw = s_raw if raw == nil
        completed = s_completed if completed == nil
        help = s_help if help == nil

        return Candidate.new(candidate, raw:raw, completed:completed, help:help)
      else
        return nil
      end
    end

    def lazy(&block)
      return LazyList.new(&block)
    end

  end # refine Kernel

  refine String do
    # When a string starts with "~/", then expand to the home directory.
    # Doesn't support ~USERNAME/.
    def expand_home()
      return self.sub(/^~\//, "#{Dir.home}/")
    end

    # Same as self.start_with?(prefix), except it can do case-insensitive
    # comparison when needed.
    def has_prefix?(prefix)
      return true unless prefix
      if $complete_ignore_case
        return self.downcase.start_with? prefix.downcase
      else
        return self.start_with? prefix
      end
    end

    # Build a candidate from a String.
    def as_candidate(raw:nil, completed: nil, help: nil)
      return Kernel.as_candidate(value, raw:raw, completed:completed, help:help)
    end
  end # refine String
end

class LazyList
  include Enumerable

  def initialize(&block)
    block or die "block must be provided."
    @block = block
    @list = nil
  end

  def each(&block)
    @list = @block.call() unless @list
    @list.each(&block)
  end
end

using CompleterRefinements

#===============================================================================
# Argument helpers
#===============================================================================
module CompleterHelper
  # Return true if a given path is a directory and not empty.
  def is_non_empty_dir(f, ignore_files: false)
    begin
      return false unless File.directory?(f)

      if ignore_files
        return f.children.any? { |x| x.directory? }
      else
        return !Dir.empty?(f)
      end
    rescue SystemCallError => e
      debug {"is_non_empty_dir(): #{e.inspect}"}
      # Just ignore any errors.
      return false
    end
  end

  # Find matching files for a given word.
  def get_matched_files(word, wildcard = "*")
    # Remove the last path component.
    dir = word.sub(%r([^\/]*$), "")

    debug {"word=#{word} dir=#{dir} wildcard=#{wildcard}"}

    if dir != "" and !Dir.exists? dir
      return
    end

    ret = []

    flag = File::FNM_DOTMATCH
    if $complete_ignore_case
      flag |= File::FNM_CASEFOLD
    end

    begin
      Pathname.new(dir == "" ? "." : dir).children.each do |path|
        if path.directory?
          cand = path.to_s
          cand += "/"
          cand += "\b" if is_non_empty_dir(path)
        else
          # If it's a file, only add when the basename matches wildcard.
          next unless File.fnmatch(wildcard, path.basename, flag)
          cand = path.to_s
        end
        ret.push(cand)
      end
    rescue SystemCallError => e
      debug {"get_matched_files(): #{e.inspect}"}
    end

    return ret
  end

  # Find matching directories for a given word.
  def get_matched_dirs(word)
    # Remove the last path component.
    dir = word.sub(%r([^\/]*$), "")

    if dir != "" and !Dir.exists? dir
      return
    end

    ret = []

    begin
      Pathname.new(dir == "" ? "." : dir).children.each do |path|
        next unless path.directory?
        cand = path.to_s
        cand += "/"
        cand += "\b" if is_non_empty_dir(path, ignore_files:true)
        ret.push(cand)
      end
    rescue SystemCallError => e
      debug {"get_matched_dirs(): #{e.inspect}"}
    end

    return ret
  end

  # Read all lines from a file, if exists.
  def read_file_lines(file, ignore_comments:true)
    file = file.expand_home
    ret = (File.exist? file) ? open(file, "r").read.split(/\n/) : []

    if ignore_comments
      ret = ret.reject {|x| x =~/^\#/ }
    end

    return ret;
  end

  # Accept an integer.
  def get_matched_numbers(word, allow_negative:false)
    lazy do
      if allow_negative
        return [] unless word =~ /^\-?\d*$/
      else
        return [] unless word =~ /^\d*$/
      end

      if word == ""
        if allow_negative
          return ["-1".."-9", "0".."9"]
        else
          return ["0".."9"]
        end
      else
        return ("0".."9").map {|x| word + x }
      end
    end
  end

  def take_file(wildcard="*")
    lazy { get_matched_files word, wildcard }
  end

  def take_dir()
    lazy { get_matched_dirs word }
  end

  def take_number(allow_negative:false)
    lazy { get_matched_numbers word, allow_negative }
  end
end

#===============================================================================
# Candidate
#===============================================================================

# Represents a single candidate.
class Candidate
  using CompleterRefinements

  def initialize(value, raw:false, completed: true, help: "")
    value or die "Empty candidate detected."

    @value = value.chomp
    @raw= raw
    @completed = completed
    @help = help
  end

  # The candidate text.
  attr_reader :value

  # Raw candidates will not be escaped.
  attr_reader :raw

  # When a candidate is "completed", it's not a prefix of another text.
  # A completed candidate will be followed by a space when expanded.
  attr_reader :completed

  # Help text, bash can't show it, but maybe zsh can.
  attr_reader :help

  # Whether a candidate has a prefix or not.
  def has_prefix?(prefix)
    return @value.has_prefix?(prefix)
  end

  def as_candidate()
    return self
  end

  def to_s()
    return "{Candidate:value=#{shescape value}#{raw ? " [raw]" : ""}" +
        "#{completed ? " [completed]" : ""}" +
        "#{help ? " " + help : ""}}"
  end
end

#===============================================================================
# Shell interface
#===============================================================================

# Class that eats information sent by bash via stdin.
class BashProxy
  SECTION_SEPARATOR = "\n-*-*-*-COMPLETER-*-*-*-\n"

  def initialize()
    # Shell and environmental variables.
    @env = {}
    @jobs = []
    @engine = nil
  end

  attr_reader :env, :jobs

  attr_accessor :engine

  def install(commands, script, ignore_case)
    command = commands[0]
    func = "_#{command.gsub(/[^a-z0-9]/i) {|c| "_" + c.ord.to_s(16)}}_completion"

    debug {"Installing completion for '#{command}', function='#{func}'"}

    script_file = File.expand_path $0

    debug_flag = debug ? "-d" : ""
    ignore_case_flag = ignore_case ? "-i" : ""

    # Note, we generate "COMPREPLY=(" and ")" by code too, which will
    # allow us to execute any code from the script if needed.
    puts <<~EOF
        function __completer_context_passer {
            declare -p
            echo -n "#{SECTION_SEPARATOR}"
            jobs
        }

        function #{func} {
          . <( __completer_context_passer |
              ruby -x "#{script_file}" #{debug_flag} #{ignore_case_flag} \
                  -p "$COMP_POINT" \
                  -l "$COMP_LINE" \
                  -c "$COMP_CWORD" "${COMP_WORDS[@]}" \
                  )
        }
        EOF

    commands.each do |c|
      puts "complete -o nospace -F #{func} #{c}"
    end
  end

  # Called when completion is about to start.
  def start_completion()
    vars, jobs = $stdin.read.split(SECTION_SEPARATOR)
    vars and vars.split(/\n/).each do |line|
      if line =~ /^declare\s+(\S+)\s+([^=]+)\=(.*)$/ then
        flag, name, value = $1, $2, $3
        debug {"#{flag}: #{name} = #{value}"}
        next if flag =~ /[aA]/ # Ignore arrays and hashes
        @env[name] = unshescape value
      end
    end

    # TODO Parse jobs
    jobs = jobs # suppress warning.

    # debug @env
    puts <<~EOF
          IFS=$'\\n' COMPREPLY=(
        EOF
  end

  def end_completion()
    puts <<~EOF
          ) # END COMPREPLY
        EOF
  end

  def maybe_override_candidates()
    do_filename_completion = false
    1.upto(engine.cursor_index - 1).each do |i|
      # When there's an unquoted redirect marker, do a filename completion.
      word = engine.orig_words[i]
      if word =~ /^[\<\>]/
        do_filename_completion = true
      end
    end
    if do_filename_completion
      engine.candidates engine.get_matched_files engine.cursor_word
    end
  end

  # Return as a candidate string for bash.
  # Note bash can't show a help string.
  def add_candidate(candidate)
    s = shescape(candidate.value)
    s += " " if candidate.completed

    # Output will be eval'ed, so need double-escaping unless raw.
    puts(candidate.raw ? s : shescape(s))
  end

  def variable_completable?(word)
    return (word =~ /^\$([a-z0-9\_]*)$/i) ? $1 : nil
  end

  def variable_expandable?(word)
    return (word =~ /^\$([a-z0-9\_]*)\/$/i) ? $1 : nil
  end
end

def get_proxy()
  shell = Pathname.new(ENV["SHELL"]).basename.to_s
  case shell
  when "bash"
    return BashProxy.new
  else
    die "Unsupported shell '#{shell}'"
  end
end
#-----------------------------------------------------------
# Engine
#-----------------------------------------------------------
class CompletionEngine
  using CompleterRefinements
  include CompleterHelper

  FINISH_LABEL = :FinishLabel
  FOR_ARG_LABEL = :ForArg
  FOR_AGAIN = 1

  def initialize(proxy, orig_words, index, ignore_case, comp_line, comp_point)
    @proxy = proxy

    @orig_words = orig_words

    # All words in the command line.
    @words = orig_words.map { |w| unshescape(w.expand_home) }

    # Cursor word index; 0-based.
    @cursor_index = index

    # Command name
    @command = @words[0].gsub(%r(^.*/), "")

    # Whether do case-insensitive comparison or not;
    # this comes from the -i option.
    @ignore_case = ignore_case

    # Whole command line
    @comp_line = comp_line

    # Cursor point
    @comp_point = comp_point

    @index = 0

    @current_consumed = false

    @candidates = []

    @candidates_nest = 0 # for debugging
  end

  attr_reader :proxy, :orig_words, :words, :cursor_index, :command,
      :ignore_case, :comp_line, :comp_point, :index

  # Returns the shell and environmental variables.
  def env()
    return @proxy.env
  end

  def cursor_word()
    return words[cursor_index] || ""
  end

  def cursor_orig_word()
    return orig_words[cursor_index] || ""
  end

  def word(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return words[i] || ""
  end

  def orig_word(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return orig_words[i] || ""
  end

  def at_cursor?()
    return index == cursor_index
  end

  def after_cursor?()
    return index > cursor_index
  end

  def before_cursor?()
    return index < cursor_index
  end

  def current_consumed?
    return @current_consumed
  end

  # Whether a candidate(s) are already registered.
  def has_candidates?()
    return @candidates.size > 0
  end

  # Clear all the candidates that have been added so far.
  def clear_candidates()
    debug "Candidate(s) removed."
    @candidates = []
  end

  # Add a single candidate.
  # If always is true, candidates will be always added, even
  # if the candidate doesn't start with the cursor word.
  def _candidate_single(arg, always:false)
    # debug {"_candidate_single: #{arg} #{always}"}

    return unless at_cursor?
    return unless arg
    die "#{arg.inspect} is not a Candidate" unless arg.instance_of? Candidate
    return unless arg.value
    if !always and !arg.has_prefix? cursor_word
      debug {"#{"  " * @candidates_nest}candidate rejected."}
      return
    end

    debug {"#{"  " * @candidates_nest}candidate added: #{arg}"}

    @candidates.push(arg)
  end

  # Push candidates.
  # "args" can be a string, an array of strings, or a proc.
  # If always is true, candidates will be always added, even
  # if they don't start with the cursor word.
  def candidates(*args, always:false , &block)
    return unless at_cursor?

    @candidates_nest += 1

    args.each {|arg|
      debug {"#{"  " * @candidates_nest}candidate?: arg=#{arg.inspect}"}
      c = as_candidate(arg)
      # debug {"as_candidate=#{c.inspect}"}
      if c
        @candidates_nest += 1
        _candidate_single c, always:always
        @candidates_nest -= 1
      elsif arg.respond_to? :each
        arg.each {|x| candidates x, always:always}
      elsif arg.respond_to? :call
        candidates(arg.call(), always:always)
      else
        debug {"Ignoring unsupported candidate: #{arg.inspect}"}
      end
    }
    if block
      candidates(block.call(), always:always)
    end
    @candidates_nest -= 1
  end

  alias candidate candidates
  alias flag candidates
  alias flags candidates


  def next_word(implicit:false, &block)
    if @index <= @cursor_index
      @last_move_was_implicit = implicit
      @index += 1
      @current_consumed = false
      block.call() if block
    end
    debug {"[next_word] -> now at #{index}, \"#{word}\""}

    finish if after_cursor?
  end

  def consume()
    @current_consumed = true
    debug {"word at #{index} consumed."}
  end

  def match?(condition, value)
    debug {"match?: #{condition}, #{value}"}
    if condition.instance_of? String
      return condition == value # For a full match, we're always case sensitive.
    elsif condition.instance_of? Regexp
      return value =~ condition
    elsif condition.respond_to? :each
      return condition.any?{|x| x == value}
    else
      die "Unsupported match type: condition"
    end
  end

  def for_arg(match=nil, &block)
    block or die "for_each_word() requires a block."

    move_next_word = current_consumed?

    begin
      res = catch FOR_ARG_LABEL do
        while !after_cursor?
          debug {"[for_arg](#{index}/#{cursor_index})"}

          next_word if move_next_word # First move may be skipped.
          move_next_word = true

          debug {"  #{match} vs #{word}"}
          if match == nil or at_cursor? or match? match, word
            debug {"    matched."}
            block.call()
          else
            return
          end

          # If at_cursor, we need to run the rest of the code after the loop,
          # with the current word (without advancing the index).
          if at_cursor?
            break
          end
        end
      end
    end while res == FOR_AGAIN
  end

  # def any_of(&block)
  #   block or die "any_of() requires a block."
  #   catch ANY_OF_LABEL do
  #     block.call
  #   end
  # end

  def for_break()
    throw FOR_ARG_LABEL
  end

  def for_next()
    throw FOR_ARG_LABEL, FOR_AGAIN
  end

  def maybe(*args, &block)
    args.length == 0 and die "maybe() requires at least one argument."

    return if current_consumed?
    debug {"[maybe](#{index}/#{cursor_index}): #{args}#{block ? " (has block)" : ""}"}

    # If we're at cursor, just add the candidates.
    if at_cursor?
      debug {" at_cursor: adding candidate(s)."}
      candidates args[0]
      return
    end

    if !match? args[0], word
      return
    end

    # Otherwise, eat words.
    debug {"  maybe: found a match."}

    (args.length - 1).times do |i|
      next_word
      if at_cursor?
        candidates args[i + 1]
        finish
      end
    end
    consume

    if block
      next_word implicit:true
      block.call
    end
  end

  def otherwise(&block)
    block or die "otherwise() requires a block."

    maybe(//) do
      block.call
    end
  end

  def next_word_must(*args, &block)
    args.length == 0 and die "next_word_must() requires at least one argument."

    debug {"[next_word_must](#{index}/#{cursor_index}): #{args}#{block ? " (has block)" : ""}"}

    next_word if current_consumed?
    # next_word unless @last_move_was_implicit

    (args.length).times do |n|
      if at_cursor?
        candidates args[n]
        finish
      end
      next_word
    end
  end

  def finish()
    block_given? and die "finish() doesn't take a block."
    debug "finish()"
    throw FINISH_LABEL
  end

  # If the cursor word starts with "$", then see if it's expandable.
  def maybe_handle_variable()
    cow = cursor_orig_word

    name = proxy.variable_completable?(cow)
    if name
      debug { "Maybe variable: #{name}" }
      env.keys.each do |k|
        if k.has_prefix?(name)
          candidate("\e$" + k + "\b") # Raw candidate
        end
      end
      return
    end

    name = proxy.variable_expandable?(cow)
    if name
      debug "Maybe variable: #{name}"
      value = env[name]
      if value and File.directory?(value)
        value += "/"
        value += "\b" if is_non_empty_dir(value)
        candidate value, always:true
      end
    end
  end

  # Entry point.
  def run_completion(&block)
    proxy.start_completion
    begin
      # Need this so candidates() will accept candidates.
      @index = @cursor_index

      # If the cursor word starts with a variable name, we want to
      # complete or expand it.
      maybe_handle_variable

      # Bash unfortunately calls a completion function even after < and >.
      # Give the proxy a chance to detect it and do a filename completion.
      proxy.maybe_override_candidates

      # If no one generated candidates yet, let the user-defined code
      # generates some.
      if !has_candidates?
        catch FINISH_LABEL do
          debug "Starting the user block."

          @index = 0
          consume
          instance_eval(&block)

          # If the block defined main(), also run it.
          if self.respond_to? :main
            debug "Detected main(), also running it."
            self.main
          end
        end
      end

      # Add collected candidates.
      @candidates.each do |c|
        proxy.add_candidate c
      end
    ensure
      proxy.end_completion
    end
  end

end


#-----------------------------------------------------------
# Core class
#-----------------------------------------------------------
class Completer

  private

  def __initialize__
  end

  # Install completion
  def do_install(commands, script, ignore_case)
    commands or die "Missing commands."

    # Remove directories from command names.
    commands = commands.map {|p| p.sub(%r(^.*/), "")}
    get_proxy.install(commands, script, ignore_case)
  end

  # Perform completion
  def do_completion(cursor_pos, words, line:nil, point:nil, ignore_case:false, &b)
    b or die "do_completion() requires a block."
    $complete_ignore_case = ignore_case
    proxy = get_proxy
    engine = CompletionEngine.new proxy, words, cursor_pos, ignore_case, line, point
    proxy.engine = engine

    debug <<~EOF
        OrigWords: #{engine.orig_words.join ", "}
        Words: #{engine.words.join ", "}
        Index: #{engine.cursor_index}
        Current: #{engine.cursor_word}
        Line: #{engine.comp_line}
        Point: #{engine.comp_point}
        EOF

    engine.run_completion(&b)
  end

  # Main
  public
  def real_main(&b)
    ignore_case = false
    line = nil
    point = nil

    OptionParser.new { |opts|
      opts.banner = "Usage: [OPTIONS] command-name"

      # Note "-c" must be the last option; otherwise other flags such as
      # "-i" "-d" will be ignored.
      opts.on("-c", "Perform completion (shouldn't be used directly)") do
        cursor_pos = ARGV.shift.to_i
        words = ARGV
        do_completion cursor_pos, words, line:line, point:point, ignore_case: ignore_case, &b
        return
      end

      opts.on("-lLINE", "Pass whole command line") do |v|
        line = v
      end

      opts.on("-pPOS", "Pass completion point") do |v|
        point = v
      end

      opts.on("-i", "Enable ignore-case completion") do
        ignore_case = true
      end

      opts.on("-d", "Enable debug mode") do
        $debug = true
      end
    }.parse!

    ARGV or die("Missing command name(s).")

    do_install ARGV, $0, ignore_case
  end

  # The entry point called by the outer script.
  public
  def self.define(&b)
    b or die "define() requires a block."

    Completer.new.real_main(&b)
  end
end
