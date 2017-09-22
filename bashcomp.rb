#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'pp'

# Can also be enabled with -d.
$debug = ENV['BASHCOMP_DEBUG'] == "1"

# Debug output goes to this file.
DEBUG_FILE = "/tmp/bashcomp-debug.txt"
FileUtils.rm(DEBUG_FILE, force:true)

#-----------------------------------------------------------
# Stuff used by scripts.
#-----------------------------------------------------------
module Utilities
  # Shod debug output.
  def debug(*msg, &b)
    if $debug
      open DEBUG_FILE, "a" do |o|
        o.puts msg
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

  def is_non_empty_dir(f)
    begin
      return File.directory?(f) && !Dir.empty?(f)
    rescue
      # Just ignore any errors.
      return false
    end
  end
end

#-----------------------------------------------------------
# Completion context
#-----------------------------------------------------------

START = "start"
EMPTY = "end"

class CompletionContext
  include Utilities

  def initialize(words, index, ignore_case)
    @state = START
    @words = words
    @cur_index = index
    @ignore_case = ignore_case
    @index = 0

    @states = {}

    # @pass
    # 0: Pre-scan; just collect all states.
    # 0 < @pass < cur_index: Scanning, don't generate candidates yet.
    # @pass == cur_index: Current word. Generate candidates.

    @pass = 0

    @current_block = nil;

    @candidates = []

    # END state is an empty block.
    add_state EMPTY do
    end
  end

  attr_reader *%i(state cur_index ignore_case pass)

  def prescan?()
    return @pass == 0
  end

  def current?()
    return @pass == @cur_index
  end

  # Return the command name.
  def command()
    return @words[0]
  end

  def word(i = 0)
    return nil if prescan?
    i += @pass
    return "" if i < 0 || i >= @words.length
    return @words[i]
  end

  def words()
    return @words
  end

  def add_state(name, &b)
    prescan? or die "add_state can be only called during prescan."
    @states[name] = b
  end

  def clear_candidates()
    @candidates = []
  end

  def move_to_next_word()
    throw :BlockExecute
  end

  # Same as a.start_with?(b), except it can do case-insensitive comparison.
  def has_prefix(a, b)
    if ignore_case
      return a.downcase.start_with? b.downcase
    else
      return a.start_with? b
    end
  end

  def _candidate_single(arg, add_space: true)
    return unless current?

    return unless arg

    if has_prefix arg, word then
      arg.chomp!
      # Note, because of the additional space, we shescape at this point,
      # not when we print it.
      c = shescape(arg)
      if add_space
        c += " "
      end
      @candidates.push c
    end
  end

  # Push candidates.
  def candidates(*args, add_space: true, &b)
    return unless current?

    args.each {|arg|
      if arg.instance_of? String
        _candidate_single arg, add_space: add_space
      elsif arg.respond_to? :each
        arg.each {|x| candidates x, add_space: add_space}
      elsif arg.respond_to? :call
        candidates arg.call(), add_space: add_space
      end
    }
    if b
      candidates(b.call(), add_space: add_space)
    end
  end

  alias flags candidates

  def get_match_files(prefix)
    dir = prefix.sub(%r([^\/]*$), "") # Remove the last path section.

    %x(command ls -dp1 '#{shescape(dir)}'* 2>/dev/null).split(/\n/).each { |f|
      candidates(f, add_space: !is_non_empty_dir(f))
    }
  end

  def state(state_name, auto_transition: true, &b)
    if prescan?
      add_state state_name, &b
      self.instance_eval &b
    elsif auto_transition and state_name == word
      to_state state_name
    end
  end

  def option(flag, next_candidates, optional: false)
    return unless current?

    if word(-1) == flag
      clear_candidates unless optional
      candidates next_candidates
      move_to_next_word unless optional
    end

    candidates flag

  end

  def take_files()
    return unless current?
    get_match_files word
  end

  def to_state(state_name)
    if !prescan?
      b = @states[state_name]
      b or abort "state #{state_name} not found."
      @current_block = b
      debug "State -> #{state_name}"
      move_to_next_word
    end
  end

  def run(&b)
    @current_block = b

    # First, run the block in the pre-scan mode.
    (0 .. @cur_index).each do |pass|
      @pass = pass
      debug "Pass -> #{@pass} \"#{word}\""
      catch :BlockExecute do
        self.instance_eval &@current_block
      end
    end

    # Print the collected candidates.
    @candidates.each do |v|
      puts v
    end
  end
end

#-----------------------------------------------------------
# Core class
#-----------------------------------------------------------
class BashComp
  include Utilities

  def __initialize__
  end

  # Install completion
  def do_install(command, script, ignore_case)
    func = "_#{command}_completion".gsub(/[^a-z0-9_]/i, "-")

    debug "Installing completion for '#{command}', function='#{func}'"

    script_file = File.expand_path $0

    debug_flag = debug ? "-d" : ""
    ignore_case_flag = ignore_case ? "-i" : ""

    puts <<~EOF
        function #{func} {
          IFS='
        '
          COMPREPLY=( $(ruby -x "#{script_file}" #{debug_flag} #{ignore_case_flag} -c "$COMP_CWORD" "${COMP_WORDS[@]}") )
        }
        complete -o nospace -F #{func} #{command}
        EOF
  end

  # Perform completion
  def do_completion(ignore_case, &b)
    word_index = ARGV.shift.to_i
    words = ARGV.map { |w| unshescape w }
    cc = CompletionContext.new words, word_index, ignore_case

    debug <<~EOF
        OrigWords: #{ARGV.map {|x| shescape x}.join ", "}
        Words: #{words.map {|x| shescape x}.join ", "}
        Index: #{word_index}
        Current: #{words[word_index]}
        EOF

    cc.run &b
  end

  # Main
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

    command_name = ARGV.shift or die("Missing command name.")

    do_install command_name, $0, ignore_case
  end

  # The entry point called by the outer script.
  def self.define(&b)
    b or die "define_completion() requires a block."

    instance = BashComp.new()
    instance.real_main &b
  end
end
