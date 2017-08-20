#!/usr/bin/env ruby2.3

require "test/unit"

$DEBUG = true

class InvalidCommandLineError < StandardError
end


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

class CommandLine
  def initialize(command_line, pos = -1)
    @command_line = command_line
    pos = command_line.length if pos < 0
    @tokens = [] # [] of [start, end, STRING, is_whitespace]
    tokenize
  end

  attr_reader :tokens

  private
  def tokenize()
    raw_tokens = @command_line.scan(
        %r{
          (?: \s+ | # Whitespace
              ' [^']* '? | # Single quoted
              \" (?: [^\"] | \\.) * \"? | # Double quoted
              (?: [^\'\"\s] | \\.) + | # Bare characters
          )
        }x)

    puts raw_tokens.inspect if $DEBUG

    pos = 0
    current = ""
    current_start = 0
    current_len = 0
    in_token = false

    push_token = lambda {
      if in_token
        @tokens.push [current_start, current_len, current, false]
        current_start = pos
        current_len = 0
        current = ""
        in_token = false
      end
    }

    raw_tokens.each{|t|
      len = t.length
      break if len == 0
      if t =~ /^\s/ # Whitespace?
        push_token.call
        @tokens.push [pos, len, t, true]

        current_start = pos + len
      else # Token?
        in_token = true
        current += t
        current_len += len
      end
      pos += len
    }
    push_token.call
  end
end

class TestCommandLine < Test::Unit::TestCase
  def test_simple
    assert_equal([], CommandLine.new("").tokens)
    assert_equal(
        [
            [0, 3, 'abc', false],
        ], CommandLine.new("abc").tokens)
  end
end
