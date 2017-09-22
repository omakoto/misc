#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pathname'
require 'pp'

# Can also be enabled with -d.
$debug_file = ENV['COMPLETER_DEBUG']
$debug = $debug_file ? true : false

# Debug output goes to this file.
$debug_file ||= "/tmp/bashcomp-debug.txt"
FileUtils.rm($debug_file, force:true)

# Stuff used by the core as well as the engine.

# Shod debug output.
public
def debug(*msg, &b)
  if $debug
    # If stdout is TTY, assume the script is executed directly for
    # testing, and write log to stderr.
    if $stdout.tty?
      $stderr.puts msg
    else
      open $debug_file, "a" do |o|
        o.puts msg
      end
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
public
def shescape(arg)
  if arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/
      return "'" + arg.gsub(/'/, "'\\\\''") + "'"
  else
      return arg;
  end
end

# Shell-unescape a single token.
public
def unshescape(arg, expand_home: true)
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

# Same as c.start_with?(prefix), except it can do case-insensitive
# comparison when needed.
public
def has_prefix(c, prefix, ignore_case:)
  if ignore_case
    return c.downcase.start_with? prefix.downcase
  else
    return c.start_with? prefix
  end
end

class Candidate
  def initialize(value, completed: true, help: "")
    value or die "Empty candidate detected."
    @value = value.chomp
    @completed = completed
    @help = help
  end

  attr_reader *%i(value completed help)

  # Return as a candidate string for bash.
  # Note bash can't show a help string.
  def to_bash_candidate()
    ret = shescape(@value)
    ret += " " if @completed
    return ret
  end

  def start_with?(prefix, ignore_case:)
    return Kernel.has_prefix(@value, prefix, ignore_case:ignore_case)
  end

  def as_candidate()
    return self
  end
end

# Grr, respond_to? doesn't support refinements...
# module StringCandidate
#   refine String do
#     def as_candidate()
#       return Candidate.new(self, completed:true, help:"")
#     end
#   end
# end
#
# using StringCandidate

def as_candidate(value)
  if value.instance_of? Candidate
    return value
  elsif value.instance_of? String
    return Candidate.new(value, completed:true, help:"")
  else
    return nil
    # die "Can't treat '#{value.inspect} as a candidate."
  end
end


# def c(value)
#   return Candidate.new(value)
# end

# Return true if a given path is a directory and not empty.
def is_non_empty_dir(f)
  begin
    return File.directory?(f) && !Dir.empty?(f)
  rescue
    # Just ignore any errors.
    return false
  end
end

# Read all lines from a file, if exists.
def read_file_lines(file)
  begin
    file.sub!(/^~\//, "#{Dir.home}/")
    return open(file, "r").read.split(/\n/);
  rescue
    # ignore errors
    return []
  end
end

START = "start"

# This class is the DSL engine.
class CompleterEngine
  def initialize(words, index, ignore_case)
    # All words in the command line.
    @words = words
    # Current word index at the cursor; 0-based.
    @cur_index = index

    # Whether do case-insensitive comparison or not;
    # this comes from the -i option.
    @ignore_case = ignore_case

    # Current state.
    @state = START

    # All the defined states and their blocks.
    @states = {}

    # @pass
    # 0: Pre-scan; just collect all states.
    # 0 < @pass < cur_index: Scanning, don't generate candidates yet.
    # @pass == cur_index: Current word. Generate candidates.
    @pass = 0

    # Current user-defined block to execute.
    # Start with the block that's passed to Completer.define(),
    # and changes when the current state changes.
    @current_block = nil;

    # Candidate collected so far. All the candidates are written
    # out at once at the end.
    # Call clear_candidates() to clear it.
    @candidates = []
  end

  attr_reader *%i(state cur_index ignore_case pass words)

  # index is an alias of pass.
  alias index pass

  # Whether in the precan mode, i.e. pass == 0.
  # During prescan, we execute all state blocks in order to collect
  # all states.
  def prescan?()
    return @pass == 0
  end

  # Whether we're at the current word, i.e. pass == cur_index.
  def current?()
    return @pass == @cur_index
  end

  # Return the command name, such as "adb", "cargo" or "go".
  def command()
    return @words[0]
  end

  # Returns the current word in the command line.
  def current_word()
    return (@words[@cur_index] or "")
  end

  # Define a "begin" block, which will be executed only once
  # during prescan.
  def init(&b)
    return unless prescan?

    b.call()
  end

  # Finish the completion. No further candidates will be provided
  # once it's called.
  def finish()
    return if prescan?

    throw :FinishCompletion
  end

  # Return the word relative to current. word() returns the current
  # word, and word(-1) returns the previous word.
  def word(i = 0)
    return nil if prescan?
    i += @pass
    return "" if i < 0 || i >= @words.length
    return @words[i]
  end

  # Clear all the candidates that have been added so far.
  def clear_candidates()
    @candidates = []
  end

  # Skip the rest of the code in the block and move to the
  # next word.
  def next_word()
    throw :NextWord
  end

  # Same as c.start_with?(prefix), except it does case-insensitive
  # comparison when needed.
  def start_with?(c, prefix)
    Kernel.has_prefix(c, prefix, ignore_case: ignore_case)
  end

  # Add a single candidate.
  def _candidate_single(arg)
    return unless current?
    return unless arg
    die "#{arg.inspect} is not a Candidate" unless arg.instance_of? Candidate
    return unless arg.value
    return unless arg.start_with? current_word, ignore_case: ignore_case

    @candidates.push(arg)
  end

  # Push candidates.
  # "args" can be a string, an array of strings, or a proc.
  def candidates(*args, &b)
    return unless current?

    args.each {|arg|
      c = as_candidate(arg)
      if c
        _candidate_single c
      elsif arg.respond_to? :each
        arg.each {|x| candidates x}
      elsif arg.respond_to? :call
        candidates arg.call()
      end
    }
    if b
      candidates(b.call())
    end
  end

  def cand(value, completed: true, help: "")
    return Candidate.new(value, completed:completed, help:help);
  end

  # flags() is an alias of candidates().
  alias flags candidates

  # Add a new state.
  def add_state(name, &b)
    b or die "Must pass a block to add_state()."
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
    elsif state_name == word
      next_state state_name
    end
  end

  # Move to a state.
  def next_state(state_name)
    if !prescan?
      b = @states[state_name]
      b or abort "state #{state_name} not found."
      @current_block = b
      debug "State -> #{state_name}"
      next_word
    end
  end

  # Define an option that takes an argument, which can be
  # either optional or mandatory.
  def option(flag, arg_candidates, arg_optional: false)
    return unless current?

    # If the previous word was the flag, then add the
    # candidates for the argument.
    if word(-1) == flag

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
    candidates flag
  end

  # Accept files.
  def matched_files()
    return unless current?

    ret = []

    # Get the directory from the word.
    dir = word.sub(%r([^\/]*$), "")
    dir = "." if dir.length == 0
    Pathname.new(dir).children.each do |f|
      path = f.to_s
      path += "/" if f.directory?
      ret.push(cand(path, completed: !is_non_empty_dir(f)))
    end

    return ret
  end

  # Entry point.
  def run(&b)
    @current_block = b

    # Start from pass-0 (prescan), look at each word at
    # index 1, 2, ... until the current word.
    catch :FinishCompletion do
      (0 .. @cur_index).each do |pass|
        @pass = pass
        debug "Pass -> #{@pass} \"#{word}\""
        catch :NextWord do
          self.instance_eval &@current_block
        end
      end
    end

    # Print the collected candidates.
    @candidates.each do |c|
      puts c.to_bash_candidate
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
    command = commands[0]
    func = "_#{command}_completion".gsub(/[^a-z0-9_]/i, "_")

    debug "Installing completion for '#{command}', function='#{func}'"

    script_file = File.expand_path $0

    debug_flag = debug ? "-d" : ""
    ignore_case_flag = ignore_case ? "-i" : ""

    puts <<~EOF
        function #{func} {
          local IFS='
        '
          COMPREPLY=( $(ruby -x "#{script_file}" #{debug_flag} #{ignore_case_flag} -c "$COMP_CWORD" "${COMP_WORDS[@]}") )
        }
        EOF

    commands.each do |c|
      puts "complete -o nospace -F #{func} #{c}"
    end
  end

  # Perform completion
  def do_completion(ignore_case, &b)
    word_index = ARGV.shift.to_i
    words = ARGV.map { |w| unshescape w }
    cc = CompleterEngine.new words, word_index, ignore_case

    debug <<~EOF
        OrigWords: #{ARGV.map {|x| shescape x}.join ", "}
        Words: #{words.map {|x| shescape x}.join ", "}
        Index: #{word_index}
        Current: #{words[word_index]}
        EOF

    cc.run &b
  end

  # Main
  public
  def real_main(&b)
    ignore_case = false

    OptionParser.new { |opts|
      opts.banner = "Usage: [OPTIONS] command-name"

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
