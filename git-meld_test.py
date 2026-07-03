#!/usr/bin/env python3
import sys
import os
import unittest
import subprocess
from unittest.mock import patch, MagicMock
import importlib.util
import importlib.machinery

# Save the original subprocess.run before any mock patches are applied
ORIGINAL_SUBPROCESS_RUN = subprocess.run

# Dynamically import git-meld (extensionless script)
script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'git-meld')
loader = importlib.machinery.SourceFileLoader("git_meld", script_path)
spec = importlib.util.spec_from_file_location("git_meld", script_path, loader=loader)
git_meld = importlib.util.module_from_spec(spec)
sys.modules["git_meld"] = git_meld
spec.loader.exec_module(git_meld)

class GitMeldTest(unittest.TestCase):
    def test_parse_arguments_empty(self):
        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments([])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertFalse(cached)
        self.assertFalse(no_rename)
        self.assertFalse(all_subs)
        self.assertFalse(help_req)

    def test_parse_arguments_cached(self):
        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments(["--cached"])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertTrue(cached)
        self.assertFalse(no_rename)
        self.assertFalse(all_subs)
        self.assertFalse(help_req)

    def test_parse_arguments_no_rename(self):
        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments(["--no-rename-detection"])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertFalse(cached)
        self.assertTrue(no_rename)
        self.assertFalse(all_subs)
        self.assertFalse(help_req)

    def test_parse_arguments_all_submodules(self):
        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments(["--all-submodules"])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertFalse(cached)
        self.assertFalse(no_rename)
        self.assertTrue(all_subs)
        self.assertFalse(help_req)

    def test_parse_arguments_help(self):
        _, _, _, _, _, help_req = git_meld.parse_arguments(["-h"])
        self.assertTrue(help_req)
        _, _, _, _, _, help_req = git_meld.parse_arguments(["--help"])
        self.assertTrue(help_req)

    @patch('git_meld.parse_rev_or_range')
    def test_parse_arguments_revs_and_paths(self, mock_parse_rev):
        # Mock git revision check to return True for commit names
        mock_parse_rev.side_effect = lambda x: x in {"HEAD", "HEAD~1", "master", "feature", "master..feature"}

        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments(["HEAD~1", "--", "file1.txt"])
        self.assertEqual(revs, ["HEAD~1"])
        self.assertEqual(paths, ["file1.txt"])

        # Test range
        revs, paths, cached, no_rename, all_subs, help_req = git_meld.parse_arguments(["master..feature", "dir/"])
        self.assertEqual(revs, ["master..feature"])
        self.assertEqual(paths, ["dir/"])

    def test_sanitize_dir_name(self):
        self.assertEqual(git_meld.sanitize_dir_name("HEAD"), "HEAD")
        self.assertEqual(git_meld.sanitize_dir_name("HEAD~1"), "HEAD~1")
        self.assertEqual(git_meld.sanitize_dir_name("master/feature"), "master_feature")
        self.assertEqual(git_meld.sanitize_dir_name("a:b\\c?d*e"), "a_b_c_d_e")

    @patch('subprocess.run')
    def test_query_diff_status(self, mock_run):
        # We simulate git diff output with renames, modifications, deletions, and submodules.
        # Format of git diff -z --raw is:
        # :src_mode dst_mode src_sha dst_sha status \0 PATH1 \0 (PATH2 \0 if rename/copy)
        mock_stdout = (
            b":100644 100644 1111111 2222222 M\0file1.txt\0"
            b":100644 100644 3333333 4444444 R100\0old_file.txt\0new_file.txt\0"
            b":100644 000000 5555555 0000000 D\0deleted_file.txt\0"
            b":000000 100644 0000000 6666666 A\0added_file.txt\0"
            b":160000 160000 7777777 8888888 M\0submodule_dir\0"
            b":160000 160000 9999999 aaaaaaa R100\0old_submodule\0new_submodule\0"
        )
        mock_run.return_value = MagicMock(stdout=mock_stdout)
        
        src, dest, renames = git_meld.query_diff_status(["HEAD"])
        
        # Verify --ignore-submodules is passed
        mock_run.assert_called_once()
        called_args = mock_run.call_args[0][0]
        self.assertIn("--ignore-submodules", called_args)
        
        self.assertEqual(src, ["file1.txt", "old_file.txt", "deleted_file.txt"])
        self.assertEqual(dest, ["file1.txt", "new_file.txt", "added_file.txt"])
        self.assertEqual(renames, {"new_file.txt": "old_file.txt"})

    @patch('os.fork')
    @patch('os.setsid')
    def test_main_integration(self, mock_setsid, mock_fork):
        mock_fork.return_value = 0 # Simulate child process
        
        import tempfile
        import shutil
        import subprocess
        
        test_dir = tempfile.mkdtemp()
        orig_cwd = os.getcwd()
        os.chdir(test_dir)
        
        try:
            # Initialize git repository
            subprocess.run(["git", "init", "-q"], check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], check=True)
            
            # Create a file and commit it
            with open("file1.txt", "w") as f:
                f.write("initial content")
            subprocess.run(["git", "add", "file1.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Initial commit"], check=True)
            
            # Modify the file in the workspace
            with open("file1.txt", "w") as f:
                f.write("modified content")
                
            # Create a new untracked file
            with open("untracked.txt", "w") as f:
                f.write("untracked content")
                
            # Setup arguments to test git-meld comparing HEAD to working directory
            with patch('sys.argv', ['git-meld', 'HEAD']):
                with patch('subprocess.run') as mock_run:
                    def side_effect(cmd, *args, **kwargs):
                        if cmd[0] == 'meld' or cmd[0] == '/usr/bin/meld':
                            # Diff tool execution intercepted!
                            source_dir = cmd[-2]
                            dest_dir = cmd[-1]
                            
                            # Verify file1.txt exists in both dirs
                            self.assertTrue(os.path.exists(os.path.join(source_dir, "file1.txt")))
                            self.assertTrue(os.path.exists(os.path.join(dest_dir, "file1.txt")))
                            
                            # Verify contents
                            with open(os.path.join(source_dir, "file1.txt")) as f:
                                self.assertEqual(f.read().strip(), "initial content")
                            with open(os.path.join(dest_dir, "file1.txt")) as f:
                                self.assertEqual(f.read().strip(), "modified content")
                                
                            return MagicMock(returncode=0)
                        else:
                            return ORIGINAL_SUBPROCESS_RUN(cmd, *args, **kwargs)
                            
                    mock_run.side_effect = side_effect
                    
                    git_meld.main()
                    
                    # Verify meld call was made
                    meld_called = False
                    for call in mock_run.call_args_list:
                        cmd_arg = call[0][0]
                        if cmd_arg[0] == 'meld' or cmd_arg[0] == '/usr/bin/meld':
                            meld_called = True
                    self.assertTrue(meld_called, "Diff tool 'meld' was not called")
                
        finally:
            os.chdir(orig_cwd)
            shutil.rmtree(test_dir, ignore_errors=True)

    @patch('os.fork')
    @patch('os.setsid')
    def test_main_all_submodules_integration(self, mock_setsid, mock_fork):
        mock_fork.return_value = 0 # Simulate child process

        import tempfile
        import shutil
        import subprocess

        test_dir = tempfile.mkdtemp(dir="/tmp")
        orig_cwd = os.getcwd()

        try:
            def init_repo(path):
                os.makedirs(path, exist_ok=True)
                subprocess.run(["git", "init", "-q"], cwd=path, check=True)
                subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=path, check=True)
                subprocess.run(["git", "config", "user.name", "Test User"], cwd=path, check=True)

            # Two submodule origins: one will be dirtied, one stays clean
            for name, filename in (("sub1_origin", "sub1file.txt"), ("sub2_origin", "sub2file.txt")):
                repo = os.path.join(test_dir, name)
                init_repo(repo)
                with open(os.path.join(repo, filename), "w") as f:
                    f.write("original content")
                subprocess.run(["git", "add", filename], cwd=repo, check=True)
                subprocess.run(["git", "commit", "-q", "-m", "Initial commit"], cwd=repo, check=True)

            # Parent repo with the two submodules
            parent = os.path.join(test_dir, "parent")
            init_repo(parent)
            with open(os.path.join(parent, "parentfile.txt"), "w") as f:
                f.write("parent content")
            subprocess.run(["git", "add", "parentfile.txt"], cwd=parent, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Initial commit"], cwd=parent, check=True)
            for name, sub in (("sub1_origin", "sub1"), ("sub2_origin", "sub2")):
                subprocess.run(
                    ["git", "-c", "protocol.file.allow=always", "submodule", "add", "-q",
                     os.path.join(test_dir, name), sub],
                    cwd=parent, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Add submodules"], cwd=parent, check=True)

            # Dirty sub1: modify a tracked file and add an untracked file
            with open(os.path.join(parent, "sub1", "sub1file.txt"), "w") as f:
                f.write("modified content")
            with open(os.path.join(parent, "sub1", "untracked.txt"), "w") as f:
                f.write("untracked content")

            # Also dirty the parent repository: modify tracked and add untracked
            with open(os.path.join(parent, "parentfile.txt"), "w") as f:
                f.write("modified parent content")
            with open(os.path.join(parent, "parent_untracked.txt"), "w") as f:
                f.write("untracked parent content")

            os.chdir(parent)

            with patch('sys.argv', ['git-meld', '--all-submodules']):
                with patch('subprocess.run') as mock_run:
                    def side_effect(cmd, *args, **kwargs):
                        if cmd[0] == 'meld' or cmd[0] == '/usr/bin/meld':
                            source_dir = cmd[-2]
                            dest_dir = cmd[-1]

                            # Changed file appears under the submodule path on both sides
                            with open(os.path.join(source_dir, "sub1", "sub1file.txt")) as f:
                                self.assertEqual(f.read().strip(), "original content")
                            with open(os.path.join(dest_dir, "sub1", "sub1file.txt")) as f:
                                self.assertEqual(f.read().strip(), "modified content")

                            # The destination side is a symlink to the real working file
                            self.assertTrue(os.path.islink(os.path.join(dest_dir, "sub1", "sub1file.txt")))

                            # Untracked file appears only on the destination side
                            self.assertFalse(os.path.exists(os.path.join(source_dir, "sub1", "untracked.txt")))
                            with open(os.path.join(dest_dir, "sub1", "untracked.txt")) as f:
                                self.assertEqual(f.read().strip(), "untracked content")

                            # The clean submodule does not show up at all
                            self.assertFalse(os.path.exists(os.path.join(source_dir, "sub2")))
                            self.assertFalse(os.path.exists(os.path.join(dest_dir, "sub2")))

                            # Parent repo's modified file appears directly in the root on both sides
                            with open(os.path.join(source_dir, "parentfile.txt")) as f:
                                self.assertEqual(f.read().strip(), "parent content")
                            with open(os.path.join(dest_dir, "parentfile.txt")) as f:
                                self.assertEqual(f.read().strip(), "modified parent content")

                            self.assertTrue(os.path.islink(os.path.join(dest_dir, "parentfile.txt")))

                            # Parent repo's untracked file appears only on destination side
                            self.assertFalse(os.path.exists(os.path.join(source_dir, "parent_untracked.txt")))
                            with open(os.path.join(dest_dir, "parent_untracked.txt")) as f:
                                self.assertEqual(f.read().strip(), "untracked parent content")

                            return MagicMock(returncode=0)
                        else:
                            return ORIGINAL_SUBPROCESS_RUN(cmd, *args, **kwargs)

                    mock_run.side_effect = side_effect

                    git_meld.main()

                    meld_called = False
                    for call in mock_run.call_args_list:
                        cmd_arg = call[0][0]
                        if cmd_arg[0] == 'meld' or cmd_arg[0] == '/usr/bin/meld':
                            meld_called = True
                    self.assertTrue(meld_called, "Diff tool 'meld' was not called")

        finally:
            os.chdir(orig_cwd)
            shutil.rmtree(test_dir, ignore_errors=True)

    @patch('os.fork')
    @patch('os.setsid')
    def test_main_all_submodules_no_changes(self, mock_setsid, mock_fork):
        mock_fork.return_value = 0

        import tempfile
        import shutil
        import subprocess

        test_dir = tempfile.mkdtemp(dir="/tmp")
        orig_cwd = os.getcwd()

        try:
            os.chdir(test_dir)
            subprocess.run(["git", "init", "-q"], check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], check=True)
            with open("file1.txt", "w") as f:
                f.write("content")
            subprocess.run(["git", "add", "file1.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Initial commit"], check=True)

            # No submodules at all -> "No changes found." and exit code 3
            with patch('sys.argv', ['git-meld', '--all-submodules']):
                with self.assertRaises(SystemExit) as cm:
                    git_meld.main()
                self.assertEqual(cm.exception.code, 3)

        finally:
            os.chdir(orig_cwd)
            shutil.rmtree(test_dir, ignore_errors=True)

    @patch('os.fork')
    @patch('os.setsid')
    def test_main_dest_symlink_optimization(self, mock_setsid, mock_fork):
        mock_fork.return_value = 0 # Simulate child process
        
        import tempfile
        import shutil
        import subprocess
        
        test_dir = tempfile.mkdtemp()
        orig_cwd = os.getcwd()
        os.chdir(test_dir)
        
        try:
            # Initialize git repository
            subprocess.run(["git", "init", "-q"], check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], check=True)
            
            # Commit 1
            with open("file1.txt", "w") as f:
                f.write("content 1")
            subprocess.run(["git", "add", "file1.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Commit 1"], check=True)
            
            # Commit 2 (file1 updated to "content 2", file2 added with "content A")
            with open("file1.txt", "w") as f:
                f.write("content 2")
            with open("file2.txt", "w") as f:
                f.write("content A")
            subprocess.run(["git", "add", "file1.txt", "file2.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Commit 2"], check=True)
            
            # Scenario A: dest_tree comparison (git-meld HEAD~1 HEAD)
            # Modify file2.txt in working directory to "content B" (making it different from Commit 2)
            # file1.txt remains "content 2" (identical to Commit 2)
            with open("file2.txt", "w") as f:
                f.write("content B")
                
            # Setup arguments to test git-meld comparing HEAD~1 to HEAD
            with patch('sys.argv', ['git-meld', 'HEAD~1', 'HEAD']):
                with patch('subprocess.run') as mock_run:
                    def side_effect(cmd, *args, **kwargs):
                        if cmd[0] == 'meld' or cmd[0] == '/usr/bin/meld':
                            source_dir = cmd[-2]
                            dest_dir = cmd[-1]
                            
                            dest_file1 = os.path.join(dest_dir, "file1.txt")
                            dest_file2 = os.path.join(dest_dir, "file2.txt")
                            
                            self.assertTrue(os.path.exists(dest_file1))
                            self.assertTrue(os.path.exists(dest_file2))
                            
                            # file1.txt should be a symlink because it matches working dir
                            self.assertTrue(os.path.islink(dest_file1))
                            self.assertEqual(os.readlink(dest_file1), os.path.abspath("file1.txt"))
                            
                            # file2.txt should NOT be a symlink because it differs from working dir
                            self.assertFalse(os.path.islink(dest_file2))
                            with open(dest_file2) as f:
                                self.assertEqual(f.read().strip(), "content A")
                                
                            return MagicMock(returncode=0)
                        else:
                            return ORIGINAL_SUBPROCESS_RUN(cmd, *args, **kwargs)
                            
                    mock_run.side_effect = side_effect
                    git_meld.main()

            # Scenario B: cached comparison (git-meld --cached)
            # Commit 2 is currently HEAD.
            # Stage new modifications to file1.txt and file2.txt
            with open("file1.txt", "w") as f:
                f.write("content 3")
            with open("file2.txt", "w") as f:
                f.write("content C")
            subprocess.run(["git", "add", "file1.txt", "file2.txt"], check=True)

            # Working tree has same file1.txt ("content 3") but modify file2.txt to "content D"
            with open("file2.txt", "w") as f:
                f.write("content D")

            with patch('sys.argv', ['git-meld', '--cached']):
                with patch('subprocess.run') as mock_run:
                    def side_effect(cmd, *args, **kwargs):
                        if cmd[0] == 'meld' or cmd[0] == '/usr/bin/meld':
                            source_dir = cmd[-2]
                            dest_dir = cmd[-1]
                            
                            dest_file1 = os.path.join(dest_dir, "file1.txt")
                            dest_file2 = os.path.join(dest_dir, "file2.txt")
                            
                            self.assertTrue(os.path.exists(dest_file1))
                            self.assertTrue(os.path.exists(dest_file2))
                            
                            # file1.txt should be a symlink because staging matches working tree
                            self.assertTrue(os.path.islink(dest_file1))
                            self.assertEqual(os.readlink(dest_file1), os.path.abspath("file1.txt"))
                            
                            # file2.txt should NOT be a symlink because staging differs from working tree
                            self.assertFalse(os.path.islink(dest_file2))
                            with open(dest_file2) as f:
                                self.assertEqual(f.read().strip(), "content C")
                                
                            return MagicMock(returncode=0)
                        else:
                            return ORIGINAL_SUBPROCESS_RUN(cmd, *args, **kwargs)
                            
                    mock_run.side_effect = side_effect
                    git_meld.main()
                
        finally:
            os.chdir(orig_cwd)
            shutil.rmtree(test_dir, ignore_errors=True)

    @patch('os.fork')
    @patch('os.setsid')
    def test_main_unmerged_integration(self, mock_setsid, mock_fork):
        mock_fork.return_value = 0  # Simulate child process
        
        import tempfile
        import shutil
        import subprocess
        
        test_dir = tempfile.mkdtemp()
        orig_cwd = os.getcwd()
        os.chdir(test_dir)
        
        try:
            # Initialize git repository
            subprocess.run(["git", "init", "-q"], check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "config", "user.name", "Test User"], check=True)
            
            # Commit a file
            with open("conflict.txt", "w") as f:
                f.write("base content\n")
            subprocess.run(["git", "add", "conflict.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Initial commit"], check=True)
            
            # Create and checkout branch 'branch-a'
            subprocess.run(["git", "checkout", "-q", "-b", "branch-a"], check=True)
            with open("conflict.txt", "w") as f:
                f.write("branch-a content\n")
            subprocess.run(["git", "add", "conflict.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Commit on branch-a"], check=True)
            
            # Checkout master (main)
            subprocess.run(["git", "checkout", "-q", "master"], check=True)
            with open("conflict.txt", "w") as f:
                f.write("master content\n")
            subprocess.run(["git", "add", "conflict.txt"], check=True)
            subprocess.run(["git", "commit", "-q", "-m", "Commit on master"], check=True)
            
            # Merge branch-a to cause conflict
            subprocess.run(["git", "merge", "branch-a"], capture_output=True)
            
            # Now running git-meld without arguments compares staging area to working tree
            with patch('sys.argv', ['git-meld']):
                with patch('subprocess.run') as mock_run:
                    def side_effect(cmd, *args, **kwargs):
                        if cmd[0] in {'meld', '/usr/bin/meld'}:
                            source_dir = cmd[-2]
                            dest_dir = cmd[-1]
                            
                            # Verify conflict.txt exists in both dirs
                            self.assertTrue(os.path.exists(os.path.join(source_dir, "conflict.txt")))
                            self.assertTrue(os.path.exists(os.path.join(dest_dir, "conflict.txt")))
                            
                            # Since we checked out staging area (which falls back to stage 2: master content)
                            with open(os.path.join(source_dir, "conflict.txt")) as f:
                                self.assertEqual(f.read().strip(), "master content")
                                
                            # Dest dir is working tree, so it will contain merge conflict markers
                            with open(os.path.join(dest_dir, "conflict.txt")) as f:
                                content = f.read()
                                self.assertIn("<<<<<<< HEAD", content)
                                self.assertIn("master content", content)
                                self.assertIn("branch-a content", content)
                                
                            return MagicMock(returncode=0)
                        else:
                            return ORIGINAL_SUBPROCESS_RUN(cmd, *args, **kwargs)
                            
                    mock_run.side_effect = side_effect
                    git_meld.main()
                    
                    # Verify meld was called
                    meld_called = False
                    for call in mock_run.call_args_list:
                        cmd_arg = call[0][0]
                        if cmd_arg[0] in {'meld', '/usr/bin/meld'}:
                            meld_called = True
                    self.assertTrue(meld_called, "Diff tool 'meld' was not called")
                    
        finally:
            os.chdir(orig_cwd)
            shutil.rmtree(test_dir, ignore_errors=True)

if __name__ == '__main__':
    unittest.main()
