#!/usr/bin/env python3
"""
Convert filenames in input to fullpath.
Python rewrite of misc/fullpathifier.
"""

import os
import sys
import re

def get_cwd():
    # Prefer PWD to getcwd because it doesn't have symlinks resolved.
    cwd = os.environ.get("PWD") or os.getcwd()
    if not cwd.endswith("/"):
        cwd += "/"
    return cwd

def main():
    # Flush stdout after every line
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(line_buffering=True)

    file_re_chars = os.environ.get("FILE_RE_CHARS", r"A-Za-z0-9\-\,\.\/\%\_\+\@\~\$\{\}")
    pattern = re.compile("([" + file_re_chars + "]+)")

    file_cache = {}

    def is_file(path):
        if path not in file_cache:
            file_cache[path] = os.path.exists(path)
        return file_cache[path]

    cwd = get_cwd()

    def fullpathify(file_path):
        if file_path.startswith("/"):
            return file_path
        if is_file(file_path):
            ret = f"{cwd}{file_path}"
            ret = ret.replace("/./", "/")
            return ret
        return file_path

    # Read from files in sys.argv or stdin if none provided.
    files = sys.argv[1:]
    if not files:
        files = ['-']

    def get_lines():
        for filepath in files:
            if filepath == '-':
                for line in sys.stdin:
                    yield line
            else:
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                        for line in f:
                            yield line
                except Exception as e:
                    sys.stderr.write(f"fullpathifier: {filepath}: {e}\n")

    try:
        for line in get_lines():
            # chomp behavior: strip trailing newline and carriage return
            # But keep other spaces! So rstrip("\r\n") is perfect.
            stripped_line = line.rstrip("\r\n")

            # Match entering directory lines
            m = re.search(r"Entering directory [`']([^']+)'", stripped_line)
            if m:
                print(stripped_line)
                d = m.group(1)
                if d != "." and os.path.isdir(d):
                    try:
                        os.chdir(d)
                    except Exception as e:
                        sys.stderr.write(f"fullpathifier: chdir {d}: {e}\n")
                    
                    pwd = os.environ.get("PWD", "")
                    if not pwd:
                        pwd = os.getcwd()
                    if d.startswith("/"):
                        pwd = d
                    else:
                        pwd = pwd.rstrip("/") + "/" + d
                    os.environ["PWD"] = pwd
                    cwd = get_cwd()
                file_cache.clear()
                continue

            # Replace paths
            # In Python, pattern.sub can take a function that receives a Match object.
            # We want to replace the matched path with fullpathify(match.group(0)).
            replaced_line = pattern.sub(lambda match: fullpathify(match.group(0)), stripped_line)
            print(replaced_line)
    except BrokenPipeError:
        # Exit silently if downstream pipe is closed.
        try:
            sys.stdout.close()
        except OSError:
            pass
        try:
            sys.stderr.close()
        except OSError:
            pass
        sys.exit(141)

if __name__ == "__main__":
    main()
