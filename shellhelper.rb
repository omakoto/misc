#!/usr/bin/env ruby

# $DEBUG = true

=begin
Basic shell escape/unescape helper.

It doesn't support complicated cases like "$(echo "o  k")".

See also:
http://pubs.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html
=end

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
def unshescape(arg)
  if arg !~ /[\'\"\\]/
    return arg
  end

  ret = ""
  pos = 0
  while pos < arg.length
    ch = arg[pos]

    case
    when ch == "'"
      pos += 1
      while pos < arg.length
        ch = arg[pos]
        pos += 1
        if ch == "'"
          break
        end
        ret += ch
      end
    when ch == '"'
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
    when ch == '\\'
      pos += 1
      if pos < arg.length
        ret += arg[pos]
        pos += 1
      end
    when (ch == '$') && (arg[pos+1] == "'") # C-like string
      pos += 2
      ret, pos = _unescape_clike(arg, ret, pos)
    else
      ret += ch
      pos += 1
    end
  end

  return ret
end

def _unescape_clike(arg, ret, pos)
  while pos < arg.length
    ch = arg[pos]
    pos += 1
    case ch
    when "'"
      break
    when "\\"
      ch = arg[pos]
      pos += 1
      case
      when ch == '"';    ret += '"'
      when ch == "'";    ret += "'"
      when ch == '\\';   ret += '\\'
      when ch == 'a';    ret += "\a"
      when ch == 'b';    ret += "\b"
      when ch == 'e';    ret += "\e"
      when ch == 'E';    ret += "\e"
      when ch == 'f';    ret += "\f"
      when ch == 'n';    ret += "\n"
      when ch == 'r';    ret += "\r"
      when ch == 't';    ret += "\t"
      when ch == 'v';    ret += "\v"
      when ch == 'c'
        ch2 = arg[pos]&.downcase&.ord
        pos += 1
        code = ch2 ? (ch2 - 'a'.ord + 1) : 0
        ret << code.chr
      when (ch == 'x') && /\G([0-9a-fA-F]{1,2})/.match(arg, pos)
        code = $1
        pos += $1.length
        ret << code.to_i(16).chr("utf-8")
      when (ch == 'u') && /\G([0-9a-fA-F]{1,4})/.match(arg, pos)
        code = $1
        pos += $1.length
        ret << code.to_i(16).chr("utf-8")
      when (ch == 'U') && /\G([0-9a-fA-F]{1,8})/.match(arg, pos)
        code = $1
        pos += $1.length
        ret << code.to_i(16).chr("utf-8")
      when /\G([0-7]{1,3})/.match(arg, pos - 1)
        code = $1
        pos += $1.length - 1
        ret << code.to_i(8).chr("utf-8")
      else
        ret << "\\"
        ret << ch
      end
    else
      ret << ch
    end
  end
  return [ret, pos]
end

def shsplit(arg)
  ret = []
  c = CommandLine.new(arg)
  c.tokens.each do |token|
    ret << token if token =~ /^\S/
  end
  return ret
end

def is_shell_op(arg)
  return arg =~ /^[\;\<\>\|\&\!\(\)]+$/
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
    @tokens = nil # [] of STRING (token or spaces)
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

  SHELL_OPERATORS = %r!^ (?:
      \;      |
      [\|\&\<\>]+   |
      \(      |
      \)      ) $!x

  private
  def tokenize()
    @tokens = []
    raw_tokens = @command_line.scan(%r[
      (?:
      \s+                      # Whitespace
      | \' [^\']* \'?          # Single quote
      | \" (?: \\. | [^\"] )* \"? # Double-quote
      | \$\'(?:                # C-like string
          \\[\"\'\\abeEfnrtv]      # Special character
          | \\c.                   # Control character
          | \\x[0-9a-fA-F]{0,2}
          | \\u[0-9a-fA-F]{0,4}
          | \\U[0-9a-fA-F]{0,8}
          | [^\']
          )* \'?
      | .
      )
      ]x)

    # puts raw_tokens.inspect if $DEBUG

    pos = 0
    current = ""

    push_token = lambda do
      if current.length > 0
        @tokens.push current
        current = ""
      end
    end

    raw_tokens.each do |token|
      len = token.length
      break if len == 0

      if token =~ /^\s/ # Whitespace?
        push_token.call
        @tokens.push token
      elsif current.length == 0 && token == "#" # Comment?
        # Comment, eat up all the string.
        @tokens.push @command_line[pos..-1]
        break
      elsif ((current.length == 0) && # Line head '!' is special.
          (token == "!") &&
          ((@tokens.length == 0) || (@tokens[0] =~ /^\s+$/)))
        current += token
        push_token.call
      else
        current_is_op = current =~ SHELL_OPERATORS
        if ((current_is_op && (current + token) !~ SHELL_OPERATORS) ||
            (!current_is_op && token =~ SHELL_OPERATORS))
          push_token.call
        end
        current += token
      end
      pos += len
    end
    push_token.call
  end
end
