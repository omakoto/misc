#!/usr/bin/env ruby

require 'optparse'
require 'stringio'

#-----------------------------------------------------------
# Global stuff.
#-----------------------------------------------------------

$self_path = File.expand_path(__FILE__)
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

#-----------------------------------------------------------
# Completion context
#-----------------------------------------------------------

class CompletionContext
    def initialize(words, index, ignore_case)
        @words = words
        @index = index
        @current = words[index]
        @ignore_case = ignore_case
    end

    attr_reader *%i(words index current ignore_case)
end

$cc = nil; # CompletionContext

#-----------------------------------------------------------
# Install completion
#-----------------------------------------------------------

def do_install(command, script_file, ignore_case)
  script = script_file.read

  func = "_#{command}_completion".gsub(/[^a-z0-9_]/i, "-")

  debug "Installing completion for '#{command}', function='#{func}'"

  debug_flag = debug ? "-d" : ""
  ignore_case_flag = ignore_case ? "-i" : ""

  puts <<~EOF
      function #{func} {
        IFS='
'
        COMPREPLY=( $(ruby "#{$self_path}" #{debug_flag} #{ignore_case_flag} -c "$COMP_CWORD" "${COMP_WORDS[@]}" <<'SCRIPT_END'
#{script}
SCRIPT_END
) )
      }
      complete -o nospace -F #{func} #{command}
      EOF
end

#-----------------------------------------------------------
# Perform completion
#-----------------------------------------------------------

def do_completion(script, ignore_case)
  word_index = ARGV.shift.to_i
  words = ARGV.map { |w| unshescape w }
  $cc = CompletionContext.new words, word_index, ignore_case

  debug do
    open "/tmp/bashcomp-debug.txt", "w" do |o|
      o.puts <<~EOF
          OrigWords: #{ARGV.map {|x| shescape x}.join ", "}
          Index: #{$cc.index}
          Words: #{$cc.words.map {|x| shescape x}.join ", "}
          Current: '#{shescape $cc.current}'
          Script:
          #{script}
          EOF
    end
  end

  eval script
end

#-----------------------------------------------------------
# Main
#-----------------------------------------------------------

def script_main()
  ignore_case = false
  OptionParser.new do |opts|
    opts.banner = "Usage: [OPTIONS] command-name"

    opts.on("-c", "Perform completion (shouldn't be used directly)") do
      script = $stdin.read
      do_completion script, ignore_case
      exit 0
    end

    opts.on("-i", "Enable ignore-case completion") do
      ignore_case = true
    end

    opts.on("-d", "Enable debug mode") do
      $debug = true
    end
  end.parse!

  command_name = ARGV.shift or abort("#{$0}: Missing command name.")

  do_install command_name, ARGF, ignore_case
  exit 1
end

#-----------------------------------------------------------
# Stuff used by scripts.
#-----------------------------------------------------------

def has_prefix(a, b, ignore_case)
  if ignore_case
    return a.downcase.start_with? b.downcase
  else
    return a.start_with? b
  end
end

def candidate(arg, add_space = true)
  if has_prefix arg, $cc.current, $cc.ignore_case then
    arg.chomp!
    c = shescape(arg)
    if add_space
      c += " "
    end
    puts c
  end
end

script_main()
