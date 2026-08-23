import QtQuick
import QtTest
import "../../DrawerModel.js" as DrawerModel

TestCase {
  name: "DrawerModel"

  function resolve(item) { return item.id === "alias" ? "resolved" : item.id }

  function test_normalize_deduplicates_and_canonicalizes_height() {
    var items = DrawerModel.normalize([
      { id: "alias", height: 13.5 },
      { id: "resolved", height: -4 },
      { id: "gshulga.drawer" },
      { id: "", height: 100 }
    ], resolve)
    compare(items.length, 1)
    compare(items[0].id, "resolved")
    compare(items[0].height, 13.5)
    compare(items[0].embedding, "")
  }

  function test_legacy_pages_are_flattened_only_when_plugins_are_absent() {
    var legacy = DrawerModel.itemsFromSettings({ pages: [{ items: [{ id: "one" }] }] }, [], resolve)
    compare(legacy.length, 1)
    compare(legacy[0].id, "one")

    var explicit = DrawerModel.itemsFromSettings({ plugins: [], pages: [{ items: [{ id: "one" }] }] }, [], resolve)
    compare(explicit.length, 0)
  }

  function test_move_and_resize_are_immutable() {
    var source = [{ id: "one", height: 0 }, { id: "two", height: 0 }, { id: "three", height: 0 }]
    var moved = DrawerModel.move(source, "one", "three", true)
    compare(moved.map(function(item) { return item.id }).join(","), "two,three,one")
    compare(source[0].id, "one")
    compare(DrawerModel.resizeHeight(200, 10, -1000, 160, 520, 5), 160)
    compare(DrawerModel.resizeHeight(200, 10, 333, 160, 520, 5), 520)
  }
}
