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

$debug_indent_level = 0

# Whether completion is being performed in case-insensitive mode.
# For simplicity, we just use a global var.
$complete_ignore_case = true

module CompleterRefinements
  refine Kernel do
    # Debug print.
    def debug(*args, &b)
      return false unless $debug

      if args.length > 0
        msg = args.join("\n").gsub(/^/m, "  " * $debug_indent_level + "D:").chomp

        # If stdout is TTY, assume the script is executed directly for
        # testing, and write log to stderr.
        if $stdout.tty?
          $stderr.puts msg
        else
          $debug_out = open $debug_file, "w" unless $debug_out
          $debug_out.puts msg
          $debug_out.flush
        end
      end
      debug(b.call()) if b
      return true
    end

    def debug_indent(&block)
      $debug_indent_level += 1

      if block
        begin
          block.call()
        ensure
          $debug_indent_level -= 1
        end
      end
    end

    def debug_unindent()
      $debug_indent_level -= 1
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

    # Takes a block that generates a list. The block will be executed only when
    # needed.
    def lazy(&block)
      return LazyList.new(&block)
    end

    # This is basically same as %w(...), except it treats # as comments.
    def words(*args)
      ret = []
      args.each do |arg|
        arg.split(/\n/).each do |line|
          l = line.sub(/^\s+/, "").sub(/\s*\#.*/, "")
          if l.length > 0
            l.split(/\s+/).each do |word|
              ret << word
            end
          end
        end
      end
      return ret
    end

  end # refine Kernel

  refine String do
    # When a string starts with "~/", then expand to the home directory.
    # Doesn't support ~USERNAME/.
    def expand_home()
      return self.sub(/^~\//, "#{Dir.home}/")
    end

    # Same as self.start_with?(prefix), except it does case-insensitive
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

  # Find matching files for a given prefix, with a mask.
  def get_matched_files(prefix, wildcard = "*")
    # Remove the last path component.
    dir = prefix.sub(%r([^\/]*$), "")

    debug {"prefix=#{prefix} dir=#{dir} wildcard=#{wildcard}"}

    if dir != "" and !Dir.exist? dir
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

  # Find matching directories for a given prefix.
  def get_matched_dirs(prefix)
    # Remove the last path component.
    dir = prefix.sub(%r([^\/]*$), "")

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
  def get_matched_numbers(prefix, allow_negative:false)
    lazy do
      if allow_negative
        next [] unless prefix =~ /^\-?\d*$/
      else
        next [] unless prefix =~ /^\d*$/
      end

      if prefix == ""
        if allow_negative
          next ["-1".."-9", "0".."9"]
        else
          next ["0".."9"]
        end
      else
        next ("0".."9").map {|x| prefix + x }
      end
    end
  end

  def take_file(wildcard="*")
    lazy { get_matched_files arg, wildcard }
  end

  def take_dir()
    lazy { get_matched_dirs arg }
  end

  def take_number(allow_negative:false)
    lazy { get_matched_numbers arg, allow_negative:allow_negative }
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
    # Parse output from __completer_context_passer and extract
    # variables and jobs.
    # If STDIN is tty, just skip it, which is handy when debugging.
    if !$stdin.tty?
      debug_indent do
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
      end
    end

    puts <<~EOF
          local IFS=$'\\n'; COMPREPLY=(
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
      arg = engine.orig_args[i]
      if arg =~ /^[\<\>]/
        do_filename_completion = true
      end
    end
    if do_filename_completion
      engine.candidates engine.get_matched_files engine.cursor_arg
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

  def variable_completable?(arg)
    return (arg =~ /^\$([a-z0-9\_]*)$/i) ? $1 : nil
  end

  def variable_expandable?(arg)
    return (arg =~ /^\$([a-z0-9\_]*)\/$/i) ? $1 : nil
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

  def initialize(proxy, orig_args, index, ignore_case, comp_line, comp_point)
    @proxy = proxy

    @orig_args = orig_args

    # All words in the command line.
    @args = orig_args.map { |w| unshescape(w.expand_home) }

    # Cursor arg index; 0-based.
    @cursor_index = index

    # Command name
    @command = @args[0].gsub(%r(^.*/), "")

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
  end

  attr_reader :proxy, :orig_args, :args, :cursor_index, :command,
      :ignore_case, :comp_line, :comp_point, :index

  # Returns the shell and environmental variables.
  def env()
    return @proxy.env
  end

  def cursor_arg()
    return args[cursor_index] || ""
  end

  def cursor_orig_arg()
    return orig_args[cursor_index] || ""
  end

  def arg(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return args[i] || ""
  end

  def orig_arg(relative_index = 0)
    i = index + relative_index
    return nil if i < 0 || i > cursor_index
    return orig_args[i] || ""
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
  # if the candidate doesn't start with the cursor arg.
  def _candidate_single(cand, always:false)
    debug_indent do
      return unless at_cursor?
      return unless cand
      die "#{cand.inspect} is not a Candidate" unless cand.instance_of? Candidate
      return unless cand.value
      if !always and !cand.has_prefix? cursor_arg
        debug {"candidate rejected."}
        return
      end

      debug {"candidate added: #{cand}"}

      @candidates.push(cand)
    end
  end

  # Push candidates.
  # "args" can be a string, an array of strings, or a proc.
  # If always is true, candidates will be always added, even
  # if they don't start with the cursor arg.
  def candidates(*vals, always:false , &block)
    debug_indent do
      return unless at_cursor?

      vals.each {|val|
        debug {"Possible candidate: val=#{val.inspect}"}
        c = as_candidate(val)
        if c
          _candidate_single c, always:always
        elsif val.respond_to? :each
          val.each {|x| candidates x, always:always}
        elsif val.respond_to? :call
          candidates(val.call(), always:always)
        else
          debug {"Ignoring unsupported candidate: #{val.inspect}"}
        end
      }
      if block
        candidates(block.call(), always:always)
      end
    end
  end

  alias candidate candidates
  alias flag candidates
  alias flags candidates

  def next_arg(force:false)
    block_given? and die "next_arg() doesn't take a block."

    if !force and !current_consumed?
       debug {"[next_arg] -> still at #{index}, not consumed yet"}
      return
    end

    if @index <= @cursor_index
      @index += 1
      @current_consumed = false
    end
    debug {"[next_arg] -> now at #{index}, \"#{arg}\""}

    finish if after_cursor?
  end

  def unconsume()
    if @current_consumed
      @current_consumed = false
      debug {"arg at #{index} unconsumed."}
    end
  end

  def consume()
    if !@current_consumed
      @current_consumed = true
      debug {"arg at #{index} consumed."}
    end
  end

  def match?(condition, value)
    debug {"match?: \"#{condition}\", #{shescape value}"}
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

    last_start_index = -1
    begin
      res = catch FOR_ARG_LABEL do
        while !after_cursor?
          force_next = last_start_index == @index and !current_consumed?
          last_start_index = @index

          debug {"[for_arg](#{index}/#{cursor_index})"}

          next_arg force:force_next

          start_index = @index

          if match == nil or at_cursor? or match? match, arg
            debug {"Executing loop body."}
            debug_indent do
              block.call()
            end
          else
            return
          end

          # If at_cursor, we need to run the rest of the code after the loop,
          # with the current arg (without advancing the index).
          if start_index == @cursor_index
            throw FOR_ARG_LABEL
          end
        end
      end
    end while res == FOR_AGAIN
  end

  # Exits the inner most for_arg loop.
  def for_break()
    debug "for_break()"
    throw FOR_ARG_LABEL
  end

  # Jump back to the top the inner most for_arg loop and process the
  # next argument.
  def for_next()
    debug "for_next()"
    throw FOR_ARG_LABEL, FOR_AGAIN
  end

  def maybe(*vals, &block)
    vals.length == 0 and die "maybe() requires at least one argument."

    return if current_consumed?
    debug {"[maybe](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      # If we're at cursor, just add the candidates.
      if at_cursor?
        debug {" at_cursor: adding candidate(s)."}
        candidates vals[0]
        return
      end

      if !match? vals[0], arg
        return
      end

      # Otherwise, eat words.
      debug {"maybe: found a match."}
      consume

      debug_indent do
        1.upto(vals.length - 1) do |i|
          debug {"maybe(): processing arg ##{i} #{vals[i].inspect}"}
          next_arg
          consume
          if at_cursor?
            candidates vals[i]
            finish
          end
        end
      end

      if block
        next_arg
        debug_indent do
          block.call
        end
      end
    end
  end

  def otherwise(&block)
    block or die "otherwise() requires a block."

    maybe(//) do
      block.call
    end
  end

  def next_arg_must(*vals, &block)
    vals.length == 0 and die "next_arg_must() requires at least one argument."

    debug {"[next_arg_must](#{index}/#{cursor_index}): #{vals}#{block ? " (has block)" : ""}"}

    debug_indent do
      next_arg
      consume

      (vals.length).times do |n|
        if at_cursor?
          candidates vals[n]
          finish
        end
        consume
        next_arg
      end
    end
  end

  def finish()
    block_given? and die "finish() doesn't take a block."
    debug "finish()"
    throw FINISH_LABEL
  end

  # If the cursor arg starts with "$", then see if it's expandable.
  def _maybe_handle_variable()
    arg = cursor_orig_arg

    debug { "_maybe_handle_variable(): arg=#{arg}" }

    # First, see if the current arg may be a prefix of an environmental
    # variable, in which case we can complete.
    var_name = proxy.variable_completable?(arg)
    if var_name
      debug { "Maybe variable: #{var_name}" }
      env.keys.each do |k|
        if k.has_prefix?(var_name)
          candidate("\e$" + k + "\b") # Raw candidate
        end
      end
      return
    end

    # Next, see if the current arg contains an "expandable" environmental
    # variable. e.g. on bash, $HOME/[TAB] will expand to /home/USER/.
    var_name = proxy.variable_expandable?(arg)
    if var_name
      debug "Maybe variable: #{var_name}"
      value = env[var_name]
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

      # If the cursor arg starts with a variable name, we want to
      # complete or expand it.
      _maybe_handle_variable

      # Bash unfortunately calls a completion function even after < and >.
      # Give the proxy a chance to detect it and do a filename completion.
      proxy.maybe_override_candidates

      # If no one generated candidates yet, let the user-defined code
      # generates some.
      if !has_candidates?
        catch FINISH_LABEL do
          debug "Starting the user block."

          # Start from the first argument, unconsumed.
          @index = 1
          unconsume

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
  def do_completion(cursor_pos, args, line:nil, point:nil, ignore_case:false, &b)
    b or die "do_completion() requires a block."
    $complete_ignore_case = ignore_case
    proxy = get_proxy
    engine = CompletionEngine.new proxy, args, cursor_pos, ignore_case, line, point
    proxy.engine = engine

    debug <<~EOF
        OrigArgs: #{engine.orig_args.join ", "}
        Args: #{engine.args.join ", "}
        Index: #{engine.cursor_index}
        Current: #{engine.cursor_arg}
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
        args = ARGV
        do_completion cursor_pos, args, line:line, point:point, ignore_case: ignore_case, &b
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
