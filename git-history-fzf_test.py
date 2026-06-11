#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Unit and integration tests for git-history-fzf.
# Run this test suite with: python3 -m unittest git-history-fzf_test.py

import sys
import os
import unittest
import subprocess
from io import BytesIO
from typing import List, Set, Optional, Any, Union, Dict, Generator
from unittest.mock import patch, MagicMock

import importlib.util
import importlib.machinery

# Dynamically import git-history-fzf (extensionless script)
script_path: str = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'git-history-fzf')
loader: importlib.machinery.SourceFileLoader = importlib.machinery.SourceFileLoader("git_history_fzf", script_path)
spec: Optional[importlib.machinery.ModuleSpec] = importlib.util.spec_from_file_location("git_history_fzf", script_path, loader=loader)
if spec is None or spec.loader is None:
    raise ImportError("Could not load git-history-fzf")
git_history_fzf: Any = importlib.util.module_from_spec(spec)
sys.modules["git_history_fzf"] = git_history_fzf
spec.loader.exec_module(git_history_fzf)

class GitHistoryFzfTest(unittest.TestCase):
    
    @patch('subprocess.run')
    def test_is_inside_work_tree(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0)
        self.assertTrue(git_history_fzf.is_inside_work_tree())
        
        mock_run.return_value = MagicMock(returncode=1)
        self.assertFalse(git_history_fzf.is_inside_work_tree())
        
    @patch('git_history_fzf.popen_command')
    @patch('subprocess.run')
    def test_is_dirty(self, mock_run: MagicMock, mock_popen: MagicMock) -> None:
        # Case 1: Unstaged changes (diff-files returns 1)
        mock_run.return_value = MagicMock(returncode=1)
        self.assertTrue(git_history_fzf.is_dirty())
        mock_run.assert_called_with(["git", "diff-files", "--quiet"])
        
        # Case 2: Staged changes (diff-files returns 0, diff-index returns 1)
        mock_run.side_effect = [MagicMock(returncode=0), MagicMock(returncode=1)]
        self.assertTrue(git_history_fzf.is_dirty())
        
        # Case 3: Untracked files
        mock_run.side_effect = [MagicMock(returncode=0), MagicMock(returncode=0)]
        mock_proc = MagicMock()
        mock_proc.stdout.readline.return_value = b"untracked.txt\n"
        mock_proc.poll.return_value = None
        mock_proc.wait.return_value = 0
        mock_popen.return_value = mock_proc
        self.assertTrue(git_history_fzf.is_dirty())
        
        # Case 4: Clean
        mock_run.side_effect = [MagicMock(returncode=0), MagicMock(returncode=0)]
        mock_proc = MagicMock()
        mock_proc.stdout.readline.return_value = b""
        mock_proc.poll.return_value = None
        mock_proc.wait.return_value = 0
        mock_popen.return_value = mock_proc
        self.assertFalse(git_history_fzf.is_dirty())
        
    @patch('subprocess.run')
    def test_get_merge_bases(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0, stdout=b"sha1\nsha2\n")
        self.assertEqual(git_history_fzf.get_merge_bases(), {b"sha1", b"sha2"})
        
        mock_run.side_effect = Exception("error")
        self.assertEqual(git_history_fzf.get_merge_bases(), set())

    @patch('os.path.exists')
    @patch('subprocess.run')
    def test_get_submodules(self, mock_run: MagicMock, mock_exists: MagicMock) -> None:
        git_history_fzf._get_submodules_abs.cache_clear()
        
        def run_side_effect(cmd, **kwargs):
            if cmd == ["git", "rev-parse", "--show-toplevel"]:
                return MagicMock(returncode=0, stdout="/toplevel\n")
            elif cmd == ["git", "config", "--file", "/toplevel/.gitmodules", "--get-regexp", "path"]:
                return MagicMock(returncode=0, stdout="submodule.sub1.path path/to/sub1\nsubmodule.sub2.path path/to/sub2\n")
            return MagicMock(returncode=1)
            
        mock_run.side_effect = run_side_effect
        
        def exists_side_effect(path):
            if path in (
                "/toplevel/.gitmodules",
                "/toplevel/path/to/sub1/.git",
                "/toplevel/path/to/sub2/.git"
            ):
                return True
            return False
        mock_exists.side_effect = exists_side_effect
        
        with patch('os.getcwd', return_value='/toplevel'):
            self.assertEqual(git_history_fzf.get_submodules(), ["path/to/sub1", "path/to/sub2"])
            
        git_history_fzf._get_submodules_abs.cache_clear()
        mock_run.side_effect = Exception("error")
        self.assertEqual(git_history_fzf.get_submodules(), [])

    @patch('subprocess.run')
    def test_get_parent_repo(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0, stdout="/path/to/parent\n")
        self.assertEqual(git_history_fzf.get_parent_repo(), "/path/to/parent")
        
        mock_run.return_value = MagicMock(returncode=0, stdout="\n")
        self.assertIsNone(git_history_fzf.get_parent_repo())
        
        mock_run.side_effect = Exception("error")
        self.assertIsNone(git_history_fzf.get_parent_repo())

    def test_format_line_too_few_parts(self) -> None:
        line: bytes = b"too\x00few\x00parts"
        res: bytes = git_history_fzf.format_line(line)
        self.assertEqual(res, b"too\x00few\x00parts\n")

    def test_format_line_normal(self) -> None:
        line: bytes = b"12345ab\x002026-06-08 02:17:54\x00user@example.com\x00\x00Initial commit"
        res: bytes = git_history_fzf.format_line(line)
        self.assertEqual(
            res, 
            b"12345ab \x1b[36m[2026-06-08 02:17:54]\x1b[m \x1b[35m<user@example.com>\x1b[m Initial commit\n"
        )

    def test_format_line_with_decorations(self) -> None:
        # HEAD -> master, origin/master, tag: v1.0
        line: bytes = b"12345ab\x002026-06-08\x00user@example.com\x00\x1b[33mHEAD -> \x1b[32mmaster\x1b[m, origin/master, tag: v1.0\x00Initial commit"
        res: bytes = git_history_fzf.format_line(line)
        self.assertEqual(
            res,
            b"12345ab \x1b[36m[2026-06-08]\x1b[m \x1b[35m<user@example.com>\x1b[m \x1b[32m[master, origin/master]\x1b[m Initial commit\n"
        )

    def test_format_line_with_merge_base(self) -> None:
        line: bytes = b"12345ab\x002026-06-08\x00user@example.com\x00\x00Initial commit"
        merge_bases: Set[bytes] = {b"12345ab"}
        res: bytes = git_history_fzf.format_line(line, merge_bases=merge_bases)
        self.assertEqual(
            res,
            b"12345ab \x1b[36m[2026-06-08]\x1b[m \x1b[35m<user@example.com>\x1b[m \x1b[32m[\x1b[33mupstream-base\x1b[32m]\x1b[m Initial commit\n"
        )

    def test_format_line_with_merge_base_and_branches(self) -> None:
        line: bytes = b"12345ab\x002026-06-08\x00user@example.com\x00master\x00Initial commit"
        merge_bases: Set[bytes] = {b"12345ab"}
        res: bytes = git_history_fzf.format_line(line, merge_bases=merge_bases)
        self.assertEqual(
            res,
            b"12345ab \x1b[36m[2026-06-08]\x1b[m \x1b[35m<user@example.com>\x1b[m \x1b[32m[master, \x1b[33mupstream-base\x1b[32m]\x1b[m Initial commit\n"
        )

    @patch('git_history_fzf.is_inside_work_tree')
    @patch('git_history_fzf.get_merge_bases')
    @patch('subprocess.Popen')
    def test_main_standard_flow(self, mock_popen: MagicMock, mock_get_merge_bases: MagicMock, mock_is_inside: MagicMock) -> None:
        mock_is_inside.return_value = True
        mock_get_merge_bases.return_value = {b"12345ab"}
        
        mock_fzf_proc = MagicMock()
        mock_fzf_proc.stdin = BytesIO()
        mock_fzf_proc.communicate.return_value = (b"12345ab commit message\n", None)
        mock_fzf_proc.wait.return_value = 0
        
        mock_git_proc = MagicMock()
        mock_git_proc.stdout = [
            b"12345ab\x002026-06-08\x00user@example.com\x00\x00Initial commit\n"
        ]
        mock_git_proc.wait.return_value = 0
        
        def popen_side_effect(cmd: List[str], **kwargs: Any) -> MagicMock:
            if cmd[0] == "fzf":
                return mock_fzf_proc
            elif cmd[0] == "git":
                return mock_git_proc
            raise ValueError(f"Unexpected Popen call: {cmd}")
            
        mock_popen.side_effect = popen_side_effect
        
        with patch('sys.argv', ['git-history-fzf']), \
             patch('sys.stdout') as mock_stdout:
            
            with self.assertRaises(SystemExit) as cm:
                git_history_fzf.main()
            
            self.assertEqual(cm.exception.code, 0)
            mock_stdout.buffer.write.assert_called_once_with(b"12345ab commit message\n")
            
            fzf_args = mock_popen.call_args_list[0][0][0]
            self.assertIn("--multi", fzf_args)
            self.assertNotIn("--single", fzf_args)

    @patch('git_history_fzf.is_inside_work_tree')
    @patch('git_history_fzf.get_merge_bases')
    @patch('subprocess.Popen')
    def test_main_single_mode(self, mock_popen: MagicMock, mock_get_merge_bases: MagicMock, mock_is_inside: MagicMock) -> None:
        mock_is_inside.return_value = True
        mock_get_merge_bases.return_value = set()
        
        mock_fzf_proc = MagicMock()
        mock_fzf_proc.stdin = BytesIO()
        mock_fzf_proc.communicate.return_value = (b"12345ab commit message\n", None)
        mock_fzf_proc.wait.return_value = 0
        
        mock_git_proc = MagicMock()
        mock_git_proc.stdout = []
        mock_git_proc.wait.return_value = 0
        
        def popen_side_effect(cmd: List[str], **kwargs: Any) -> MagicMock:
            if cmd[0] == "fzf":
                return mock_fzf_proc
            elif cmd[0] == "git":
                return mock_git_proc
            raise ValueError(f"Unexpected Popen call: {cmd}")
            
        mock_popen.side_effect = popen_side_effect
        
        with patch('sys.argv', ['git-history-fzf', '--single', '-h', 'Test Header', '-e', 'ctrl-s']), \
             patch('sys.stdout') as mock_stdout:
            
            with self.assertRaises(SystemExit) as cm:
                git_history_fzf.main()
                
            self.assertEqual(cm.exception.code, 0)
            fzf_args = mock_popen.call_args_list[0][0][0]
            self.assertNotIn("--multi", fzf_args)
            self.assertIn("--header=Test Header", fzf_args)
            self.assertIn("--expect=ctrl-s", fzf_args)

    @patch('git_history_fzf.is_inside_work_tree')
    @patch('git_history_fzf.get_merge_bases')
    @patch('git_history_fzf.is_dirty')
    @patch('subprocess.Popen')
    def test_main_current_dirty(self, mock_popen: MagicMock, mock_is_dirty: MagicMock, mock_get_merge_bases: MagicMock, mock_is_inside: MagicMock) -> None:
        mock_is_inside.return_value = True
        mock_get_merge_bases.return_value = set()
        mock_is_dirty.return_value = True
        
        mock_fzf_proc = MagicMock()
        mock_fzf_proc.stdin = MagicMock()
        mock_fzf_proc.communicate.return_value = (b"selection\n", None)
        mock_fzf_proc.wait.return_value = 0
        
        mock_git_proc = MagicMock()
        mock_git_proc.stdout = []
        mock_git_proc.wait.return_value = 0
        
        def popen_side_effect(cmd: List[str], **kwargs: Any) -> MagicMock:
            if cmd[0] == "fzf":
                return mock_fzf_proc
            elif cmd[0] == "git":
                return mock_git_proc
            raise ValueError(f"Unexpected Popen call: {cmd}")
            
        mock_popen.side_effect = popen_side_effect
        
        with patch('sys.argv', ['git-history-fzf', '-c']), \
             patch('sys.stdout') as mock_stdout:
            with self.assertRaises(SystemExit) as cm:
                git_history_fzf.main()
            self.assertEqual(cm.exception.code, 0)
            mock_fzf_proc.stdin.write.assert_any_call(b"\x1b[33m(CURRENT)\x1b[m Local changes\n")

    @patch('git_history_fzf.is_inside_work_tree')
    @patch('git_history_fzf.get_merge_bases')
    @patch('git_history_fzf.get_submodules')
    @patch('git_history_fzf.get_parent_repo')
    @patch('subprocess.Popen')
    def test_main_submodules(self, mock_popen: MagicMock, mock_get_parent: MagicMock, mock_get_subs: MagicMock, mock_get_merge_bases: MagicMock, mock_is_inside: MagicMock) -> None:
        mock_is_inside.return_value = True
        mock_get_merge_bases.return_value = set()
        mock_get_subs.return_value = ["sub1", "sub2"]
        mock_get_parent.return_value = "/path/to/parent"
        
        mock_fzf_proc = MagicMock()
        mock_fzf_proc.stdin = MagicMock()
        mock_fzf_proc.communicate.return_value = (b"(submodule) [Submodules]\n", None)
        mock_fzf_proc.wait.return_value = 0
        
        mock_fzf_sub_proc = MagicMock()
        mock_fzf_sub_proc.stdin = MagicMock()
        mock_fzf_sub_proc.communicate.return_value = (b"sub1\n", None)
        mock_fzf_sub_proc.wait.return_value = 0
        
        mock_git_proc = MagicMock()
        mock_git_proc.stdout = []
        mock_git_proc.wait.return_value = 0
        
        def popen_side_effect(cmd: List[str], **kwargs: Any) -> MagicMock:
            if cmd[0] == "fzf":
                if any("--header=Select a submodule" in arg for arg in cmd):
                    return mock_fzf_sub_proc
                return mock_fzf_proc
            elif cmd[0] == "git":
                return mock_git_proc
            raise ValueError(f"Unexpected Popen call: {cmd}")
            
        mock_popen.side_effect = popen_side_effect
        
        with patch('sys.argv', ['git-history-fzf', '--submodules']), \
             patch('sys.stdout') as mock_stdout:
            
            with self.assertRaises(SystemExit) as cm:
                git_history_fzf.main()
                
            self.assertEqual(cm.exception.code, 0)
            mock_fzf_proc.stdin.write.assert_any_call(b"\x1b[35m(submodule)\x1b[m [Submodules]\n")
            mock_fzf_proc.stdin.write.assert_any_call(b"\x1b[35m(submodule)\x1b[m (Parent)\n")
            mock_stdout.buffer.write.assert_called_once_with(b"(submodule) sub1\n")

    @patch('git_history_fzf.is_inside_work_tree')
    @patch('sys.stderr.write')
    def test_main_not_in_git_repo(self, mock_stderr_write: MagicMock, mock_is_inside: MagicMock) -> None:
        mock_is_inside.return_value = False
        with patch('sys.argv', ['git-history-fzf']):
            with self.assertRaises(SystemExit) as cm:
                git_history_fzf.main()
            self.assertEqual(cm.exception.code, 1)
            mock_stderr_write.assert_any_call("Error: Not a git repository\n")

if __name__ == "__main__":
    unittest.main()
