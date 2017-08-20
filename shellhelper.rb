#!/usr/bin/env ruby2.3

require "test/unit"

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
