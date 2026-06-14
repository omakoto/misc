#!/usr/bin/env python3
#
# list-files_test.py - Unit test suite for list-files.
#
# Run this test via `python3 misc/list-files_test.py`.
#

import io
import os
import sys
import tempfile
import unittest
from typing import Tuple, Optional

# Dynamically import list-files (extensionless script)
import importlib.machinery
import importlib.util

script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'list-files')
loader = importlib.machinery.SourceFileLoader("list_files", script_path)
spec = importlib.util.spec_from_file_location("list_files", script_path, loader=loader)
list_files = importlib.util.module_from_spec(spec)
sys.modules["list_files"] = list_files
spec.loader.exec_module(list_files)


class TestListFiles(unittest.TestCase):
    def setUp(self) -> None:
        # Create a temporary directory to perform testing
        self.temp_dir = tempfile.TemporaryDirectory()
        self.dir_path = self.temp_dir.name

        # Create a directory structure:
        # self.dir_path/
        # ├── a/
        # │   └── x.txt
        # ├── b/
        # │   └── y.txt
        # ├── c.txt
        # └── d/
        #     └── e/
        #         └── z.txt
        os.makedirs(os.path.join(self.dir_path, "a"))
        os.makedirs(os.path.join(self.dir_path, "b"))
        os.makedirs(os.path.join(self.dir_path, "d", "e"))

        with open(os.path.join(self.dir_path, "a", "x.txt"), "w") as f:
            f.write("a/x")
        with open(os.path.join(self.dir_path, "b", "y.txt"), "w") as f:
            f.write("b/y")
        with open(os.path.join(self.dir_path, "c.txt"), "w") as f:
            f.write("c")
        with open(os.path.join(self.dir_path, "d", "e", "z.txt"), "w") as f:
            f.write("d/e/z")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_traverse(self, start_dir: str, reverse: bool, max_files: Optional[int] = None) -> Tuple[bool, str, str]:
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        sys.stdout = io.StringIO()
        sys.stderr = io.StringIO()
        try:
            state = list_files.TraversalState(max_files) if max_files is not None else None
            success = list_files.traverse_dir(start_dir, reverse, state)
            return success, sys.stdout.getvalue(), sys.stderr.getvalue()
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def test_alphabetical_depth_first(self) -> None:
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=False)
        self.assertTrue(success)
        self.assertEqual(stderr, "")

        # Get lines, relative to the temp dir path
        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = [
            "a/x.txt",
            "b/y.txt",
            "c.txt",
            "d/e/z.txt"
        ]
        self.assertEqual(lines, expected)

    def test_reverse_alphabetical_depth_first(self) -> None:
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=True)
        self.assertTrue(success)
        self.assertEqual(stderr, "")

        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = [
            "d/e/z.txt",
            "c.txt",
            "b/y.txt",
            "a/x.txt"
        ]
        self.assertEqual(lines, expected)

    def test_empty_directory(self) -> None:
        with tempfile.TemporaryDirectory() as empty_dir:
            success, stdout, stderr = self.run_traverse(empty_dir, reverse=False)
            self.assertTrue(success)
            self.assertEqual(stdout, "")
            self.assertEqual(stderr, "")

    def test_non_existent_directory(self) -> None:
        non_existent = os.path.join(self.dir_path, "does_not_exist")
        success, stdout, stderr = self.run_traverse(non_existent, reverse=False)
        self.assertFalse(success)
        self.assertEqual(stdout, "")
        self.assertIn("is not a directory", stderr)

    def test_max_files_limit(self) -> None:
        # Test limit of 3 files in alphabetical order
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=False, max_files=3)
        self.assertTrue(success)
        self.assertEqual(stderr, "")
        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = ["a/x.txt", "b/y.txt", "c.txt"]
        self.assertEqual(lines, expected)

        # Test limit of 2 files in reverse alphabetical order
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=True, max_files=2)
        self.assertTrue(success)
        self.assertEqual(stderr, "")
        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = ["d/e/z.txt", "c.txt"]
        self.assertEqual(lines, expected)

    def test_max_files_zero(self) -> None:
        # Test limit of 0 files/dirs
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=False, max_files=0)
        self.assertTrue(success)
        self.assertEqual(stderr, "")
        self.assertEqual(stdout.strip(), "")

    def test_max_files_larger_than_total(self) -> None:
        # Test limit of 10 files (total is 4)
        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=False, max_files=10)
        self.assertTrue(success)
        self.assertEqual(stderr, "")
        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = [
            "a/x.txt",
            "b/y.txt",
            "c.txt",
            "d/e/z.txt"
        ]
        self.assertEqual(lines, expected)

    def test_symlinks(self) -> None:
        # Create a symbolic link to a file:
        os.symlink("c.txt", os.path.join(self.dir_path, "sym_file"))
        # Create a symbolic link to a directory:
        os.symlink("a", os.path.join(self.dir_path, "sym_dir"))
        # Create a broken symlink:
        os.symlink("non_existent.txt", os.path.join(self.dir_path, "sym_broken"))

        success, stdout, stderr = self.run_traverse(self.dir_path, reverse=False)
        self.assertTrue(success)
        self.assertEqual(stderr, "")

        lines = [os.path.relpath(line, self.dir_path) for line in stdout.strip().split("\n")]
        expected = [
            "a/x.txt",
            "b/y.txt",
            "c.txt",
            "d/e/z.txt",
            "sym_file"
        ]
        self.assertEqual(lines, expected)


if __name__ == "__main__":
    unittest.main()
