#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for dconf-backup.

Run with:
  python3 misc/dconf-backup_test.py
"""

import importlib.machinery
import importlib.util
import os
import unittest

# Load dconf-backup (no .py extension) using SourceFileLoader.
_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dconf-backup')
_loader = importlib.machinery.SourceFileLoader('dconf_backup', _SCRIPT)
_spec = importlib.util.spec_from_loader('dconf_backup', _loader)
dconf_backup = importlib.util.module_from_spec(_spec)
_loader.exec_module(dconf_backup)

HOME = '/home/testuser'


class TestNormalizeHome(unittest.TestCase):
    """Tests for normalize_home()."""

    def test_path_with_trailing_slash(self) -> None:
        line = "command='/home/testuser/cbin/script'"
        self.assertEqual(dconf_backup.normalize_home(line, HOME),
                         "command='$HOME/cbin/script'")

    def test_exact_home_no_slash(self) -> None:
        line = "path='/home/testuser'"
        self.assertEqual(dconf_backup.normalize_home(line, HOME),
                         "path='$HOME'")

    def test_list_with_multiple_homes(self) -> None:
        line = "list=['/home/testuser', '/home/testuser/sub']"
        self.assertEqual(dconf_backup.normalize_home(line, HOME),
                         "list=['$HOME', '$HOME/sub']")

    def test_no_replacement_when_not_after_quote(self) -> None:
        # /home/testuser not preceded by ' — must NOT be replaced.
        line = "other=/home/testuser/thing"
        self.assertEqual(dconf_backup.normalize_home(line, HOME), line)

    def test_unrelated_user_path_untouched(self) -> None:
        line = "path='/home/otheruser/cbin'"
        self.assertEqual(dconf_backup.normalize_home(line, HOME), line)

    def test_no_home_reference(self) -> None:
        line = "name='1work'"
        self.assertEqual(dconf_backup.normalize_home(line, HOME), line)

    def test_home_with_no_content_after(self) -> None:
        # Edge: value is exactly the home directory, no trailing quote yet
        line = "x='/home/testuser/a'"
        result = dconf_backup.normalize_home(line, HOME)
        self.assertIn("'$HOME/", result)


class TestProcessDumpOutput(unittest.TestCase):
    """Tests for process_dump_output()."""

    def _process(self, path: str, raw: str) -> str:
        return dconf_backup.process_dump_output(path, raw, HOME)

    # --- Section headers ---

    def test_root_section_becomes_base_path_header(self) -> None:
        out = self._process('/org/cinnamon/', "[/]\nkey='v'\n")
        self.assertIn('[org/cinnamon]\n', out)

    def test_section_header_no_leading_slash(self) -> None:
        out = self._process('/org/cinnamon/', "[/]\nk='v'\n")
        for line in out.splitlines():
            if line.startswith('[') and line != '[/]':
                self.assertFalse(line.startswith('[/'),
                                 f'Header has leading slash: {line!r}')

    def test_section_header_no_trailing_slash(self) -> None:
        out = self._process('/org/cinnamon/', "[/]\nk='v'\n")
        for line in out.splitlines():
            if line.startswith('['):
                self.assertFalse(line.endswith('/]'),
                                 f'Header ends with slash: {line!r}')

    def test_subsection_header(self) -> None:
        raw = "[/]\nk='v'\n\n[custom-keybindings/custom0]\nname='x'\n"
        out = self._process('/org/cinnamon/desktop/keybindings/', raw)
        self.assertIn('[org/cinnamon/desktop/keybindings/custom-keybindings/custom0]\n', out)

    # --- Key prefixes ---

    def test_root_section_key_gets_base_prefix(self) -> None:
        out = self._process('/org/cinnamon/', "[/]\nmy-key='hello'\n")
        self.assertIn('/org/cinnamon/my-key=', out)

    def test_subsection_key_gets_full_prefix(self) -> None:
        raw = "[sub/path]\nk='v'\n"
        out = self._process('/org/cinnamon/', raw)
        self.assertIn('/org/cinnamon/sub/path/k=', out)

    def test_multiple_subsections_get_correct_prefixes(self) -> None:
        raw = (
            "[/]\ntop='a'\n\n"
            "[custom/sub0]\nname='sub0'\n\n"
            "[custom/sub1]\nname='sub1'\n"
        )
        out = self._process('/org/cinnamon/desktop/keybindings/', raw)
        self.assertIn('/org/cinnamon/desktop/keybindings/top=', out)
        self.assertIn('/org/cinnamon/desktop/keybindings/custom/sub0/name=', out)
        self.assertIn('/org/cinnamon/desktop/keybindings/custom/sub1/name=', out)

    # --- Blank lines ---

    def test_blank_lines_preserved(self) -> None:
        raw = "[/]\nk='v'\n\n[sub]\nk2='v2'\n"
        out = self._process('/org/test/', raw)
        self.assertIn('\n\n', out)

    # --- $HOME normalization ---

    def test_home_normalized_in_value(self) -> None:
        raw = "[/]\ncmd='/home/testuser/script'\n"
        out = self._process('/org/test/', raw)
        self.assertIn("cmd='$HOME/script'", out)

    # --- Root dump (path='/') ---

    def test_root_dump_root_section_stays_slash(self) -> None:
        raw = "[/]\nkey='val'\n"
        out = self._process('/', raw)
        self.assertIn('[/]\n', out)

    def test_root_dump_subsection_stays_unmodified(self) -> None:
        raw = "[/]\nkey='val'\n\n[org/gnome]\nk2='v2'\n"
        out = self._process('/', raw)
        self.assertIn('[org/gnome]\n', out)

    def test_root_dump_keys_have_slash_prefix(self) -> None:
        raw = "[/]\nkey='val'\n\n[org/gnome]\nk2='v2'\n"
        out = self._process('/', raw)
        self.assertIn('/key=', out)
        self.assertIn('/org/gnome/k2=', out)

    # --- Path normalization ---

    def test_path_without_trailing_slash_gives_same_result(self) -> None:
        # process_dump_output strips the path cleanly regardless of trailing slash
        raw = "[/]\nk='v'\n"
        out1 = self._process('/org/cinnamon/', raw)
        out2 = self._process('/org/cinnamon', raw)
        self.assertEqual(out1, out2)


if __name__ == '__main__':
    unittest.main()
