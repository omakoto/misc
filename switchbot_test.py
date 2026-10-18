#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Unit tests for switchbot. They mock all HTTP calls and never contact the real API.
# Run this test suite with: python3 -m unittest ~/cbin/misc/switchbot_test.py

import base64
import hashlib
import hmac
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from typing import Any, Optional
from unittest.mock import MagicMock, patch

# Dynamically import switchbot (extensionless script)
script_path: str = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'switchbot')
loader: importlib.machinery.SourceFileLoader = importlib.machinery.SourceFileLoader("switchbot", script_path)
spec: Optional[importlib.machinery.ModuleSpec] = importlib.util.spec_from_file_location("switchbot", script_path, loader=loader)
if spec is None or spec.loader is None:
    raise ImportError("Could not load switchbot")
switchbot: Any = importlib.util.module_from_spec(spec)
sys.modules["switchbot"] = switchbot
spec.loader.exec_module(switchbot)

DEVICES_BODY: dict[str, Any] = {
    "deviceList": [
        {"deviceId": "AA01", "deviceName": "Light on", "deviceType": "Bot", "hubDeviceId": "HUB1"},
        {"deviceId": "AA02", "deviceName": "Light off", "deviceType": "Bot", "hubDeviceId": "HUB1"},
        {"deviceId": "AA03", "deviceName": "Garage Dehumidifier ", "deviceType": "Plug Mini (US)", "hubDeviceId": ""},
    ],
    "infraredRemoteList": [
        {"deviceId": "01-123", "deviceName": "TV", "remoteType": "TV", "hubDeviceId": "HUB1"},
        {"deviceId": "01-456", "deviceName": "TV's copy", "remoteType": "TV", "hubDeviceId": "HUB1"},
    ],
}


def make_response(payload: Any) -> MagicMock:
    res = MagicMock()
    res.read.return_value = json.dumps(payload).encode()
    res.__enter__.return_value = res
    return res


class ParseConfigTest(unittest.TestCase):
    def test_firmware_compatible_syntax(self) -> None:
        text = """
# comment
switchbot_token=abc123
switchbot_key = "quoted # not a comment"
other = 'single'
trailing = value # comment
no_equals_line
wifi_ssid = first
wifi_ssid = second
"""
        self.assertEqual(switchbot.parse_config(text), {
            "switchbot_token": "abc123",
            "switchbot_key": "quoted # not a comment",
            "other": "single",
            "trailing": "value",
            "wifi_ssid": "second",
        })

    def test_load_credentials(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as f:
            f.write("switchbot_token=tok\nswitchbot_key=sec\n")
        try:
            self.assertEqual(switchbot.load_credentials(f.name), ("tok", "sec"))
            with patch.dict(os.environ, {"ESP32_CONFIG_TOML": f.name}):
                self.assertEqual(switchbot.load_credentials(None), ("tok", "sec"))
        finally:
            os.unlink(f.name)

    def test_load_credentials_missing_key(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as f:
            f.write("switchbot_token=tok\n")
        try:
            with self.assertRaisesRegex(switchbot.SwitchBotError, "no switchbot_key"):
                switchbot.load_credentials(f.name)
        finally:
            os.unlink(f.name)

    def test_load_credentials_no_env(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(switchbot.SwitchBotError, "ESP32_CONFIG_TOML is not set"):
                switchbot.load_credentials(None)


class AuthHeadersTest(unittest.TestCase):
    def test_signature(self) -> None:
        headers = switchbot.make_auth_headers("tok", "sec", t="1700000000000", nonce="n-1")
        expected = base64.b64encode(
            hmac.new(b"sec", b"tok1700000000000n-1", hashlib.sha256).digest()).decode()
        self.assertEqual(headers["Authorization"], "tok")
        self.assertEqual(headers["t"], "1700000000000")
        self.assertEqual(headers["nonce"], "n-1")
        self.assertEqual(headers["sign"], expected)

    def test_generated_timestamp_and_nonce(self) -> None:
        headers = switchbot.make_auth_headers("tok", "sec")
        self.assertEqual(len(headers["t"]), 13)
        self.assertNotEqual(headers["nonce"], switchbot.make_auth_headers("tok", "sec")["nonce"])


class ResolveTest(unittest.TestCase):
    def setUp(self) -> None:
        self.items = switchbot.device_items(DEVICES_BODY)

    def test_by_id(self) -> None:
        self.assertEqual(switchbot.resolve("AA02", self.items, "device").name, "Light off")

    def test_exact_name_case_insensitive(self) -> None:
        self.assertEqual(switchbot.resolve("light ON", self.items, "device").id, "AA01")

    def test_exact_name_beats_substring(self) -> None:
        # "TV" is also a substring of "TV's copy".
        self.assertEqual(switchbot.resolve("tv", self.items, "device").id, "01-123")

    def test_exact_name_ignores_surrounding_whitespace(self) -> None:
        self.assertEqual(switchbot.resolve("garage dehumidifier", self.items, "device").id, "AA03")

    def test_unique_substring(self) -> None:
        self.assertEqual(switchbot.resolve("copy", self.items, "device").id, "01-456")

    def test_ambiguous(self) -> None:
        with self.assertRaisesRegex(switchbot.SwitchBotError, "ambiguous"):
            switchbot.resolve("light", self.items, "device")

    def test_not_found(self) -> None:
        with self.assertRaisesRegex(switchbot.SwitchBotError, "no device matches"):
            switchbot.resolve("nosuch", self.items, "device")

    def test_ir_remote_kind(self) -> None:
        self.assertEqual(switchbot.resolve("01-123", self.items, "device").kind, "IR TV")


class DeviceCommandsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.items = {i.id: i for i in switchbot.device_items(DEVICES_BODY)}

    def commands_of(self, item: Any) -> list[str]:
        return [c for c, _, _ in switchbot.device_commands(item)[0]]

    def test_physical_device(self) -> None:
        rows, notes = switchbot.device_commands(self.items["AA01"])
        self.assertEqual([c for c, _, _ in rows], ["turnOff", "turnOn", "press"])
        self.assertEqual(notes, [])

    def test_undocumented_device_type(self) -> None:
        rows, notes = switchbot.device_commands(switchbot.Item("X", "Meter", "WoIOSensor"))
        self.assertEqual(rows, [])
        self.assertIn("No commands are documented", notes[0])

    def test_ir_remote_gets_common_and_type_commands(self) -> None:
        commands = self.commands_of(self.items["01-123"])
        self.assertEqual(commands[:2], ["turnOn", "turnOff"])
        self.assertIn("volumeAdd", commands)
        self.assertIn("--customize", switchbot.device_commands(self.items["01-123"])[1][0])

    def test_diy_remote_uses_base_type(self) -> None:
        item = switchbot.Item("03-1", "Room fan", "IR DIY Fan", remote_type="DIY Fan")
        self.assertIn("swing", self.commands_of(item))
        self.assertIn("learned (DIY)", switchbot.device_commands(item)[1][1])

    def test_others_remote_has_only_custom_buttons(self) -> None:
        item = switchbot.Item("01-9", "Others", "IR Others", remote_type="Others")
        rows, notes = switchbot.device_commands(item)
        self.assertEqual(rows, [])
        self.assertIn("custom buttons", notes[0])

    def test_ir_type_aliases(self) -> None:
        for remote_type in ("Streamer", "Set Top Box", "DVD Player"):
            item = switchbot.Item("01-9", "x", f"IR {remote_type}", remote_type=remote_type)
            self.assertGreater(len(self.commands_of(item)), 2, remote_type)

    def test_tables_are_clean(self) -> None:
        tables = list(switchbot.DEVICE_COMMANDS.values()) + list(switchbot.IR_COMMANDS.values())
        for row in [r for rows in tables for r in rows] + switchbot.IR_COMMON_COMMANDS:
            self.assertEqual(len(row), 3, row)
            self.assertTrue(row[0], row)
            for cell in row:
                self.assertNotIn("<br", cell, row)
                self.assertNotIn("`", cell, row)


class ClientTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = switchbot.Client("tok", "sec")

    @patch("urllib.request.urlopen")
    def test_command_request(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = make_response({"statusCode": 100, "body": {}, "message": "success"})
        self.client.command("AA01", "press")
        req = mock_urlopen.call_args.args[0]
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.full_url, "https://api.switch-bot.com/v1.1/devices/AA01/commands")
        self.assertEqual(json.loads(req.data),
                         {"command": "press", "parameter": "default", "commandType": "command"})
        self.assertEqual(req.get_header("Authorization"), "tok")

    @patch("urllib.request.urlopen")
    def test_returns_body(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = make_response({"statusCode": 100, "body": [{"sceneId": "s"}]})
        self.assertEqual(self.client.scenes(), [{"sceneId": "s"}])

    @patch("urllib.request.urlopen")
    def test_api_error(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = make_response({"statusCode": 161, "body": {}, "message": ""})
        with self.assertRaisesRegex(switchbot.SwitchBotError, "API error 161: device offline"):
            self.client.status("AA01")

    @patch("urllib.request.urlopen")
    def test_api_error_with_message(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = make_response({"statusCode": 160, "body": {}, "message": "unknown command"})
        with self.assertRaisesRegex(switchbot.SwitchBotError, r"unknown command \(command is not supported"):
            self.client.command("AA01", "bogus")

    @patch("urllib.request.urlopen")
    def test_http_401(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.side_effect = urllib.error.HTTPError(
            "url", 401, "Unauthorized", {}, io.BytesIO(b'{"message":"Unauthorized"}'))  # type: ignore[arg-type]
        with self.assertRaisesRegex(switchbot.SwitchBotError, "authentication failed"):
            self.client.devices()

    @patch("urllib.request.urlopen")
    def test_verbose_does_not_print_credentials(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = make_response({"statusCode": 100, "body": {}})
        client = switchbot.Client("secret-token", "secret-key", verbose=True)
        with patch("sys.stderr", new_callable=io.StringIO) as err:
            client.command("AA01", "press")
        self.assertIn("POST", err.getvalue())
        self.assertNotIn("secret-token", err.getvalue())
        self.assertNotIn("secret-key", err.getvalue())


class RunTest(unittest.TestCase):
    def run_cli(self, argv: list[str], client: MagicMock) -> str:
        args = switchbot.build_parser().parse_args(argv)
        with patch("switchbot.load_credentials", return_value=("tok", "sec")), \
                patch("switchbot.Client", return_value=client), \
                patch("sys.stdout", new_callable=io.StringIO) as out:
            switchbot.run(args)
        return out.getvalue()

    def test_cmd_by_name(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        out = self.run_cli(["cmd", "light on", "turnOn"], client)
        client.command.assert_called_once_with("AA01", "turnOn", "default", "command")
        self.assertIn("Sent turnOn to Light on (AA01)", out)

    def test_cmd_customize_and_json_param(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        self.run_cli(["cmd", "TV", "Power", '{"a": 1}', "--customize", "--json-param"], client)
        client.command.assert_called_once_with("01-123", "Power", {"a": 1}, "customize")

    def test_scene_by_name(self) -> None:
        client = MagicMock()
        client.scenes.return_value = [{"sceneId": "s1", "sceneName": "Good night"},
                                      {"sceneId": "s2", "sceneName": "Morning"}]
        out = self.run_cli(["scene", "night"], client)
        client.execute_scene.assert_called_once_with("s1")
        self.assertIn("Executed scene Good night (s1)", out)

    def test_devices_table(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        lines = self.run_cli(["devices"], client).splitlines()
        self.assertEqual(lines[0].split(), ["NAME", "TYPE", "ID", "HUB"])
        self.assertEqual(len(lines), 6)

    def test_devices_tsv(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        lines = self.run_cli(["devices", "--tsv"], client).splitlines()
        self.assertEqual(lines[0], "NAME\tTYPE\tID\tHUB")
        self.assertEqual(lines[1], "Light on\tBot\tAA01\tHUB1")
        self.assertEqual(lines[3], "Garage Dehumidifier \tPlug Mini (US)\tAA03\t")

    def test_tsv_flattens_tabs_and_newlines(self) -> None:
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            switchbot.print_rows(["A", "B"], [["x\ty", "line1\nline2"]], "tsv")
        self.assertEqual(out.getvalue(), "A\tB\nx y\tline1 line2\n")

    def test_scenes_csv_quotes(self) -> None:
        client = MagicMock()
        client.scenes.return_value = [{"sceneId": "s1", "sceneName": 'Off, "all"'}]
        out = self.run_cli(["scenes", "-c"], client)
        self.assertEqual(out, 'NAME,TYPE,ID\n"Off, ""all""",scene,s1\n')

    def test_status_csv(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        client.status.return_value = {"power": "on", "temperature": 21.5, "nested": {"a": 1}}
        out = self.run_cli(["status", "light on", "--csv"], client)
        self.assertEqual(out, 'KEY,VALUE\npower,on\ntemperature,21.5\nnested,"{""a"": 1}"\n')

    def test_status_text(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        client.status.return_value = {"power": "on"}
        self.assertEqual(self.run_cli(["status", "light on"], client), "power: on\n")

    def test_commands_text(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        lines = self.run_cli(["commands", "light on"], client).splitlines()
        self.assertEqual(lines[0], "Light on (Bot, AA01)")
        self.assertEqual(lines[2].split(), ["COMMAND", "PARAMETER", "DESCRIPTION"])
        self.assertEqual(lines[5].split()[0], "press")

    def test_commands_csv_sends_notes_to_stderr(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        with patch("sys.stderr", new_callable=io.StringIO) as err:
            out = self.run_cli(["commands", "TV", "--csv"], client)
        self.assertTrue(out.startswith("COMMAND,PARAMETER,DESCRIPTION\nturnOn,default,"))
        self.assertNotIn("customize", out)
        self.assertIn("--customize", err.getvalue())

    def test_commands_json(self) -> None:
        client = MagicMock()
        client.devices.return_value = DEVICES_BODY
        data = json.loads(self.run_cli(["commands", "light off", "-j"], client))
        self.assertEqual(data["deviceId"], "AA02")
        self.assertEqual(data["commands"][2], {"command": "press", "parameter": "default",
                                               "description": "trigger press"})
        self.assertEqual(data["notes"], [])

    def test_format_options_are_exclusive(self) -> None:
        with patch("sys.stderr", new_callable=io.StringIO), self.assertRaises(SystemExit):
            switchbot.build_parser().parse_args(["devices", "--csv", "--tsv"])

    def test_config_short_option(self) -> None:
        args = switchbot.build_parser().parse_args(["-C", "/x.toml", "devices", "-c"])
        self.assertEqual((args.config, args.format), ("/x.toml", "csv"))


if __name__ == "__main__":
    unittest.main()
