#!/usr/bin/env ruby

require 'optparse'
require 'pp'

#-----------------------------------------------------------
# Global stuff.
#-----------------------------------------------------------

$debug = ENV['BASHCOMP_DEBUG'] == "1"

def debug(*msg, &b)
  if $debug
    $stderr.puts msg
    b.call if b
    return 1
  else
    return 0
  end
end

#-----------------------------------------------------------
# Stuff used by scripts.
#-----------------------------------------------------------
module Utilities
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

class CompletionContext
  include Utilities

  START = "start"
  EMPTY = "end"

  def initialize(words, index, ignore_case)
    @state = START
    @words = words
    @cur_index = index
    @cur_word = @words[index]
    @cur_word = "" unless @cur_word;
    @ignore_case = ignore_case
    @index = 0

    @states = {}

    @prescan = true

    # END state is an empty block.
    add_state EMPTY do
    end
  end

  attr_reader *%i(state cur_index cur_word ignore_case i)

  def prescan?()
    return @prescan
  end

  def word(i)
    i += @cur_index
    return nil if i < 0 || i >= @words.length
    return @words[i]
  end

  def words()
    return @words
  end

  def add_state(name, &b)
    @states[name] = b
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
    return if prescan?
    return unless arg

    if has_prefix arg, cur_word then
      arg.chomp!
      c = shescape(arg)
      if add_space
        c += " "
      end
      puts c
    end
  end

  # Push candidates.
  def candidates(*args, add_space: true, &b)
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

  def get_match_files()
    dir = cur_word.sub(%r([^\/]*$), "") # Remove the last path section.

    %x(command ls -dp1 '#{shescape(dir)}'* 2>/dev/null).split(/\n/).each { |f|
      candidates(f, add_space: !is_non_empty_dir(f))
    }
  end

  def state(name, auto_transition: true, &b)
    if prescan?
      add_state name, &b
      self.instance_eval &b
    else
    end
  end

  def option(name, next_candidate, optional: false)
  end

  def allow_files()
  end

  def to_state(state_name)
  end

  def run(&b)
    # First, run the block in the pre-scan mode.
    @prescan = true
    self.instance_eval &b

    debug { pp(self) }
  end
end

#-----------------------------------------------------------
# Core class
#-----------------------------------------------------------
class BashComp
  include Utilities

  private

  def __initialize__
  end

  def die(*msg)
    abort "#{__FILE__}: " + msg.join("")
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

    debug do
      open "/tmp/bashcomp-debug.txt", "w" do |o|
        o.puts <<~EOF
            OrigWords: #{ARGV.map {|x| shescape x}.join ", "}
            Words: #{cc.words.map {|x| shescape x}.join ", "}
            Index: #{cc.cur_index}
            Current: '#{shescape cc.cur_word}'
            EOF
      end
    end

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

    command_name = ARGV.shift or die("Missing command name.")

    do_install command_name, $0, ignore_case
  end

  # The entry point called by the outer script.
  public
  def self.define(&b)
    b or die "define_completion() requires a block."

    instance = BashComp.new()
    instance.real_main &b
  end
end
