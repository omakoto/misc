#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Unit tests for git-upstream-label.
# Run this test suite with: python3 -m unittest git-upstream-label_test.py
#

import os
import sys
import unittest
from unittest.mock import patch, MagicMock
from io import StringIO
from contextlib import redirect_stdout, redirect_stderr

import importlib.util
import importlib.machinery

# Dynamically import git-upstream-label
script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'git-upstream-label')
loader = importlib.machinery.SourceFileLoader("git_upstream_label", script_path)
spec = importlib.util.spec_from_file_location("git_upstream_label", script_path, loader=loader)
if spec is None or spec.loader is None:
    raise ImportError("Could not load git-upstream-label")
git_upstream_label = importlib.util.module_from_spec(spec)
sys.modules["git_upstream_label"] = git_upstream_label
spec.loader.exec_module(git_upstream_label)

class GitUpstreamLabelTest(unittest.TestCase):

    @patch('git_upstream_label.run_git')
    def test_is_inside_work_tree(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0)
        self.assertTrue(git_upstream_label.is_inside_work_tree())
        
        mock_run.return_value = MagicMock(returncode=1)
        self.assertFalse(git_upstream_label.is_inside_work_tree())

    @patch('git_upstream_label.run_git')
    def test_get_upstream_label_multiple_refs(self, mock_run):
        # Format: hash\x00 HEAD -> master, origin/master, origin/HEAD
        mock_stdout = b"\x1b[33ma9c9c8da\x1b[m\x00 \x1b[33mHEAD -> \x1b[32mmaster\x1b[m, origin/master, origin/HEAD"
        mock_run.return_value = MagicMock(returncode=0, stdout=mock_stdout)
        
        label = git_upstream_label.get_upstream_label()
        self.assertEqual(
            label,
            "a9c9c8da [master, origin/master, origin/HEAD]"
        )

    @patch('git_upstream_label.run_git')
    def test_get_upstream_label_single_ref(self, mock_run):
        mock_stdout = b"\x1b[33ma9c9c8da\x1b[m\x00 origin/master"
        mock_run.return_value = MagicMock(returncode=0, stdout=mock_stdout)
        
        label = git_upstream_label.get_upstream_label()
        self.assertEqual(
            label,
            "a9c9c8da [origin/master]"
        )

    @patch('git_upstream_label.run_git')
    def test_get_upstream_label_no_decorations(self, mock_run):
        mock_stdout = b"\x1b[33ma9c9c8da\x1b[m\x00 "
        mock_run.return_value = MagicMock(returncode=0, stdout=mock_stdout)
        
        label = git_upstream_label.get_upstream_label()
        self.assertEqual(
            label,
            "a9c9c8da"
        )

    @patch('git_upstream_label.run_git')
    def test_get_upstream_label_git_error(self, mock_run):
        mock_run.return_value = MagicMock(returncode=128, stdout=b"")
        
        label = git_upstream_label.get_upstream_label()
        self.assertEqual(label, "")

    @patch('git_upstream_label.is_inside_work_tree')
    @patch('git_upstream_label.get_upstream_label')
    def test_main_success(self, mock_get_label, mock_is_inside):
        mock_is_inside.return_value = True
        mock_get_label.return_value = "mocked_label"
        
        out = StringIO()
        with patch('sys.argv', ['git-upstream-label']), redirect_stdout(out):
            git_upstream_label.main()
            
        self.assertEqual(out.getvalue(), "mocked_label\n")

    @patch('git_upstream_label.is_inside_work_tree')
    def test_main_not_in_git(self, mock_is_inside):
        mock_is_inside.return_value = False
        
        err = StringIO()
        with patch('sys.argv', ['git-upstream-label']), \
             redirect_stderr(err), \
             self.assertRaises(SystemExit) as cm:
            git_upstream_label.main()
            
        self.assertEqual(cm.exception.code, 1)
        self.assertEqual(err.getvalue(), "Error: Not a git repository\n")

    @patch('git_upstream_label.is_inside_work_tree')
    @patch('git_upstream_label.get_upstream_label')
    def test_main_no_upstream(self, mock_get_label, mock_is_inside):
        mock_is_inside.return_value = True
        mock_get_label.return_value = ""
        
        with patch('sys.argv', ['git-upstream-label']), \
             self.assertRaises(SystemExit) as cm:
            git_upstream_label.main()
            
        self.assertEqual(cm.exception.code, 1)

    @patch('git_upstream_label.is_inside_work_tree')
    @patch('git_upstream_label.get_upstream_label')
    @patch('os.path.isdir')
    @patch('os.path.abspath')
    def test_main_with_dir(self, mock_abspath, mock_isdir, mock_get_label, mock_is_inside):
        mock_isdir.return_value = True
        mock_abspath.return_value = "/mock/dir"
        mock_is_inside.return_value = True
        mock_get_label.return_value = "label"
        
        out = StringIO()
        with patch('sys.argv', ['git-upstream-label', 'some_dir']), redirect_stdout(out):
            git_upstream_label.main()
            
        mock_abspath.assert_called_with("some_dir")
        mock_is_inside.assert_called_with("/mock/dir")
        mock_get_label.assert_called_with("/mock/dir")
        self.assertEqual(out.getvalue(), "label\n")

    @patch('os.path.isdir')
    def test_main_with_invalid_dir(self, mock_isdir):
        mock_isdir.return_value = False
        
        err = StringIO()
        with patch('sys.argv', ['git-upstream-label', 'invalid_dir']), \
             redirect_stderr(err), \
             self.assertRaises(SystemExit) as cm:
            git_upstream_label.main()
            
        self.assertEqual(cm.exception.code, 1)
        self.assertEqual(err.getvalue(), "Error: Directory not found: invalid_dir\n")

if __name__ == '__main__':
    unittest.main()
