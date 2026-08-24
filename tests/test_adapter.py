import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("adapter", ROOT / "lib" / "omarchy_side_panel_adapter.py")
adapter = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = adapter
SPEC.loader.exec_module(adapter)


PANEL = """import QtQuick
Panel {
  id: root
  IpcHandler { function close() { root.close() } }
  BarIconButton { onPressed: root.close() }
  KeyboardPanel { open: root.opened }
}
"""


class AdapterTests(unittest.TestCase):
    def write_source(self, directory: Path, content: str = PANEL) -> Path:
        source = directory / "source"
        source.mkdir()
        (source / "Panel.qml").write_text(content)
        return source

    def test_transforms_only_syntax_tokens_and_preserves_nested_close(self):
        transformed = adapter.transform_qml(PANEL + "// KeyboardPanel { root.controller.hide()\n")
        self.assertIn("property var sidePanelHost: null", transformed)
        self.assertIn("SidePanelDisabledIpc { function close()", transformed)
        self.assertIn("SidePanelHiddenBarButton {", transformed)
        self.assertIn("SidePanelHost {\n    anchors.fill: parent\n    sidePanelHost: root.sidePanelHost", transformed)
        self.assertIn("function sidePanelFocus()", transformed)
        self.assertIn("onFocusTargetChanged: root.sidePanelFocusTarget = focusTarget", transformed)
        self.assertIn("function close() { root.close() }", transformed)
        self.assertIn("// KeyboardPanel { root.controller.hide()", transformed)

    def test_comment_only_host_falls_back_to_sibling_panel(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "BarWidget.qml").write_text("// KeyboardPanel {\nItem {}\n")
            (source / "Panel.qml").write_text(PANEL)
            self.assertEqual(adapter.choose_source(source, "BarWidget.qml").name, "Panel.qml")

    def test_rejects_custom_windows_and_ambiguous_hosts(self):
        with self.assertRaisesRegex(adapter.AdaptationError, "mapped surface"):
            adapter.transform_qml("""Panel {
  id: root
  PanelWindow {}
  KeyboardPanel {}
}
""")
        with self.assertRaisesRegex(adapter.AdaptationError, "exactly one"):
            adapter.transform_qml(PANEL.replace("KeyboardPanel {", "KeyboardPanel {}\n  KeyboardPanel {"))

    def test_build_is_non_destructive_and_uses_immutable_fingerprint(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            cache = root / "cache"
            output = adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)
            self.assertTrue(output.is_file())
            self.assertEqual((source / "Panel.qml").read_text(), PANEL)
            self.assertTrue((output.parent / "SidePanelHost.qml").is_file())
            self.assertIn("property bool dimmed", (output.parent / "SidePanelHiddenBarButton.qml").read_text())
            self.assertEqual(output, adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT))

    def test_build_rebases_relative_imports_outside_the_plugin(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            components = root / "components"
            components.mkdir()
            (source / "Panel.qml").write_text(
                """import QtQuick
import "../components" as Components
Panel {
  id: root
  KeyboardPanel { open: root.opened }
}
"""
            )

            output = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)
            self.assertIn(f'import "{components.as_uri()}" as Components', output.read_text())

    def test_rejects_escape_and_symlinked_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            with self.assertRaisesRegex(adapter.AdaptationError, "outside"):
                adapter.build(source, "../outside.qml", root / "cache", "example.plugin", ROOT)
            (source / "linked.qml").symlink_to(source / "Panel.qml")
            with self.assertRaisesRegex(adapter.AdaptationError, "symlink"):
                adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)

    def test_rejects_cache_overlap_before_creating_staging_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            with self.assertRaisesRegex(adapter.AdaptationError, "overlap"):
                adapter.build(source, "Panel.qml", source / "cache", "example.plugin", ROOT)
            self.assertFalse((source / "cache").exists())

    def test_rejects_symlinked_cache_ancestor_before_reading_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            real_cache = root / "real-cache"
            real_cache.mkdir()
            linked_cache = root / "linked-cache"
            linked_cache.symlink_to(real_cache, target_is_directory=True)
            with self.assertRaisesRegex(adapter.AdaptationError, "symlinked ancestors"):
                adapter.build(source, "Panel.qml", linked_cache, "example.plugin", ROOT)

    def test_rejects_preexisting_destination_without_adapter_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            cache = root / "cache"
            namespace = adapter.hashlib.sha256(b"example.plugin").hexdigest()[:24]
            fingerprint = adapter.hashlib.sha256(
                (adapter.source_tree_digest(source) + "\0" + adapter.ADAPTER_VERSION).encode()
            ).hexdigest()[:24]
            target = cache / namespace / fingerprint
            target.mkdir(parents=True)
            (target / "Panel.qml").write_text("Item {}")
            with self.assertRaisesRegex(adapter.AdaptationError, "not a SidePanel artifact"):
                adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)


if __name__ == "__main__":
    unittest.main()
