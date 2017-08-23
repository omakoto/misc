#!/usr/bin/env ruby

# $DEBUG = true

class InvalidCommandLineError < StandardError
end

#-----------------------------------------------------------
# Shell-escape a single token.
#-----------------------------------------------------------
def shescape(arg)
  if arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/
      return "'" + arg.gsub(/'/, "'\\\\''") + "'"
  else
      return arg;
  end
end

#-----------------------------------------------------------
# Shell-unescape a single token.
#-----------------------------------------------------------
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
      end
    else
      ret += ch
      pos += 1
    end
  end

  return ret
end

#-----------------------------------------------------------
class CommandLine
  def initialize(command_line, pos = -1)
    # Full command line as a single string.
    @command_line = command_line

    # Cursor position, which will be moved by set_token().
    @position = if pos >= 0 then pos else command_line.length end

    # Tokens, including whitespaces, as original strings.
    # (non-unescaped)
    @tokens = nil # [] of [STRING (token or spaces)]
    tokenize
  end

  attr_reader :tokens, :position, :command_line

  # Returns [start, end, TOKEN]
  def get_token(position, get_partial = true)
    start = 0
    @tokens.each {|t|
      len = t.length
      if position <= (start + len)
        # found
        if t =~ /^\s/
          return [position, position, ""]
        else
          if get_partial
            return [start, position, t[0, position - start]]
          else
            return [start, start + len, t]
          end
        end
      end
      start += len
    }
    # Not found.
    return [@command_line.length, @command_line.length, ""]
  end

  def set_token(pos, replacement, set_partial = true)
    target = get_token(pos, set_partial)
    new_command = command_line.dup
    new_command[target[0]...target[1]] = replacement
    new_pos = position
    if new_pos >= target[0]
      new_pos = target[0] + replacement.length
    end
    return CommandLine.new(new_command, new_pos)
  end

  private
  def tokenize()
    @tokens = []
    raw_tokens = @command_line.scan(
        %r{
          (?: \s+ | # Whitespace
              \' [^']* \'? | # Single quoted
              \" (?: [^\"] | \\.) * \"? | # Double quoted
              (?: [^\'\"\s] | \\.) + | # Bare characters
          )
        }x)

    # puts raw_tokens.inspect if $DEBUG

    pos = 0
    current = ""
    in_token = false

    push_token = lambda {
      if in_token
        @tokens.push current
        current = ""
        in_token = false
      end
    }

    raw_tokens.each {|t|
      len = t.length
      break if len == 0
      if t =~ /^\s/ # Whitespace?
        push_token.call
        @tokens.push t

      else # Token?
        in_token = true
        current += t
      end
      pos += len
    }
    push_token.call
  end
end
