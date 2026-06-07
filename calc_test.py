#!/usr/bin/python3
#
# calc_test.py - Unit test suite for calc.py.
# Tests expression parsing, formatting, fraction conversion, mixed fractions,
# and different numeric representation outputs.
#

import io
import sys
import unittest
from unittest.mock import patch
from fractions import Fraction
import calc


class TestHelperFunctions(unittest.TestCase):
    def test_grouped(self) -> None:
        self.assertEqual(calc.grouped("123456", 3), "123_456")
        self.assertEqual(calc.grouped("12345", 3), "12_345")
        self.assertEqual(calc.grouped("12", 3), "12")
        self.assertEqual(calc.grouped("abcdef", 4), "ab_cdef")

    def test_format_fraction(self) -> None:
        self.assertEqual(calc.format_fraction(Fraction(1, 3)), "1/3")
        self.assertEqual(calc.format_fraction(Fraction(5, 3)), "1 + 2/3 (5/3)")
        self.assertEqual(calc.format_fraction(Fraction(-5, 3)), "-(1 + 2/3) (-5/3)")
        self.assertEqual(calc.format_fraction(Fraction(2, 1)), "2")
        self.assertEqual(calc.format_fraction(Fraction(-2, 1)), "-2")
        self.assertEqual(calc.format_fraction(Fraction(0, 1)), "0")

    def test_preprocess_expression(self) -> None:
        self.assertEqual(calc.preprocess_expression("2x3"), "2*3")
        self.assertEqual(calc.preprocess_expression("2 x 3"), "2*3")
        self.assertEqual(calc.preprocess_expression("1x 3"), "1*3")
        self.assertEqual(calc.preprocess_expression("1 x3"), "1*3")
        self.assertEqual(calc.preprocess_expression("2x3x4"), "2*3*4")
        self.assertEqual(calc.preprocess_expression("2 x 3 x 4"), "2*3*4")
        self.assertEqual(calc.preprocess_expression("100,000 * 3"), "100000 * 3")
        self.assertEqual(calc.preprocess_expression("100_000 * 3"), "100000 * 3")
        self.assertEqual(calc.preprocess_expression("100_000,000 * 3"), "100000000 * 3")
        self.assertEqual(calc.preprocess_expression("1,000_000,000 * 3"), "1000000000 * 3")


class TestCalcExecution(unittest.TestCase):
    def run_calc(self, args: list[str], stdin_data: str = "") -> str:
        old_stdout = sys.stdout
        old_stdin = sys.stdin
        old_argv = sys.argv
        sys.stdout = io.StringIO()
        if stdin_data:
            sys.stdin = io.StringIO(stdin_data)
        try:
            calc.main(args)
            return sys.stdout.getvalue()
        finally:
            sys.stdout = old_stdout
            sys.stdin = old_stdin
            sys.argv = old_argv

    def test_simple_calculation(self) -> None:
        out = self.run_calc(["1 + 2"])
        self.assertIn("3", out)
        self.assertIn("0b11", out)
        self.assertIn("0x3", out)

    def test_help_flag(self) -> None:
        out = self.run_calc(["-h"])
        self.assertIn("Usage: calc.py", out)
        
        out_long = self.run_calc(["--help"])
        self.assertIn("Usage: calc.py", out_long)

    def test_float_fraction_approximation(self) -> None:
        out = self.run_calc(["0.25"])
        self.assertIn("# Fraction: 1/4", out)

        out = self.run_calc(["1.6666666666666667"])
        self.assertIn("# Fraction: 1 + 2/3 (5/3)", out)

        out = self.run_calc(["-1.6666666666666667"])
        self.assertIn("# Fraction: -(1 + 2/3) (-5/3)", out)

    def test_fraction_mode(self) -> None:
        out = self.run_calc(["-f", "1/3 + 1/6"])
        self.assertIn("1/2", out)
        self.assertIn("0.5", out)

        out = self.run_calc(["--fraction", "-5/3"])
        self.assertIn("-(1 + 2/3) (-5/3)", out)

    def test_explicit_fraction(self) -> None:
        out = self.run_calc(["F(1, 3) + F(1, 6)"])
        self.assertIn("1/2", out)

    def test_stdin_input(self) -> None:
        out = self.run_calc([], stdin_data="1+2\n0.25\n")
        self.assertIn("3", out)
        self.assertIn("# Fraction: 1/4", out)

    def test_x_multiplication(self) -> None:
        # Test x with space "2 x 3"
        out = self.run_calc(["2 x 3"])
        self.assertIn("6", out)

        # Test x without space "2x3"
        out_no_space = self.run_calc(["2x3"])
        self.assertIn("6", out_no_space)

        # Test "1x 3" and "1 x3"
        self.assertIn("3", self.run_calc(["1x 3"]))
        self.assertIn("3", self.run_calc(["1 x3"]))

        # Test multiple x's in a single expression
        self.assertIn("24", self.run_calc(["2x3x4"]))
        self.assertIn("24", self.run_calc(["2 x 3 x 4"]))
        self.assertIn("24", self.run_calc(["2x 3 x4"]))

        # Test x in fraction mode
        out_frac = self.run_calc(["-f", "1/3 x 3/2"])
        self.assertIn("1/2", out_frac)

        # Test float with x
        out_float = self.run_calc(["2.5x4"])
        self.assertIn("10.0", out_float)
        self.assertIn("10.0", self.run_calc(["2.5 x 4"]))
        self.assertIn("10.0", self.run_calc(["2.5 x4"]))
        self.assertIn("10.0", self.run_calc(["2.5x 4"]))

        # Test stdin with x multiplication
        out_stdin = self.run_calc([], stdin_data="2x3\n")
        self.assertIn("6", out_stdin)

    @patch('builtins.input')
    def test_interactive_repl(self, mock_input: unittest.mock.MagicMock) -> None:
        # Mock inputs: first "1+2", then "exit"
        mock_input.side_effect = ["1+2", "exit"]
        out = self.run_calc(["-i"])
        self.assertIn("calc.py Interactive REPL", out)
        self.assertIn("3", out)
        
        # Test interactive repl with fraction mode
        mock_input.side_effect = ["1/3 + 1/6", "exit"]
        out_frac = self.run_calc(["-i", "-f"])
        self.assertIn("1/2", out_frac)

    def test_digit_separators(self) -> None:
        # Test commas and underscores mixed in a single execution
        out = self.run_calc(["1,000_000 + 2_000,000"])
        self.assertIn("3000000", out)


if __name__ == '__main__':
    unittest.main()
