#!/usr/bin/python3
#
# calc.py - A command-line calculator that evaluates mathematical expressions
# and prints results in multiple formats (Decimal, Binary, Hexadecimal, 32-bit,
# 64-bit, and epoch timestamp representations).
# Supports fraction operations using Python's Fraction class or via the -f/--fraction flag.
#
# Note: Run the test suite via `calc.py -t` whenever making changes.
#

import ast
from decimal import Decimal
import fileinput
from fractions import Fraction
import math
import numpy as np
import re
import sys
import time
import typing

# Refer the following packages to prevent from getting removed
np
math

# Custom print wrapper to highlight the first non-comment line in bold-yellow
_original_print = print
_primary_printed = True

def print(*args, **kwargs):
    global _primary_printed
    if _primary_printed or kwargs.get('file', sys.stdout) is not sys.stdout:
        _original_print(*args, **kwargs)
        return

    sep = kwargs.get('sep', ' ')
    end = kwargs.get('end', '\n')
    content = sep.join(str(arg) for arg in args)

    if content.startswith('#') or not content.strip():
        _original_print(*args, **kwargs)
    else:
        if sys.stdout.isatty():
            _original_print(f"\033[1;33m{content}\033[0m", end=end, sep=sep, file=kwargs.get('file', sys.stdout))
        else:
            _original_print(*args, **kwargs)
        _primary_printed = True


class BigDecimal(Decimal):
    pass

for op in ['__add__', '__sub__', '__mul__', '__truediv__', '__floordiv__', '__mod__', '__pow__',
           '__radd__', '__rsub__', '__rmul__', '__rtruediv__', '__rfloordiv__', '__rmod__', '__rpow__',
           '__lt__', '__le__', '__gt__', '__ge__', '__eq__', '__ne__']:
    def make_wrapper(name=op):
        orig = getattr(Decimal, name)
        def wrapper(self, other):
            if isinstance(other, float):
                other = Decimal(str(other))
            elif isinstance(other, Fraction):
                other = Decimal(other.numerator) / Decimal(other.denominator)
            res = orig(self, other)
            if isinstance(res, Decimal) and not isinstance(res, BigDecimal):
                return BigDecimal(res)
            return res
        return wrapper
    setattr(BigDecimal, op, make_wrapper())


def _frac(a, b) -> Fraction:
    if not isinstance(a, Fraction):
        if isinstance(a, float):
            a = Fraction(str(a))
        else:
            a = Fraction(a)
    if not isinstance(b, Fraction):
        if isinstance(b, float):
            b = Fraction(str(b))
        else:
            b = Fraction(b)
    return a / b


def _div(a, b):
    if hasattr(a, '__array__') or hasattr(b, '__array__'):
        return a / b
    try:
        da = BigDecimal(str(a)) if isinstance(a, (int, float, Decimal)) else a
        db = BigDecimal(str(b)) if isinstance(b, (int, float, Decimal)) else b
        return da / db
    except Exception:
        return a / b


class DecimalTransformer(ast.NodeTransformer):
    """AST transformer that converts float numeric literals into BigDecimal calls
    and converts true division (/) into a custom division function."""
    def visit_Constant(self, node: ast.Constant) -> ast.AST:
        if isinstance(node.value, float):
            return ast.Call(
                func=ast.Name(id='BigDecimal', ctx=ast.Load()),
                args=[ast.Constant(value=str(node.value))],
                keywords=[]
            )
        return node

    def visit_BinOp(self, node: ast.BinOp) -> ast.AST:
        self.generic_visit(node)
        if isinstance(node.op, ast.Div):
            return ast.Call(
                func=ast.Name(id='_div', ctx=ast.Load()),
                args=[node.left, node.right],
                keywords=[]
            )
        if isinstance(node.op, ast.MatMult):
            return ast.Call(
                func=ast.Name(id='_frac', ctx=ast.Load()),
                args=[node.left, node.right],
                keywords=[]
            )
        return node


def print_help() -> None:
    """Prints the help message for calc.py."""
    print("""Usage: calc.py [options] [expression ...]

Evaluate a mathematical expression and display the result in multiple formats:
- Decimal (with digit grouping)
- Binary (prefixed with 0b, grouped by 4 bits)
- Hexadecimal (prefixed with 0x, grouped by 4 digits)
- 32-bit signed and unsigned representations
- 64-bit signed and unsigned representations
- GMT/Local times if the value is a valid epoch timestamp (in milliseconds)

Options:
  -h, --help         Show this help message and exit.
  -f, --fraction     Evaluate the expression using Fractions (default).
  -n, --no-fraction  Evaluate the expression using decimals (disables Fraction mode).
  -i, --interactive  Run in interactive REPL mode.
  -t, --test         Run the test suite (calc_test.py) and exit.

Examples:
  calc.py 1 + 2
  calc.py "2 x 3"                             # 'x' is treated as '*'
  calc.py 2x3
  calc.py "2 ^ 3"                             # '^' is power, same as **
  calc.py "100_000 * 3"                       # Commas and underscores are ignored
  calc.py "1/3 + 1/6"                         # Fraction evaluation (default)
  calc.py "1 @ 3 + 1 @ 6"                     # '@' is dedicated fraction division
  calc.py -n "0.1 + 0.2"                      # Evaluate as float/decimal
  calc.py "Fraction(1, 3) + Fraction(1, 6)"
  calc.py 0.25
""")


class FractionTransformer(ast.NodeTransformer):
    """AST transformer that converts numeric literals (integers and floats)
    into Fraction calls so that expressions evaluate with exact fractions."""
    def visit_Constant(self, node: ast.Constant) -> ast.AST:
        if isinstance(node.value, (int, float)):
            return ast.Call(
                func=ast.Name(id='Fraction', ctx=ast.Load()),
                args=[ast.Constant(value=str(node.value))],
                keywords=[]
            )
        return node

    def visit_BinOp(self, node: ast.BinOp) -> ast.AST:
        self.generic_visit(node)
        if isinstance(node.op, ast.MatMult):
            return ast.Call(
                func=ast.Name(id='_frac', ctx=ast.Load()),
                args=[node.left, node.right],
                keywords=[]
            )
        return node


def preprocess_expression(exp: str) -> str:
    """Preprocesses the math expression string to support custom notations:
    - Replaces 'x' representing multiplication (e.g. '2x3', '2 x 3', '1x 3', '2x3x4') with '*'
    - Strips commas and underscores between digits (e.g. '100,000' -> '100000', '100_000' -> '100000')
    - Replaces '^' with '**' to treat it as the power operator (e.g. '2^3' -> '2**3')
    - Ignores leading zeros in numbers to prevent python syntax errors (e.g. '07' -> '7')
    """
    exp = re.sub(r'\bx\b|(?<!\b0)(?<=\d)\s*x\s*(?=\d)', '*', exp)
    exp = re.sub(r'(?<=\d)[,_](?=\d)', '', exp)
    exp = exp.replace('^', '**')
    exp = re.sub(r'(?<!\.)\b0+([0-9]+)', r'\1', exp)
    return exp


def grouped(val: str, units: int) -> str:
    v = val
    v = v[::-1]
    v = re.sub(r'([0-9a-zA-Z]{' + str(units) + '})(?=[0-9a-zA-Z])', r'\1_', v)
    v = v[::-1]
    return v


def print_with_grouped(val: str, units: int, prefix: str = '') -> None:
    if val[0] == '-':
        val = val[1:]
        prefix = '-' + prefix

    print(prefix + val)
    g = grouped(val, units)
    if val != g:
        print(prefix + g)


def format_fraction(fr: Fraction) -> str:
    """Formats a Fraction into mixed fraction notation if its absolute value is > 1."""
    if abs(fr) > 1:
        whole = abs(fr.numerator) // fr.denominator
        rem_num = abs(fr.numerator) % fr.denominator
        if rem_num > 0:
            if fr.numerator < 0:
                return f'-({whole} + {rem_num}/{fr.denominator}) ({fr})'
            else:
                return f'{whole} + {rem_num}/{fr.denominator} ({fr})'
    return str(fr)


def show_result(result: typing.Any) -> None:
    global _primary_printed
    _primary_printed = False

    if isinstance(result, Fraction):
        print(format_fraction(result))
        if result.denominator == 1:
            result = int(result)
        else:
            result = float(result)
    elif isinstance(result, Decimal):
        try:
            fr = Fraction(result).limit_denominator()
            if fr.denominator > 1 and fr.denominator < 1000000:
                print(f'# Fraction: {format_fraction(fr)}')
        except (ValueError, OverflowError):
            pass
    elif isinstance(result, float):
        try:
            fr = Fraction(result).limit_denominator()
            if fr.denominator > 1 and fr.denominator < 1000000:
                print(f'# Fraction: {format_fraction(fr)}')
        except (ValueError, OverflowError):
            pass

    if isinstance(result, bool) or not isinstance(result, (int, float, Decimal)):
        print(result)
        _primary_printed = True
        return

    print_with_grouped(f'{result}', 3)
    value = int(result)
    print_with_grouped(f'{value:b}', 4, '0b')
    print_with_grouped(f'{value:x}', 4, '0x')

    print()
    print('# 32 bits')
    value = 0xffffffff & int(result)
    if value > 0x8000000:
        value -= 0x100000000

    print_with_grouped(f'{value}', 3)
    value = 0xffffffff & int(result)
    print_with_grouped(f'{value:b}', 4, '0b')
    print_with_grouped(f'{value:x}', 4, '0x')

    print()
    print('# 64 bits')
    value = 0xffffffffffffffff & int(result)
    if value > 0x800000000000000:
        value -= 0x10000000000000000
    print_with_grouped(f'{value}', 3)

    value = 0xffffffffffffffff & int(result)
    print_with_grouped(f'{value:b}', 4, '0b')
    print_with_grouped(f'{value:x}', 4, '0x')

    if result >= 0 and result <= 0xffffffffffffffff:
        print()
        print('# GMT time, as millis since epoch')

        def print_time(time_val: float, conv: typing.Callable[[int], time.struct_time]) -> None:
            t = conv(int(time_val / 1000))
            millis = int(time_val % 1000)
            print(f'{t.tm_year:04}-{t.tm_mon:02}-{t.tm_mday:02} ' +
                  f'{t.tm_hour:02}:{t.tm_min:02}:{t.tm_sec:02}.{millis:03}')

        print_time(float(result), time.gmtime)

        print()
        print('# Local time, as millis since epoch')
        print_time(float(result), time.localtime)
    _primary_printed = True


def run_repl(use_fraction: bool, globals_dict: dict[str, typing.Any]) -> None:
    """Runs an interactive REPL loop."""
    print("calc.py Interactive REPL")
    lines = [
        "Hint: Use '^' for power (e.g. 2^3) and '@' for fraction (e.g. 1@2)",
        "Type your expression and press Enter. Type 'exit' or 'quit' to exit."
    ]
    for line in lines:
        if sys.stdout.isatty():
            print(f"\033[36m{line}\033[0m")
        else:
            print(line)
    
    try:
        import readline
    except ImportError:
        pass

    while True:
        try:
            prompt = "\033[1;32mcalc> \033[0m" if sys.stdout.isatty() else "calc> "
            line = input(prompt)
        except (EOFError, KeyboardInterrupt):
            print()
            break

        line_str = line.strip()
        if not line_str:
            continue

        if line_str.lower() in ("exit", "quit", "exit()", "quit()"):
            break

        if line_str.lower() in ("?", "h", "help", "/help"):
            print_help()
            continue

        try:
            line_str = preprocess_expression(line_str)
            if use_fraction:
                tree = ast.parse(line_str, mode="eval")
                transformer = FractionTransformer()
                new_tree = transformer.visit(tree)
                ast.fix_missing_locations(new_tree)
                code = compile(new_tree, "<string>", "eval")
                result = eval(code, globals_dict)
            else:
                tree = ast.parse(line_str, mode="eval")
                transformer = DecimalTransformer()
                new_tree = transformer.visit(tree)
                ast.fix_missing_locations(new_tree)
                code = compile(new_tree, "<string>", "eval")
                result = eval(code, globals_dict)

            show_result(result)
        except Exception as e:
            print(f"Error: {e}")


def main(args: list[str]) -> None:
    # Check for help flags
    if '-h' in args or '--help' in args:
        print_help()
        return

    # Check for test flags
    if '-t' in args or '--test' in args:
        import os
        import unittest
        script_dir = os.path.dirname(os.path.abspath(__file__))
        if script_dir not in sys.path:
            sys.path.insert(0, script_dir)
        import calc_test
        suite = unittest.defaultTestLoader.loadTestsFromModule(calc_test)
        runner = unittest.TextTestRunner()
        result = runner.run(suite)
        sys.exit(0 if result.wasSuccessful() else 1)

    # Check for interactive flags
    use_interactive = False
    if '-i' in args:
        use_interactive = True
        args = [arg for arg in args if arg != '-i']
    if '--interactive' in args:
        use_interactive = True
        args = [arg for arg in args if arg != '--interactive']

    # Check for fraction flag
    use_fraction = True
    if '-f' in args:
        args = [arg for arg in args if arg != '-f']
    if '--fraction' in args:
        args = [arg for arg in args if arg != '--fraction']
    if '-n' in args:
        use_fraction = False
        args = [arg for arg in args if arg != '-n']
    if '--no-fraction' in args:
        use_fraction = False
        args = [arg for arg in args if arg != '--no-fraction']

    if not args and sys.stdin.isatty():
        use_interactive = True

    # Update sys.argv so that fileinput doesn't get confused
    sys.argv = [sys.argv[0]] + args

    globals_dict = {
        'Fraction': Fraction,
        'F': Fraction,
        'Decimal': BigDecimal,
        'D': BigDecimal,
        'BigDecimal': BigDecimal,
        '_div': _div,
        '_frac': _frac,
        'math': math,
        'np': np,
        'time': time,
    }

    if use_interactive:
        run_repl(use_fraction, globals_dict)
        return

    if args:
        exp = ' '.join(args)
        exp = preprocess_expression(exp)

        if use_fraction:
            tree = ast.parse(exp, mode='eval')
            transformer = FractionTransformer()
            new_tree = transformer.visit(tree)
            ast.fix_missing_locations(new_tree)
            code = compile(new_tree, '<string>', 'eval')
            result = eval(code, globals_dict)
        else:
            tree = ast.parse(exp, mode='eval')
            transformer = DecimalTransformer()
            new_tree = transformer.visit(tree)
            ast.fix_missing_locations(new_tree)
            code = compile(new_tree, '<string>', 'eval')
            result = eval(code, globals_dict)

        show_result(result)
    else:
        # Non-interactive mode (e.g. piped input like `echo "1+2" | calc.py` when no arguments are specified).
        for line in fileinput.input():
            line_str = line.strip()
            if not line_str:
                continue
            
            line_str = preprocess_expression(line_str)
            
            if use_fraction:
                tree = ast.parse(line_str, mode='eval')
                transformer = FractionTransformer()
                new_tree = transformer.visit(tree)
                ast.fix_missing_locations(new_tree)
                code = compile(new_tree, '<string>', 'eval')
                result = eval(code, globals_dict)
            else:
                tree = ast.parse(line_str, mode='eval')
                transformer = DecimalTransformer()
                new_tree = transformer.visit(tree)
                ast.fix_missing_locations(new_tree)
                code = compile(new_tree, '<string>', 'eval')
                result = eval(code, globals_dict)
            
            show_result(result)


if __name__ == '__main__':
    main(sys.argv[1:])
