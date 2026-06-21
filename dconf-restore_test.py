#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Unit tests for dconf-restore.

Run with:
  python3 misc/dconf-restore_test.py
"""

import importlib.machinery
import importlib.util
import os
import unittest

# Load dconf-restore (no .py extension) using SourceFileLoader.
_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dconf-restore')
_loader = importlib.machinery.SourceFileLoader('dconf_restore', _SCRIPT)
_spec = importlib.util.spec_from_loader('dconf_restore', _loader)
dconf_restore = importlib.util.module_from_spec(_spec)
_loader.exec_module(dconf_restore)

HOME = '/home/testuser'


class TestExpandHome(unittest.TestCase):
    """Tests for expand_home()."""

    def test_expand_home_with_slash(self) -> None:
        line = "cmd='$HOME/cbin/script'"
        self.assertEqual(dconf_restore.expand_home(line, HOME),
                         "cmd='/home/testuser/cbin/script'")

    def test_expand_home_exact(self) -> None:
        line = "path='$HOME'"
        self.assertEqual(dconf_restore.expand_home(line, HOME),
                         "path='/home/testuser'")

    def test_expand_home_list(self) -> None:
        line = "list=['$HOME', '$HOME/sub']"
        self.assertEqual(dconf_restore.expand_home(line, HOME),
                         "list=['/home/testuser', '/home/testuser/sub']")

    def test_no_home_unchanged(self) -> None:
        line = "name='1work'"
        self.assertEqual(dconf_restore.expand_home(line, HOME), line)

    def test_home_not_after_quote_unchanged(self) -> None:
        # $HOME not preceded by ' — must NOT be replaced.
        line = "other=$HOME/thing"
        self.assertEqual(dconf_restore.expand_home(line, HOME), line)

    def test_no_double_expansion(self) -> None:
        # '$HOME/sub' should expand to real path, not double-expand
        line = "x='$HOME/a'"
        result = dconf_restore.expand_home(line, HOME)
        self.assertEqual(result, "x='/home/testuser/a'")
        self.assertNotIn('$HOME', result)


class TestStripKeyPrefix(unittest.TestCase):
    """Tests for strip_key_prefix()."""

    def test_single_level_prefix(self) -> None:
        line = "/org/cinnamon/key=['a', 'b']"
        self.assertEqual(dconf_restore.strip_key_prefix(line), "key=['a', 'b']")

    def test_deep_prefix(self) -> None:
        line = "/org/cinnamon/desktop/keybindings/custom0/name='1work'"
        self.assertEqual(dconf_restore.strip_key_prefix(line), "name='1work'")

    def test_value_contains_equals(self) -> None:
        # Only the first '=' is the key=value separator.
        line = "/org/test/key='a=b=c'"
        self.assertEqual(dconf_restore.strip_key_prefix(line), "key='a=b=c'")

    def test_root_key(self) -> None:
        # Key directly at root level: /keyname=value
        line = "/keyname='val'"
        self.assertEqual(dconf_restore.strip_key_prefix(line), "keyname='val'")

    def test_no_equals_passthrough(self) -> None:
        line = "/org/cinnamon/no-equals-here"
        self.assertEqual(dconf_restore.strip_key_prefix(line), line)

    def test_gvariant_value(self) -> None:
        # GVariant typed value like @as []
        line = "/org/test/my-key=@as []"
        self.assertEqual(dconf_restore.strip_key_prefix(line), "my-key=@as []")


class TestProcessLine(unittest.TestCase):
    """Tests for process_line()."""

    def _pl(self, line: str) -> str:
        return dconf_restore.process_line(line, HOME)

    def test_section_header_passthrough(self) -> None:
        line = '[org/cinnamon/desktop/keybindings]\n'
        self.assertEqual(self._pl(line), line)

    def test_root_section_passthrough(self) -> None:
        line = '[/]\n'
        self.assertEqual(self._pl(line), line)

    def test_blank_line_passthrough(self) -> None:
        self.assertEqual(self._pl('\n'), '\n')

    def test_key_prefix_stripped(self) -> None:
        line = "/org/cinnamon/desktop/keybindings/custom-list=['custom9']\n"
        self.assertEqual(self._pl(line), "custom-list=['custom9']\n")

    def test_home_expanded_in_value(self) -> None:
        line = "/org/test/cmd='$HOME/cbin/script'\n"
        self.assertEqual(self._pl(line), "cmd='/home/testuser/cbin/script'\n")

    def test_home_exact_expanded(self) -> None:
        line = "/org/test/path='$HOME'\n"
        self.assertEqual(self._pl(line), "path='/home/testuser'\n")

    def test_non_path_line_passthrough(self) -> None:
        # Unexpected content not starting with '/' — pass through.
        line = 'some-unexpected-content\n'
        self.assertEqual(self._pl(line), line)

    def test_gvariant_empty_array(self) -> None:
        line = '/org/test/my-key=@as []\n'
        self.assertEqual(self._pl(line), 'my-key=@as []\n')

    def test_deep_subsection_key(self) -> None:
        line = "/org/cinnamon/desktop/keybindings/custom-keybindings/custom0/binding=['<Primary><Alt>minus']\n"
        result = self._pl(line)
        self.assertEqual(result, "binding=['<Primary><Alt>minus']\n")

    def test_roundtrip_home(self) -> None:
        backup_line = "/org/test/command='$HOME/cbin/1work'\n"
        restored = self._pl(backup_line)
        self.assertEqual(restored, "command='/home/testuser/cbin/1work'\n")

    def test_root_dump_key(self) -> None:
        # Key from root dump: /keyname=value (single slash prefix)
        line = "/some-root-key='hello'\n"
        self.assertEqual(self._pl(line), "some-root-key='hello'\n")


if __name__ == '__main__':
    unittest.main()
