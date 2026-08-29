#!/usr/bin/env python3
"""Publish-layout contract: omarchy plugin add and the marketplace require
manifest.json at the repo root, with entry-point files beside it."""
import json
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "manifest.json"


class PluginLayoutTests(unittest.TestCase):
    def test_manifest_lives_at_repo_root(self):
        self.assertTrue(
            MANIFEST.is_file(),
            "omarchy plugin add and omarchyplugins.com require manifest.json at repo root",
        )

    def test_plugin_id_is_openlogi_omarchy(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(data["id"], "openlogi-omarchy")

    def test_entry_points_exist_beside_manifest(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        entry_points = data.get("entryPoints")
        self.assertIsInstance(entry_points, dict)
        self.assertGreater(len(entry_points), 0)
        for key, rel in entry_points.items():
            path = REPO / rel
            self.assertTrue(path.is_file(), f"entryPoints.{key} missing: {rel}")

    def test_panel_does_not_hardcode_old_plugin_path(self):
        panel = REPO / "Panel.qml"
        self.assertTrue(panel.is_file(), "Panel.qml must live at repo root")
        text = panel.read_text(encoding="utf-8")
        self.assertNotIn("plugins/openlogi.bar", text)
        self.assertNotIn('moduleName: "openlogi.bar"', text)
        self.assertNotIn('ipcTarget: "openlogi.bar"', text)


if __name__ == "__main__":
    unittest.main()
