/bin/true; exec ruby -wSx "$0"
#!ruby

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
    assert_equal("a ", unshescape(%q(\a\ )))
    assert_equal(%q(a b  '' xx\" '), unshescape(%q(a\ b\  "''" 'xx\"' \')))

    assert_equal(%q(a b b), unshescape(%q(a\ \b \b)))

    assert_equal(%q(abcdef), unshescape(%q($'abc'def)))
    assert_equal("\"\'\\a\b\e\e\f\n\r\t\v\\q\ca\cbX", unshescape(%q($'\"\'\\\a\b\e\E\f\n\r\t\v\q\ca\cbX')))
    assert_equal("\ca\\uz1~\u56fdX", unshescape(%q($'\u1\uz1\u7e\u56fdX')))
    assert_equal("\ca\\Uz1~\u56fd\u{1F466}X", unshescape(%q($'\U1\Uz1\U7e\U56fd\U1F466X')))
    assert_equal("\caa\\xz1b~X", unshescape(%q($'\x01a\xz1b\x7eX')))
    assert_equal("\x01X", unshescape(%q($'\1X')))
    assert_equal("\x01@0X", unshescape(%q($'\1\1000X')))
  end
end

class TestShesplit < Test::Unit::TestCase
  def test_simple
    assert_equal([], shsplit(""))
    assert_equal(%w(a), shsplit("a"))
    assert_equal(%w(ab), shsplit("ab"))
    assert_equal(%w(a bc def), shsplit("a bc   def"))
    assert_equal([%(a), %(bc'a "')], shsplit(%(a bc'a "')))
    assert_equal([%("x '  5")], shsplit(%("x '  5")))
    assert_equal([%("x  '  \\"  5")], shsplit(%("x  '  \\"  5")))
    assert_equal([%(a), %(bc'a "'), %("\\'\\"x '  5")], shsplit(%(a bc'a "'   "\\'\\"x '  5")))
    assert_equal([%($'\\'\\"\\t\\v\\r\\n\ca')], shsplit(%(  $'\\'\\"\\t\\v\\r\\n\ca')))
    assert_equal(%w(; ; &&| ab ;), shsplit(%(;;&&|ab;)))
  end
end

class TestCommandLine < Test::Unit::TestCase
  def test_tokenize
    assert_equal([], CommandLine.new("").tokens)
    assert_equal(%w(a), CommandLine.new("a").tokens)
    assert_equal(
        ['abc', '  ', "\'\"\'ab\"dd\""],
        CommandLine.new("abc  \'\"\'ab\"dd\"").tokens)
    assert_equal(
        [';', ';', '&&|', 'ab', ';', '#', ' ', 'ab#def', '  ', '#a b cde"\'d '],
        CommandLine.new(%(;;&&|ab;# ab#def  #a b cde"'d )).tokens)
    assert_equal(
        %w(! command!),
        CommandLine.new(%(!command!)).tokens)
    assert_equal(
        ['  ', '!', 'command'],
        CommandLine.new(%(  !command)).tokens)
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

    assert_equal([4, 4, ""], CommandLine.new("abc def").get_token(4, true))
    assert_equal([4, 4, ""], CommandLine.new("abc def").get_token(4, false))

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
