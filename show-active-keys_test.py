#!/usr/bin/env python3
#
# Test for show-active-keys
#

import unittest
from unittest.mock import patch, MagicMock
from evdev import ecodes

# Import functions to test
# Since show-active-keys doesn't have a .py extension, we import it dynamically
import importlib.util
import importlib.machinery
import os
import sys

script_path = os.path.join(os.path.dirname(__file__), 'show-active-keys')
loader = importlib.machinery.SourceFileLoader("show_active_keys", script_path)
spec = importlib.util.spec_from_loader("show_active_keys", loader)
show_active_keys = importlib.util.module_from_spec(spec)
sys.modules["show_active_keys"] = show_active_keys
loader.exec_module(show_active_keys)

class TestShowActiveKeys(unittest.TestCase):
    @patch('evdev.list_devices')
    @patch('evdev.InputDevice')
    def test_get_active_keys(self, mock_input_device, mock_list_devices) -> None:
        mock_list_devices.return_value = ['/dev/input/event0', '/dev/input/event1']

        # Setup mock devices
        # Device 0: Keyboard with active keys A and RIGHTSHIFT
        dev0 = MagicMock()
        dev0.active_keys.return_value = [ecodes.KEY_A, ecodes.KEY_RIGHTSHIFT]

        # Device 1: Mouse with BTN_LEFT active
        dev1 = MagicMock()
        dev1.active_keys.return_value = [ecodes.BTN_LEFT]

        # Map path to mock device
        def get_mock_device(path):
            if path == '/dev/input/event0':
                return dev0
            return dev1

        mock_input_device.side_effect = get_mock_device

        # Get active keys
        keys = show_active_keys.get_active_keys()

        # Expected keys: KEY_A -> A, KEY_RIGHTSHIFT -> RIGHTSHIFT, BTN_LEFT -> BTN_LEFT
        self.assertEqual(keys, {'A', 'RIGHTSHIFT', 'BTN_LEFT'})

if __name__ == '__main__':
    unittest.main()
