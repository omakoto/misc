#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pathname'
require 'pp'

require 'rubygems' # For version check on<1.9
abort "#{$0.sub(/^.*\//, "")} requires ruby >= 2.4" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4')

$debug_file = ENV['COMPLETER_DEBUG']
$debug = $debug_file ? true : false
$debug_file ||= "/tmp/completer-debug.txt"
$debug_out = nil

=begin
- To enable debug output,
export COMPLETER_DEBUG=/tmp/completer-debug.txt
- Can also be enabled with -d.
=end

# Whether completion is being performed in case-insensitive mode.
# For simplicity, we just use a global var.
$complete_ignore_case = false

=begin
TODOs

- unshescape doens't support $'...' yet -> it's probably not important
in completion usecases.

- Handle jobs too.

UNTODOs.
- COMP_WORDBREAKS is already handled by readline.
- The following case doesn't work, but '=' is normally optional, so
  no strong reason to support it.

--context [TAB]
--context=[TAB]
--context 123 /e[TAB]
--context=132 /e[TAB]

================================================================================
- Handling of "~"

$ echo ~
/usr/local/google/home/omakoto

$ echo ~a
~a

$ echo ~root
/root

$ echo \~
~

$ echo a~
a~

$ echo ~/
/usr/local/google/home/omakoto/

$ echo ~\/
~/

# -> So, "~" should expand, and %r(^~/) should expand too, but not when ~ is followed by
other characters or "\/".


echo ~[TAB] -> Expand to all user directories. Don't have to support it.

echo ~/[TAB] -> Expand to home dir files.

================================================================================

Sample jobs output

$ jobs # sample jobs output
[1]   Running                 sleep 100000 &
[2]-  Running                 sleep 100000 &
[3]+  Running                 sleep 100000 &

================================================================================
$VARIABLE expansion

 $ANDROID_[TAB] -> shows candidates

 $HOME[TAB] -> $HOME [<-space inserted]

 $HOME/[TAB] -> /home/omakoto/[CURSOR HERE] -- expands only if it's a directory

=end

# Stuff used by the core as well as the engine.


module CompleterRefinements
  refine Kernel do
    # Shod debug output.
    def debug(*msg, &b)
      if $debug
        # If stdout is TTY, assume the script is executed directly for
        # testing, and write log to stderr.
        if $stdout.tty?
          $stderr.puts msg
        else
          $debug_out = open $debug_file, "w" unless $debug_out
          $debug_out.puts msg
          $debug_out.flush
        end
        b.call if b
        return 1
      else
        return 0
      end
    end

    def die(*msg)
      abort "#{__FILE__}: " + msg.join("")
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
      if arg !~ / [ \' \" \\ ] /x
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

    # True if list_or_str_or_reg is a string and is equal to val,
    # or supports "includes?" and contains, or is a Regexp and matches
    # val.
    # Note this is intend to detect a flag (e.g. it's used by "option()",
    # so it's always case sensitive.)
    def matches_cs?(list_or_str_or_reg, val)
      return false unless list_or_str_or_reg

      if list_or_str_or_reg.instance_of? String
        return list_or_str_or_reg == val
      elsif list_or_str_or_reg.instance_of? Regexp
        return list_or_str_or_reg.match? val
      elsif list_or_str_or_reg.respond_to? "include?"
        return list_or_str_or_reg.include? val
      else
        die "Unsupported type: #{list_or_str_or_reg.inspect}"
      end
    end

    # Takes a String or a Candidate and return as a Candidate.
    def as_candidate(value, raw:nil, completed: nil, help: nil)
      if value.instance_of? Candidate
        return value
      elsif value.instance_of? String
        # If a string contains a TAB, the following section is a
        # help string.
        (candidate, s_help) = value.split(/\t/, 2)

        # If a candidate starts with a linefeed, it's a raw candidate.
        s_raw = candidate.sub!(/^\f/, "") ? true : false

        # If a candidate ends with an CR, it's not a completed
        # candidate.
        s_completed = candidate.sub!(/\r$/, "") ? false : true

        # If one is provided as an argument, use it.
        raw = s_raw if raw == nil
        completed = s_completed if completed == nil
        help = s_help if help == nil

        return Candidate.new(candidate, raw:raw, completed:completed, help:help)
      else
        return nil
      end
    end

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
        debug e.inspect
        # Just ignore any errors.
        return false
      end
    end

    # Find matching files for a given word.
    def get_matched_files(word, wildcard = "*")
      # Remove the last path component.
      dir = word.sub(%r([^\/]*$), "")

      debug "word=#{word} dir=#{dir} wildcard=#{wildcard}"

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
            cand += "\r" if is_non_empty_dir(path)
          else
            # If it's a file, only add when the basename matches wildcard.
            next unless File.fnmatch(wildcard, path.basename, flag)
            cand = path.to_s
          end
          ret.push(cand)
        end
      rescue SystemCallError => e
        debug e.inspect
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
          cand += "\r" if is_non_empty_dir(path, ignore_files:true)
          ret.push(cand)
        end
      rescue SystemCallError => e
        debug e.inspect
      end

      return ret
    end

    # Read all lines from a file, if exists.
    def read_file_lines(file)
      file = file.expand_home
      return (File.exist? file) ? open(file, "r").read.split(/\n/) : []
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

using CompleterRefinements

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
end

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

    debug "Installing completion for '#{command}', function='#{func}'"

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
        debug "#{flag}: #{name} = #{value}" if debug
        next if flag =~ /[aA]/ # Ignore arrays and hashes
        @env[name] = unshescape value
      end
    end

    # TODO Parse jobs

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
      engine.candidates engine.matched_files
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

# This class is the DSL engine.
class CompletionEngine
  using CompleterRefinements

  START = "start"

  def initialize(proxy, orig_words, index, ignore_case, comp_line, comp_point)
    @proxy = proxy

    @orig_words = orig_words

    # All words in the command line.
    @words = orig_words.map { |w| unshescape(w.expand_home) }

    # Cursor word index; 0-based.
    @cursor_index = index

    # Whether do case-insensitive comparison or not;
    # this comes from the -i option.
    @ignore_case = ignore_case

    # Whole command line
    @comp_line = comp_line

    # Cursor point
    @comp_point = comp_point

    # Current state.
    @state = START

    # All the defined states and their blocks.
    @states = {}

    # @position
    # 0: Pre-scan; just collect all states.
    # 0 < @position < cursor_index: Scanning, don't generate candidates yet.
    # @position == cursor_index: Cursor word. Generate candidates.
    @position = 0

    # Current user-defined block to execute.
    # Start with the block that's passed to Completer.define(),
    # and changes when the current state changes.
    @current_block = nil;

    # Candidate collected so far. All the candidates are written
    # out at once at the end.
    # Call clear_candidates() to clear it.
    @candidates = []
  end

  attr_reader *%i(state cursor_index ignore_case position orig_words words
      comp_line comp_point proxy)

  # Whether in the precan mode, i.e. position == 0.
  # During prescan, we execute all state blocks in order to collect
  # all states.
  def prescan?()
    return @position == 0
  end

  # Whether we're at the cursor word, i.e. position == cursor_index.
  def at_cursor?()
    return @position == @cursor_index
  end

  # Return the command name, such as "adb", "cargo" or "go".
  def command()
    return @words[0]
  end

  # Returns the current word in the command line.
  def cursor_word()
    return (@words[@cursor_index] or "")
  end

  # Returns the current word in the command line.
  def cursor_orig_word()
    return (@orig_words[@cursor_index] or "")
  end

  def _relative_word(ar, i)
    return nil if prescan?
    i += @position
    return "" if i < 0 || i >= ar.length
    return ar[i]
  end

  # Return the word relative to position. word() returns the current
  # word, and word(-1) returns the previous word.
  def word(i = 0)
    return _relative_word(@words, i)
  end

  # Return the original word relative to position. See word() for
  # details.
  def orig_word(i = 0)
    return _relative_word(@orig_words, i)
  end

  # Returns the shell and environmental variables.
  def env()
    return @proxy.env
  end

  # Define a "begin" block, which will be executed only once
  # during prescan.
  def init_block(&b)
    b or die "init() requires a block."
    return unless prescan?

    b.call()
  end

  # Move to a state.
  # When on_word is provided, only move the state when detecting
  # the word.
  def next_state(state_name, on_word:nil)
    return if prescan?

    # This is a little confusing, so removed it.
    #  candidates on_word if on_word and on_word.instance_of? String

    if on_word
      return unless matches_cs? on_word, word
    end

    b = @states[state_name]
    b or die "State #{state_name} not found."
    @current_block = b
    debug "State -> #{state_name}"
    next_word
  end

  # Equivalent to next_state START
  def reset_state(on_word:nil)
    return if prescan?

    next_state START, on_word: on_word
  end

  # Finish the completion. No further candidates will be provided
  # once it's called.
  def finish(on_word:nil)
    return if prescan?

    throw :FinishCompletion
  end

  # Jump to the cursor word. When a completion doesn't involve
  # any state transition and there's no state management,
  # use this to jump to the cursor word.
  def to_cursor()
    return if prescan? or @position == @cursor_index

    @position = @cursor_index - 1
  end

  # Skip the rest of the code in the block and move to the
  # next word.
  def next_word(to_position: nil)
    # The main loop increments @position, so we need -1 here.
    @position = to_position - 1 if to_position

    throw :NextWord
  end

  # Whether any candidate(s) are already registered.
  def has_candidates()
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
    return unless at_cursor?
    return unless arg
    die "#{arg.inspect} is not a Candidate" unless arg.instance_of? Candidate
    return unless arg.value
    if !always
      return unless arg.has_prefix? cursor_word
    end

    @candidates.push(arg)
  end

  # Push candidates.
  # "args" can be a string, an array of strings, or a proc.
  # If always is true, candidates will be always added, even
  # if they don't start with the cursor word.
  def candidates(*args, always:false , &b)
    return unless at_cursor?

    args.each {|arg|
      c = as_candidate(arg)
      debug c.inspect
      if c
        _candidate_single c, always:always
      elsif arg.respond_to? :each
        arg.each {|x| candidates x, always:always}
      elsif arg.respond_to? :call
        candidates(arg.call(), always:always)
      end
    }
    if b
      candidates(b.call(), always:always)
    end
  end

  # flags() is an alias of candidates().
  alias candidate candidates
  alias flag candidates
  alias flags candidates

  # Define a candidate generator function
  def cand_gen(name_sym, &b)
    b or die("cand_gen() requires a block.")
    # Define a function, only during prescan.
    return unless prescan?

    self.class.send :define_method, name_sym do
      # The method should-be no-op unless current.
      b.call if at_cursor?
    end
  end

  # Add a new state.
  # If on_word is not nil,
  def add_state(state_name, on_word:nil, &b)
    b or die "add_state() requires a block."
    if prescan?
      @states[state_name] and die "State #{state_name} is already defined."
      @states[state_name] = b
      return
    end
    if on_word
      next_state state_name if matches_cs? on_word, word
    end
  end

  # Defines a new state, and also automatically move to the
  # state when detecting a word in the command line that is
  # the state name.
  # Useful for handling subcommands, as well as "--".
  def auto_state(state_name, &b)
    if prescan?
      add_state state_name, &b
      self.instance_eval &b
    else
      candidates state_name if at_cursor?
      if state_name == word
        next_state state_name
      end
    end
  end

  # Define an option that takes an argument, which can be
  # either optional or mandatory.
  def options(flags, arg_candidates = [], arg_optional: false)
    return unless at_cursor?

    # If the previous word was the flag, then add the
    # candidates for the argument.
    if matches_cs? flags, word(-1)
      if arg_optional
        # If an argument is optional, then we just add
        # the candidates for the argument, but we still
        # collect all other possible candidates.
        candidates arg_candidates
      else
        # If an argument is mandatory, we only add the
        # candidates for the argument, so clear the collected
        # candidates so far, and don't collect any other
        # arguments (thus "next_word").
        clear_candidates
        candidates arg_candidates
        next_word
      end
    end
    candidates flags
  end

  alias option options

  # Accept files.
  def matched_files(wildcard = "*")
    return unless at_cursor?
    return get_matched_files(word, wildcard)
  end

  alias arg_file matched_files

  # Accept directories.
  def matched_dirs()
    return unless at_cursor?
    return get_matched_dirs(word)
  end

  alias arg_dir matched_dirs

  # Accept an integer.
  def arg_number(allow_negative:false)
    return unless at_cursor?

    if allow_negative
      return unless word =~ /^\-?\d*$/
    else
      return unless word =~ /^\d*$/
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

  # If the cursor word starts with "$", then see if it's expandable.
  def maybe_handle_variable()
    cow = cursor_orig_word

    name = proxy.variable_completable?(cow)
    if name
      debug "Maybe variable: #{name}"
      env.keys.each do |k|
        if k.has_prefix?(name)
          candidate("\f$" + k + "\r") # Raw candidate
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
        value += "\r" if is_non_empty_dir(value)
        candidate value, always:true
      end
    end
  end

  # Entry point.
  def run_completion(&b)
    proxy.start_completion
    begin
    # Move to the cursor position so that candidates() will accept
    # arguments.
    @position = @cursor_index

      # If the cursor word starts with a variable name, we want to
      # complete or expand it.
      maybe_handle_variable

      # Bash unfortunately calls a completion function even after < and >.
      # Give the proxy a chance to detect it and do a filename completion.
      proxy.maybe_override_candidates

      # If no one generated candidates yet, let the user-defined code
      # generates some.
      if !has_candidates
        @current_block = b
        @states[START] = b

        # Start from position-0 (prescan), look at each word at
        # index 1, 2, ... until the current word.
        catch :FinishCompletion do
          @position = 0
          while @position <= @cursor_index do
            debug "Pass -> #{@position} \"#{word}\""
            catch :NextWord do
              self.instance_eval &@current_block
            end
            @position += 1
          end
        end
      end

      # Print the collected candidates.
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

    engine.run_completion &b
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

    Completer.new.real_main &b
  end
end
