#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pathname'
require 'pp'

# Can also be enabled with -d.
$debug_file = ENV['COMPLETER_DEBUG']
$debug = $debug_file ? true : false
$debug_file ||= "/tmp/completer-debug.txt"
$debug_out = nil

# Whether completion is being performed in case-insensitive mode.
# For simplicity, we just use a global var.
$complete_ignore_case = false

=begin
TODOs

- Nested state should have a fully-qualified name too.

- Propagate shell variables and jobs to completer somehow

Feed "declare -p" to the command from the bash side.

- Sort candidates?

================================================================================
- Handling ~

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

    # True if a list contains a value, or
    def contains(list_or_str, val)
      if list_or_str.instance_of? String
        return list_or_str == val
      else
        return list_or_str.include?(val)
      end
    end

    # Takes a String or a Candidate and return as a Candidate.
    def as_candidate(value, completed: nil, help: nil)
      if value.instance_of? Candidate
        return value
      elsif value.instance_of? String
        # If a string contains a TAB, the following section is a
        # help string.
        (candidate, s_help) = value.split(/\t/, 2)

        # If a candidate ends with an CR, it's not a completed
        # candidate.
        s_completed = true
        if candidate =~ /\r$/
          candidate.chomp("\r")
          s_completed = false
        end
        # If one is provided as an argument, use it.
        help = s_help if help == nil
        completed = s_completed if completed == nil

        return Candidate.new(candidate, completed:completed, help:help)
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
      if $complete_ignore_case
        return self.downcase.start_with? prefix.downcase
      else
        return self.start_with? prefix
      end
    end

    # Build a candidate from a String.
    def to_candidate(completed: nil, help: nil)
      return Kernel.as_candidate(value, completed, help)
    end
  end # refine String
end

using CompleterRefinements

# Represents a single candidate.
class Candidate
  using CompleterRefinements

  def initialize(value, completed: true, help: "")
    value or die "Empty candidate detected."

    @value = value.chomp
    @completed = completed
    @help = help
  end

  # The candidate text.
  attr_reader :value

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

  def install(commands, script, ignore_case)
    command = commands[0]
    func = "_#{command.gsub(/[^a-z0-9]/i) {|c| "_" + c.ord.to_s(16)}}_completion"

    debug "Installing completion for '#{command}', function='#{func}'"

    script_file = File.expand_path $0

    debug_flag = debug ? "-d" : ""
    ignore_case_flag = ignore_case ? "-i" : ""

    puts <<~EOF
        function __completer_context_passer {
            declare -p
            echo -n "#{SECTION_SEPARATOR}"
            jobs
        }

        function #{func} {
          local IFS='
        '
          COMPREPLY=( $(__completer_context_passer |
              ruby -x "#{script_file}" #{debug_flag} #{ignore_case_flag} -c "$COMP_CWORD" "${COMP_WORDS[@]}") )
        }
        EOF

    commands.each do |c|
      puts "complete -o nospace -F #{func} #{c}"
    end
  end

  def stert_completion()
    (vars, jobs) = $stdin.read.split(SECTION_SEPARATOR)
    vars.split /\n/ do |sec|
      if line =~ /^declare\s+(\S+)\s+([^=]+)\=(.*)$/ then
      end
    end
  end

  # Return as a candidate string for bash.
  # Note bash can't show a help string.
  def add_candidate(candidate)
    s = shescape(candidate.value)
    s += " " if candidate.completed
    puts s
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
class CompleterEngine
  using CompleterRefinements

  START = "start"

  def initialize(proxy, orig_words, index, ignore_case)
    @proxy = proxy

    @orig_words = orig_words

    # All words in the command line.
    @words = orig_words.map { |w| unshescape(w.expand_home) }

    # Cursor word index; 0-based.
    @cursor_index = index

    # Whether do case-insensitive comparison or not;
    # this comes from the -i option.
    @ignore_case = ignore_case

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

  attr_reader *%i(state cursor_index ignore_case position orig_words words)

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

  # Return the word relative to position. word() returns the current
  # word, and word(-1) returns the previous word.
  def word(i = 0)
    return nil if prescan?
    i += @position
    return "" if i < 0 || i >= @words.length
    return @words[i]
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

    candidates on_word if on_word

    if on_word and on_word != word
      return
    end

    b = @states[state_name]
    b or abort "state #{state_name} not found."
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

  # Clear all the candidates that have been added so far.
  def clear_candidates()
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
  def add_state(name, &b)
    b or die "add_state() requires a block."
    return unless prescan?
    @states[name] and die "State #{name} is already defined."

    @states[name] = b
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
    if contains flags, word(-1)
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

  # Entry point.
  def run_completion(&b)
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

    # Print the collected candidates.
    @candidates.each do |c|
      @proxy.add_candidate c
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
  def do_completion(ignore_case, &b)
    b or die "do_completion() requires a block."
    $complete_ignore_case = ignore_case
    word_index = ARGV.shift.to_i
    words = ARGV
    cc = CompleterEngine.new get_proxy, words, word_index, ignore_case

    debug <<~EOF
        OrigWords: #{cc.orig_words.join ", "}
        Words: #{cc.words.join ", "}
        Index: #{cc.cursor_index}
        Current: #{cc.cursor_word}
        EOF

    cc.run_completion &b
  end

  # Main
  public
  def real_main(&b)
    ignore_case = false

    OptionParser.new { |opts|
      opts.banner = "Usage: [OPTIONS] command-name"

      # Note "-c" must be the last option; otherwise other flags such as
      # "-i" "-d" will be ignored.
      opts.on("-c", "Perform completion (shouldn't be used directly)") do
        do_completion ignore_case, &b
        return
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
