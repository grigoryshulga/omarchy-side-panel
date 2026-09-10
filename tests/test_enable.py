"""Enable a plugin for Side Panel without placing it on the bar."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
ENABLE = PROJECT_DIR / "bin" / "omarchy-side-panel-enable"


class EnableTests(unittest.TestCase):
    def run_enable(self, path: Path, plugin_id: str, first_party: str = "false") -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            ["/usr/bin/python3", "-I", str(ENABLE), str(path), plugin_id, first_party],
            capture_output=True,
            check=False,
            timeout=2,
        )

    def write_config(self, directory: Path, extra: dict | None = None) -> Path:
        config = {
            "version": 1,
            "bar": {"layout": {"left": [{"id": "gshulga.side-panel"}], "center": [], "right": []}},
            "plugins": [{"id": "already"}],
        }
        if extra:
            config.update(extra)
        path = directory / "shell.json"
        path.write_text(json.dumps(config, indent=2) + "\n")
        os.chmod(path, 0o600)
        os.chmod(directory, 0o700)
        return path

    def test_adds_plugin_without_bar_layout_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory), {"disabledPlugins": ["acme.weather"]})
            result = self.run_enable(path, "acme.weather")
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            config = json.loads(path.read_text())
            self.assertEqual(config["plugins"][-1], {"id": "acme.weather"})
            self.assertEqual(config["bar"]["layout"]["left"], [{"id": "gshulga.side-panel"}])
            self.assertNotIn("disabledPlugins", config)

    def test_first_party_only_clears_disabled_plugins(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory), {"disabledPlugins": ["omarchy.clock"]})
            result = self.run_enable(path, "omarchy.clock", "true")
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            config = json.loads(path.read_text())
            self.assertEqual(config["plugins"], [{"id": "already"}])
            self.assertNotIn("disabledPlugins", config)

    def test_rejects_side_panel_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory))
            result = self.run_enable(path, "gshulga.side-panel")
            self.assertEqual(result.returncode, 3)
