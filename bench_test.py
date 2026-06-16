#!/usr/bin/env python3
#
# Unit tests for the bench script.
#
# To run this test:
#   python3 bench_test.py
#

import unittest
from unittest.mock import patch, MagicMock
import sys
import io
import os
import importlib.util
from importlib.machinery import SourceFileLoader

# Get absolute path of bench script to import it dynamically
current_dir = os.path.dirname(os.path.abspath(__file__))
bench_path = os.path.join(current_dir, "bench")

loader = SourceFileLoader("bench", bench_path)
spec = importlib.util.spec_from_file_location("bench", bench_path, loader=loader)
if spec is not None and spec.loader is not None:
    bench = importlib.util.module_from_spec(spec)
    sys.modules["bench"] = bench
    spec.loader.exec_module(bench)
else:
    raise ImportError("Could not import bench")

class TestBench(unittest.TestCase):
    @patch("subprocess.run")
    @patch("time.perf_counter")
    def test_run_benchmark(self, mock_perf_counter: MagicMock, mock_run: MagicMock) -> None:
        # We will mock the returns for perf_counter.
        # 10 runs means 20 calls to perf_counter (start and end for each run).
        # Let's say it takes 0.1s for each run.
        counter_values = []
        for i in range(10):
            counter_values.extend([float(i), float(i) + 0.1])
        mock_perf_counter.side_effect = counter_values
        
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_run.return_value = mock_result
        
        # Capture stdout and stderr
        captured_stdout = io.StringIO()
        captured_stderr = io.StringIO()
        
        with patch("sys.stdout", captured_stdout), patch("sys.stderr", captured_stderr):
            bench.run_benchmark(["echo", "ok"], 10)
            
        # Verify run_benchmark called subprocess.run 10 times with the correct arguments
        self.assertEqual(mock_run.call_count, 10)
        mock_run.assert_called_with(["echo", "ok"], stdout=None, stderr=None)
        
        # Verify output
        stdout_output = captured_stdout.getvalue()
        stderr_output = captured_stderr.getvalue()
        
        self.assertIn("Average real time: 0.1000s", stdout_output)
        self.assertIn("Min real time:     0.1000s", stderr_output)
        self.assertIn("Max real time:     0.1000s", stderr_output)
        self.assertIn("--- Run 10/10 ---", stderr_output)

    @patch("subprocess.run")
    @patch("sys.argv")
    def test_main_arguments(self, mock_argv: MagicMock, mock_run: MagicMock) -> None:
        # Test command line parsing
        with patch("sys.argv", ["bench", "-n", "3", "sleep", "1"]):
            with patch("bench.run_benchmark") as mock_run_benchmark:
                bench.main()
                mock_run_benchmark.assert_called_once_with(["sleep", "1"], 3, no_stdout=False, no_stderr=False)

    @patch("sys.argv")
    def test_main_invalid_count(self, mock_argv: MagicMock) -> None:
        with patch("sys.argv", ["bench", "-n", "0", "sleep", "1"]):
            captured_stderr = io.StringIO()
            with patch("sys.stderr", captured_stderr):
                with self.assertRaises(SystemExit):
                    bench.main()
                self.assertIn("count must be a positive integer", captured_stderr.getvalue())

    @patch("subprocess.run")
    @patch("time.perf_counter")
    def test_run_benchmark_suppress(self, mock_perf_counter: MagicMock, mock_run: MagicMock) -> None:
        # Test run_benchmark with no_stdout=True and no_stderr=True
        mock_perf_counter.side_effect = [0.0, 0.1]
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_run.return_value = mock_result
        
        captured_stdout = io.StringIO()
        captured_stderr = io.StringIO()
        
        import subprocess
        with patch("sys.stdout", captured_stdout), patch("sys.stderr", captured_stderr):
            bench.run_benchmark(["echo", "ok"], count=1, no_stdout=True, no_stderr=True)
            
        mock_run.assert_called_once_with(["echo", "ok"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @patch("subprocess.run")
    @patch("sys.argv")
    def test_main_arguments_suppress(self, mock_argv: MagicMock, mock_run: MagicMock) -> None:
        # Test command line parsing with suppression options
        with patch("sys.argv", ["bench", "--no-stdout", "--no-stderr", "sleep", "1"]):
            with patch("bench.run_benchmark") as mock_run_benchmark:
                bench.main()
                mock_run_benchmark.assert_called_once_with(
                    ["sleep", "1"], 10, no_stdout=True, no_stderr=True
                )

if __name__ == "__main__":
    unittest.main()
