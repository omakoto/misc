#!/usr/bin/env ruby2.3

require_relative "./shellhelper"

require "test/unit"

class TestShescape < Test::Unit::TestCase
  def test_simple
    assert_equal("", shescape(""))
    assert_equal("a", shescape("a"))
    assert_equal("'a b c'", shescape("a b c"))
    assert_equal("'a '\\'' '\\'''", shescape("a ' '"))
  end
end

class TestUnshescape < Test::Unit::TestCase
  def test_simple
    assert_equal("", unshescape(""))
    assert_equal("a", unshescape("a"))
    assert_equal("a b c", unshescape("a b c"))
    assert_equal("a b '' xx\" '", unshescape("a\ b\ \"''\" 'xx\"' \\'"))
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
