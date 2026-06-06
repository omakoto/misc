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
        revs, paths, cached, no_rename, help_req = git_meld.parse_arguments([])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertFalse(cached)
        self.assertFalse(no_rename)
        self.assertFalse(help_req)

    def test_parse_arguments_cached(self):
        revs, paths, cached, no_rename, help_req = git_meld.parse_arguments(["--cached"])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertTrue(cached)
        self.assertFalse(no_rename)
        self.assertFalse(help_req)

    def test_parse_arguments_no_rename(self):
        revs, paths, cached, no_rename, help_req = git_meld.parse_arguments(["--no-rename-detection"])
        self.assertEqual(revs, [])
        self.assertEqual(paths, [])
        self.assertFalse(cached)
        self.assertTrue(no_rename)
        self.assertFalse(help_req)

    def test_parse_arguments_help(self):
        _, _, _, _, help_req = git_meld.parse_arguments(["-h"])
        self.assertTrue(help_req)
        _, _, _, _, help_req = git_meld.parse_arguments(["--help"])
        self.assertTrue(help_req)

    @patch('git_meld.parse_rev_or_range')
    def test_parse_arguments_revs_and_paths(self, mock_parse_rev):
        # Mock git revision check to return True for commit names
        mock_parse_rev.side_effect = lambda x: x in {"HEAD", "HEAD~1", "master", "feature", "master..feature"}
        
        revs, paths, cached, no_rename, help_req = git_meld.parse_arguments(["HEAD~1", "--", "file1.txt"])
        self.assertEqual(revs, ["HEAD~1"])
        self.assertEqual(paths, ["file1.txt"])
        
        # Test range
        revs, paths, cached, no_rename, help_req = git_meld.parse_arguments(["master..feature", "dir/"])
        self.assertEqual(revs, ["master..feature"])
        self.assertEqual(paths, ["dir/"])

    def test_sanitize_dir_name(self):
        self.assertEqual(git_meld.sanitize_dir_name("HEAD"), "HEAD")
        self.assertEqual(git_meld.sanitize_dir_name("HEAD~1"), "HEAD~1")
        self.assertEqual(git_meld.sanitize_dir_name("master/feature"), "master_feature")
        self.assertEqual(git_meld.sanitize_dir_name("a:b\\c?d*e"), "a_b_c_d_e")

    @patch('subprocess.run')
    def test_query_diff_status(self, mock_run):
        # We simulate git diff output with renames, modifications, and deletions.
        # Format of git diff -z --name-status is:
        # STATUS \0 PATH1 \0 (PATH2 \0 if rename)
        mock_stdout = (
            b"M\0file1.txt\0"
            b"R100\0old_file.txt\0new_file.txt\0"
            b"D\0deleted_file.txt\0"
            b"A\0added_file.txt\0"
        )
        mock_run.return_value = MagicMock(stdout=mock_stdout)
        
        src, dest, renames = git_meld.query_diff_status(["HEAD"])
        
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

if __name__ == '__main__':
    unittest.main()
