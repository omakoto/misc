#!/usr/bin/env python3
# bthome-sniff_test.py - Unit tests for bthome-sniff (BTHome v2 payload decoding and --help).
# Payloads are real captures from a Shelly BLU RC Button 4 and a BLU Remote Control ZB.
# Run: python3 bthome-sniff_test.py

import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import unittest

# Dynamically import bthome-sniff (extensionless script).
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bthome-sniff")
loader = importlib.machinery.SourceFileLoader("bthome_sniff", SCRIPT)
spec = importlib.util.spec_from_file_location("bthome_sniff", SCRIPT, loader=loader)
bthome_sniff = importlib.util.module_from_spec(spec)
sys.modules["bthome_sniff"] = bthome_sniff
spec.loader.exec_module(bthome_sniff)


def decode(hex_payload: str) -> str:
    return bthome_sniff.decode_bthome(bytes.fromhex(hex_payload))


class DecodeTest(unittest.TestCase):
    def test_four_button_remote_press(self) -> None:
        out = decode("44001f01643a013a003a003a00")
        self.assertIn("packet_id=31", out)
        self.assertIn("battery_%=100", out)
        self.assertIn("buttons=[1:press, 2:-, 3:-, 4:-]", out)

    def test_four_button_remote_double_triple_hold(self) -> None:
        self.assertIn("1:double_press", decode("44002001643a023a003a003a00"))
        self.assertIn("4:triple_press", decode("44002301643a003a003a003a03"))
        self.assertIn("4:hold_press", decode("44002701643a003a003a003a80"))

    def test_remote_control_buttons_and_channel(self) -> None:
        out = decode("44005901643a013a006000")
        self.assertIn("buttons=[1:press, 2:-]", out)
        self.assertIn("channel=0", out)
        out = decode("44006c01643a003a016003")
        self.assertIn("buttons=[1:-, 2:press]", out)
        self.assertIn("channel=3", out)

    def test_remote_control_wheel(self) -> None:
        self.assertIn("dimmer=rotate_left steps=0", decode("44005b01643c01006000"))
        out = decode("44007401643c02986003")
        self.assertIn("dimmer=rotate_right steps=152", out)
        self.assertIn("channel=3", out)

    def test_encrypted_payload_is_not_parsed(self) -> None:
        out = decode("45aabbcc")
        self.assertIn("ENCRYPTED", out)
        self.assertIn("payload=aabbcc", out)

    def test_unknown_object_stops_parsing(self) -> None:
        out = decode("44ff1122")
        self.assertIn("unknown_obj_0xff rest=1122", out)

    def test_truncated_object(self) -> None:
        self.assertIn("TRUNCATED", decode("44003c01"))

    def test_empty_payload(self) -> None:
        self.assertEqual(bthome_sniff.decode_bthome(b""), "(empty)")


class UuidTest(unittest.TestCase):
    def test_uuid16_expands_to_bluetooth_base_uuid(self) -> None:
        self.assertEqual(bthome_sniff.uuid16(0xFCD2), "0000fcd2-0000-1000-8000-00805f9b34fb")


class AdvertKeyTest(unittest.TestCase):
    def test_manufacturer_counter_is_ignored_when_service_data_exists(self) -> None:
        service = {"0000fd3d-0000-1000-8000-00805f9b34fb": "7600"}
        first = bthome_sniff.advert_key(service, {2409: "e6dbefbc507a00ff6ad53834"})
        second = bthome_sniff.advert_key(service, {2409: "e6dbefbc507a00ff6ad53835"})
        self.assertEqual(first, second)

    def test_service_data_change_is_detected(self) -> None:
        mfg = {2409: "e6dbefbc507a"}
        first = bthome_sniff.advert_key({"0000fd3d-0000-1000-8000-00805f9b34fb": "7600"}, mfg)
        second = bthome_sniff.advert_key({"0000fd3d-0000-1000-8000-00805f9b34fb": "7601"}, mfg)
        self.assertNotEqual(first, second)

    def test_manufacturer_data_is_used_without_service_data(self) -> None:
        first = bthome_sniff.advert_key({}, {76: "0215aa"})
        second = bthome_sniff.advert_key({}, {76: "0215ab"})
        self.assertNotEqual(first, second)


class HelpTest(unittest.TestCase):
    def test_help_works_without_bleak(self) -> None:
        # --help must not need the bluetooth library (or trigger the venv bootstrap).
        result = subprocess.run([sys.executable, SCRIPT, "--help"], capture_output=True,
                                text=True, timeout=30)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Examples:", result.stdout)


if __name__ == "__main__":
    unittest.main()
