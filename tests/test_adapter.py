import importlib.util
import os
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest import mock
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

    def test_rejects_an_entry_point_larger_than_one_megabyte_before_adapting(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root, PANEL + " " * (1024 * 1024))

            with self.assertRaisesRegex(adapter.AdaptationError, "entry point exceeds"):
                adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)

    def test_rejects_a_plugin_tree_with_more_than_512_files_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            for index in range(512):
                (source / f"extra-{index}.qml").write_text("Item {}\n")

            with self.assertRaisesRegex(adapter.AdaptationError, "too many files"):
                adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)

    def test_rejects_a_plugin_tree_larger_than_its_byte_budget_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            (source / "asset.bin").write_bytes(b"x" * 64)

            with mock.patch.object(adapter, "MAX_SOURCE_TREE_BYTES", len(PANEL.encode("utf-8"))):
                with self.assertRaisesRegex(adapter.AdaptationError, "tree exceeds"):
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

    def test_repairs_a_corrupted_cached_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            cache = root / "cache"
            output = adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)
            artifact = output.parent
            artifact.chmod(0o700)
            output.chmod(0o600)
            output.write_text("Item {}")
            artifact.chmod(0o500)

            repaired = adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)

            self.assertEqual(repaired, output)
            self.assertIn("SidePanelHost {", repaired.read_text())

    def test_repairs_an_artifact_with_a_non_object_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            cache = root / "cache"
            output = adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)
            marker = output.parent / adapter.MARKER_NAME
            marker.chmod(0o600)
            marker.write_text('["version","fingerprint","entryPoint","artifactDigest"]')

            repaired = adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)

            self.assertEqual(repaired, output)
            self.assertIn("SidePanelHost {", repaired.read_text())

    def test_entry_point_is_part_of_the_artifact_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            (source / "Other.qml").write_text(PANEL.replace("id: root", "id: other"))

            first = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)
            second = adapter.build(source, "Other.qml", root / "cache", "example.plugin", ROOT)

            self.assertNotEqual(first.parent, second.parent)
            self.assertIn("SidePanelHost {", first.read_text())
            self.assertIn("SidePanelHost {", second.read_text())

    def test_file_mode_changes_invalidate_the_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            helper = source / "helper.sh"
            helper.write_text("#!/bin/sh\n")
            helper.chmod(0o644)

            first = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)
            helper.chmod(0o755)
            second = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)

            self.assertNotEqual(first.parent, second.parent)
            self.assertFalse(os.stat(first.parent / "helper.sh").st_mode & 0o111)
            self.assertTrue(os.stat(second.parent / "helper.sh").st_mode & 0o111)

    def test_adapter_helper_changes_invalidate_the_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            adapter_dir = root / "adapter"
            adapter_dir.mkdir()
            for helper in adapter.HELPER_NAMES:
                (adapter_dir / helper).write_bytes((ROOT / helper).read_bytes())

            first = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", adapter_dir)
            host = adapter_dir / "SidePanelHost.qml"
            host.write_text(host.read_text() + "\n// changed\n")
            second = adapter.build(source, "Panel.qml", root / "cache", "example.plugin", adapter_dir)

            self.assertNotEqual(first.parent, second.parent)

    def test_nested_entry_point_uses_its_sibling_panel_and_helpers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            nested = source / "nested"
            nested.mkdir(parents=True)
            (nested / "BarWidget.qml").write_text("import QtQuick\nItem {}\n")
            (nested / "Panel.qml").write_text(PANEL)

            output = adapter.build(source, "nested/BarWidget.qml", root / "cache", "example.plugin", ROOT)

            self.assertEqual(output.name, "Panel.qml")
            self.assertEqual(output.parent.name, "nested")
            for helper in adapter.HELPER_NAMES:
                self.assertTrue((output.parent / helper).is_file())

    def test_rejects_helper_name_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            (source / "SidePanelHost.qml").write_text("Item {}\n")

            with self.assertRaisesRegex(adapter.AdaptationError, "collides"):
                adapter.build(source, "Panel.qml", root / "cache", "example.plugin", ROOT)

    def test_rejects_relative_and_insecure_cache_roots(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            with self.assertRaisesRegex(adapter.AdaptationError, "absolute"):
                adapter.build(source, "Panel.qml", Path("relative-cache"), "example.plugin", ROOT)

            insecure = root / "insecure"
            insecure.mkdir()
            insecure.chmod(0o777)
            with self.assertRaisesRegex(adapter.AdaptationError, "insecure cache ancestor"):
                adapter.build(source, "Panel.qml", insecure / "cache", "example.plugin", ROOT)

    def test_tree_digest_has_unambiguous_file_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first"
            second = root / "second"
            first.mkdir()
            second.mkdir()
            (first / "a").write_bytes(b"F:b\0X")
            (second / "a").write_bytes(b"")
            (second / "b").write_bytes(b"X")

            self.assertNotEqual(adapter.source_tree_digest(first), adapter.source_tree_digest(second))

    def test_concurrent_builds_publish_one_valid_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            cache = root / "cache"

            def build(_: int) -> Path:
                return adapter.build(source, "Panel.qml", cache, "example.plugin", ROOT)

            with ThreadPoolExecutor(max_workers=4) as executor:
                outputs = list(executor.map(build, range(4)))

            self.assertEqual(len(set(outputs)), 1)
            self.assertIn("SidePanelHost {", outputs[0].read_text())

    def test_nested_directories_cannot_bypass_the_global_entry_limit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            first = source / "first"
            second = source / "second"
            first.mkdir()
            second.mkdir()
            (first / "one").write_text("1")
            (first / "two").write_text("2")

            with mock.patch.object(adapter, "MAX_SOURCE_ENTRIES", 4):
                with self.assertRaisesRegex(adapter.AdaptationError, "too many entries"):
                    adapter.source_tree_digest(source)

    def test_rejects_a_source_tree_that_is_too_deeply_nested(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.write_source(root)
            nested = source / "one"
            nested.mkdir()
            (nested / "two").mkdir()

            with mock.patch.object(adapter, "MAX_SOURCE_DEPTH", 1):
                with self.assertRaisesRegex(adapter.AdaptationError, "too deeply nested"):
                    adapter.source_tree_digest(source)

    def test_remove_tree_unlinks_symlinks_instead_of_following_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "outside"
            target.mkdir()
            important = target / "important"
            important.write_text("keep")
            tree = root / "tree"
            tree.mkdir()
            (tree / "link").symlink_to(target, target_is_directory=True)

            adapter.remove_tree(tree)

            self.assertEqual(important.read_text(), "keep")
            self.assertFalse(tree.exists())

    def test_stale_cleanup_does_not_remove_an_active_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            staging_parent = Path(temporary)
            staging = staging_parent / "adapter-active"
            staging.mkdir()
            lock_path = staging / ".active"
            lock_path.touch()
            descriptor = os.open(lock_path, os.O_RDWR)
            adapter.fcntl.flock(descriptor, adapter.fcntl.LOCK_EX)
            old = adapter.time.time() - adapter.STALE_STAGING_SECONDS - 1
            os.utime(staging, (old, old))
            try:
                adapter.clean_stale_staging(staging_parent)
                self.assertTrue(staging.is_dir())
            finally:
                os.close(descriptor)

            adapter.clean_stale_staging(staging_parent)
            self.assertFalse(staging.exists())


if __name__ == "__main__":
    unittest.main()
