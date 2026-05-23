#!/usr/bin/env python3
import sys
import os
import unittest
from unittest.mock import patch, MagicMock
import importlib.util

# Dynamically import color-picker (extensionless script)
import importlib.machinery
script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'color-picker')
loader = importlib.machinery.SourceFileLoader("color_picker", script_path)
spec = importlib.util.spec_from_file_location("color_picker", script_path, loader=loader)
color_picker = importlib.util.module_from_spec(spec)
sys.modules["color_picker"] = color_picker
spec.loader.exec_module(color_picker)

class ColorPickerTest(unittest.TestCase):
    def setUp(self):
        # Reset state to default before each test
        color_picker.state = {
            'bold': False,
            'faint': False,
            'italics': False,
            'bash_string': False,
            'fg_color': 15,
            'fg_trans': False,
            'bg_color': 0,
            'bg_trans': True
        }
        # Reset click map
        color_picker.click_map = {}

    def test_default_output(self):
        # Default options, bash_string=False
        self.assertEqual(color_picker.get_output_string(), "\\e[38;5;15m")

    def test_default_output_bash_string(self):
        # Default options, bash_string=True
        color_picker.state['bash_string'] = True
        self.assertEqual(color_picker.get_output_string(), "$'\\e[38;5;15m'")

    def test_modifiers(self):
        color_picker.state['bold'] = True
        color_picker.state['italics'] = True
        self.assertEqual(color_picker.get_output_string(), "\\e[1;3;38;5;15m")
        
        color_picker.state['bash_string'] = True
        self.assertEqual(color_picker.get_output_string(), "$'\\e[1;3;38;5;15m'")

    def test_transparency(self):
        color_picker.state['fg_trans'] = True
        color_picker.state['bg_trans'] = True
        self.assertEqual(color_picker.get_output_string(), "\\e[0m")
        
        color_picker.state['bash_string'] = True
        self.assertEqual(color_picker.get_output_string(), "$'\\e[0m'")

    @patch('color_picker.copy_to_clipboard')
    def test_update_selection(self, mock_copy):
        color_picker.update_selection(fg=10, bg=20)
        self.assertEqual(color_picker.state['fg_color'], 10)
        self.assertEqual(color_picker.state['bg_color'], 20)
        self.assertFalse(color_picker.state['fg_trans'])
        self.assertFalse(color_picker.state['bg_trans'])
        mock_copy.assert_called_with("\\e[38;5;10;48;5;20m")

    @patch('color_picker.restore_terminal')
    @patch('sys.stdout')
    def test_select_color_and_exit(self, mock_stdout, mock_restore):
        color_picker.state['bash_string'] = True
        with self.assertRaises(SystemExit) as cm:
            color_picker.select_color_and_exit()
        self.assertEqual(cm.exception.code, 0)
        mock_stdout.write.assert_any_call("$'\\e[38;5;15m'\n")

    @patch('color_picker.setup_terminal')
    @patch('color_picker.restore_terminal')
    @patch('color_picker.copy_to_clipboard')
    @patch('sys.stderr')
    @patch('sys.stdout')
    @patch('color_picker.read_key')
    def test_mouse_click_bash_string(self, mock_read_key, mock_stdout, mock_stderr, mock_copy, mock_restore, mock_setup):
        # 1. Populate click_map by drawing screen
        color_picker.draw_screen()
        
        # 2. Find coordinates for 'toggle', 'bash_string'
        coords = [k for k, v in color_picker.click_map.items() if v == ('toggle', 'bash_string')]
        self.assertTrue(len(coords) > 0, "Bash string checkbox should be in click_map")
        
        cx, cy = coords[0]
        
        # 3. Yield mouse click release on the checkbox, then exit loop with 'q'
        mock_read_key.side_effect = [
            ('mouse', 0, cx, cy, False),
            'q'
        ]
        
        self.assertFalse(color_picker.state['bash_string'])
        with self.assertRaises(SystemExit) as cm:
            color_picker.main()
        self.assertEqual(cm.exception.code, 0)
        self.assertTrue(color_picker.state['bash_string'])
        mock_copy.assert_called_with("$'\\e[38;5;15m'")

    @patch('color_picker.setup_terminal')
    @patch('color_picker.restore_terminal')
    @patch('color_picker.copy_to_clipboard')
    @patch('sys.stderr')
    @patch('sys.stdout')
    @patch('color_picker.read_key')
    def test_mouse_click_bold(self, mock_read_key, mock_stdout, mock_stderr, mock_copy, mock_restore, mock_setup):
        color_picker.draw_screen()
        coords = [k for k, v in color_picker.click_map.items() if v == ('toggle', 'bold')]
        self.assertTrue(len(coords) > 0, "Bold checkbox should be in click_map")
        
        cx, cy = coords[0]
        
        mock_read_key.side_effect = [
            ('mouse', 0, cx, cy, False),
            'q'
        ]
        
        self.assertFalse(color_picker.state['bold'])
        with self.assertRaises(SystemExit) as cm:
            color_picker.main()
        self.assertEqual(cm.exception.code, 0)
        self.assertTrue(color_picker.state['bold'])
        mock_copy.assert_called_with("\\e[1;38;5;15m")

if __name__ == '__main__':
    unittest.main()
