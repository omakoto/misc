#!/usr/bin/env ruby2.3

require "test/unit"

# $DEBUG = true

class InvalidCommandLineError < StandardError
end

#-----------------------------------------------------------
def shescape(arg)
  if arg =~ /[^a-zA-Z0-9\-\.\_\/\:\+\@]/
      return "'" + arg.gsub(/'/, "'\\\\''") + "'"
  else
      return arg;
  end
end

class TestShescape < Test::Unit::TestCase
  def test_simple
    assert_equal("", shescape(""))
    assert_equal("a", shescape("a"))
    assert_equal("'a b c'", shescape("a b c"))
    assert_equal("'a '\\'' '\\'''", shescape("a ' '"))
  end
end

#-----------------------------------------------------------
class CommandLine
  def initialize(command_line, pos = -1)
    @command_line = command_line
    @position = if pos >= 0 then pos else command_line.length end
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
        if get_partial
          return [start, position, t[0, position - start]]
        else
          return [start, start + len, t]
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
              ' [^']* '? | # Single quoted
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

class TestCommandLine < Test::Unit::TestCase
  def test_tokenize
    assert_equal([], CommandLine.new("").tokens)
    assert_equal(
        ['abc', '  ', "\'\"\'ab\"dd\""],
        CommandLine.new("abc  \'\"\'ab\"dd\"").tokens)
  end

  def test_rebuild
    assert_equal("", CommandLine.new("").command_line)
    assert_equal("  abc  \'\"\'ab\"dd\"   ",
        CommandLine.new("  abc  \'\"\'ab\"dd\"   ").command_line)
  end

  def test_get_token
    assert_equal([4, 6, "de"], CommandLine.new("abc def").get_token(6, true))
    assert_equal([4, 7, "def"], CommandLine.new("abc def").get_token(6, false))

    assert_equal([4, 7, "def"], CommandLine.new("abc def").get_token(7, true))
    assert_equal([4, 7, "def"], CommandLine.new("abc def").get_token(7, false))

    assert_equal([3, 4, " "], CommandLine.new("abc def").get_token(4, true))
    assert_equal([3, 4, " "], CommandLine.new("abc def").get_token(4, false))

    assert_equal([7, 7, ""], CommandLine.new("abc def").get_token(8, true))
    assert_equal([7, 7, ""], CommandLine.new("abc def").get_token(8, false))
  end

  def check_set_token(expected_str, expected_pos, source_str, source_pos, pos, replacement, partial)
    n = CommandLine.new(source_str, source_pos).set_token(pos, replacement, partial)
    assert_equal([expected_pos, expected_str], [n.position, n.command_line])
  end

  def test_set_token
    check_set_token("abc XXX YYYef ghi", 1, "abc def ghi", 1, 5, "XXX YYY", true)
    check_set_token("abc XXX YYY ghi", 1, "abc def ghi", 1, 5, "XXX YYY", false)

    check_set_token("abc XXX YYYef ghi", 11, "abc def ghi", 8, 5, "XXX YYY", true)
    check_set_token("abc XXX YYY ghi", 11, "abc def ghi", 8, 5, "XXX YYY", false)
  end
end
