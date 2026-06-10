#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Test runner wrapper for git-meld-history.py.
# Runs the integration test suite in git-meld-history_test.bash targeting git-meld-history.py.

import subprocess
import sys
import os

def main() -> None:
    env: dict[str, str] = os.environ.copy()
    env["TARGET_SCRIPT"] = "git-meld-history.py"
    script_dir: str = os.path.dirname(os.path.abspath(__file__))
    res: subprocess.CompletedProcess[bytes] = subprocess.run(
        ["./git-meld-history_test.bash"],
        cwd=script_dir,
        env=env
    )
    sys.exit(res.returncode)

if __name__ == "__main__":
    main()
