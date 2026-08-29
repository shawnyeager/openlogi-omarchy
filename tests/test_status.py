#!/usr/bin/env python3
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PLUGIN_STATUS = REPO / "status.py"
SYNC_MODULE = REPO / "lib" / "openlogi_sync.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


status = load_module(PLUGIN_STATUS, "openlogi_status")
sync = load_module(SYNC_MODULE, "openlogi_sync")


class ParseListOutputTests(unittest.TestCase):
    def test_sample_devices(self):
        raw = (REPO / "tests/fixtures/openlogi-list-sample.txt").read_text()
        receivers, devices, cameras = status.parse_list_output(raw)
        self.assertEqual(len(receivers), 1)
        self.assertEqual(len(devices), 2)
        self.assertEqual(len(cameras), 1)
        self.assertEqual(devices[0]["name"], "MX Master 3S")
        self.assertTrue(devices[0]["online"])
        self.assertEqual(devices[0]["battery"]["percent"], 72)
        self.assertFalse(devices[1]["online"])
        self.assertIsNone(devices[1]["battery"])
        self.assertEqual(cameras[0]["kind"], "camera")

    def test_empty_list(self):
        raw = (REPO / "tests/fixtures/openlogi-list-empty.txt").read_text()
        receivers, devices, cameras = status.parse_list_output(raw)
        self.assertEqual(receivers, [])
        self.assertEqual(devices, [])
        self.assertEqual(cameras, [])


class PrimaryDeviceTests(unittest.TestCase):
    def test_prefers_online_mouse(self):
        raw = (REPO / "tests/fixtures/openlogi-list-sample.txt").read_text()
        _, devices, cameras = status.parse_list_output(raw)
        primary = status.primary_device(devices, cameras)
        self.assertEqual(primary["name"], "MX Master 3S")

    def test_low_battery(self):
        raw = (REPO / "tests/fixtures/openlogi-list-sample.txt").read_text()
        _, devices, cameras = status.parse_list_output(raw)
        devices[0]["battery"]["percent"] = 15
        self.assertTrue(status.has_low_battery(devices, cameras))


class SyncConfigTests(unittest.TestCase):
    def test_set_app_setting_updates_existing(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config.toml"
            config.write_text(
                "schema_version = 4\n\n[app_settings]\nlaunch_at_login = false\n",
                encoding="utf-8",
            )
            original = sync.OPENLOGI_CONFIG
            sync.OPENLOGI_CONFIG = config
            try:
                sync.set_app_setting(config, "launch_at_login", True)
                sync.set_app_setting(config, "appearance", "dark")
                text = config.read_text(encoding="utf-8")
                self.assertIn("launch_at_login = true", text)
                self.assertIn('appearance = dark', text)
            finally:
                sync.OPENLOGI_CONFIG = original

    def test_read_omarchy_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            colors = Path(tmp) / "colors.toml"
            colors.write_text('mode = "dark"\naccent = "#faa968"\n', encoding="utf-8")
            original = sync.OMARCHY_THEME_COLORS
            sync.OMARCHY_THEME_COLORS = colors
            try:
                self.assertEqual(sync.read_omarchy_mode(), "dark")
            finally:
                sync.OMARCHY_THEME_COLORS = original


class ModelJsonFixtureTests(unittest.TestCase):
    """Sanity-check JSON shape expected by Model.js."""

    def test_status_json_shape(self):
        raw = (REPO / "tests/fixtures/openlogi-list-sample.txt").read_text()
        receivers, devices, cameras = status.parse_list_output(raw)
        payload = {
            "ok": True,
            "installed": True,
            "devices": devices,
            "cameras": cameras,
            "receivers": receivers,
        }
        encoded = json.dumps(payload)
        parsed = json.loads(encoded)
        self.assertIsInstance(parsed["devices"], list)
        self.assertIn("name", parsed["devices"][0])


if __name__ == "__main__":
    unittest.main()
