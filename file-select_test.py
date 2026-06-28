#!/usr/bin/env python3
#
# file-select_test.py - Unit test suite for file-select's path filter and ANSI removal.
#
# Run this test via `python3 misc/file-select_test.py`.
#

import os
import sys
import unittest
from typing import List

# Dynamically import file-select (extensionless script)
import importlib.machinery
import importlib.util

script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'file-select')
loader = importlib.machinery.SourceFileLoader("file_select", script_path)
spec = importlib.util.spec_from_file_location("file_select", script_path, loader=loader)
file_select = importlib.util.module_from_spec(spec)
sys.modules["file_select"] = file_select
spec.loader.exec_module(file_select)

class TestFileSelect(unittest.TestCase):
    def test_filter_path(self) -> None:
        home: str = "/home/testuser"
        home_dir: str = "/home/testuser/"
        cwd: str = "/home/testuser/workspace/"

        # Test case 1: normal relative path starting with `./`
        res: List[str] = file_select.filter_path("./foo/bar.txt", home, home_dir, cwd)
        self.assertEqual(res, ["foo/bar.txt", "\033[36m~/workspace/foo/bar.txt\033[m"])

        # Test case 2: absolute path matching HOME
        res = file_select.filter_path("/home/testuser/workspace/baz.txt", home, home_dir, cwd)
        self.assertEqual(res, ["/home/testuser/workspace/baz.txt", "\033[36m~/workspace/baz.txt\033[m"])

        # Test case 3: path that is exactly HOME
        res = file_select.filter_path("/home/testuser", home, home_dir, cwd)
        self.assertEqual(res, ["/home/testuser", "\033[36m~\033[m"])

        # Test case 4: path `./` (should resolve to cwd only, rel is empty)
        res = file_select.filter_path("./", home, home_dir, cwd)
        self.assertEqual(res, ["\033[36m~/workspace\033[m"])

        # Test case 5: path `.`
        res = file_select.filter_path(".", home, home_dir, cwd)
        self.assertEqual(res, [".", "\033[36m~/workspace\033[m"])

if __name__ == "__main__":
    unittest.main()
