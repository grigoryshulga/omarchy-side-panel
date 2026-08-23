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

  function test_pages_preserve_names_and_migrate_the_legacy_plugin_list() {
    var legacy = DrawerModel.pagesFromSettings({ plugins: [{ id: "one" }] }, [], resolve)
    compare(legacy.length, 1)
    compare(legacy[0].title, "Plugins")
    compare(legacy[0].items[0].id, "one")

    var pages = DrawerModel.pagesFromSettings({ pages: [{ title: "Work", items: [{ id: "one" }] }, { items: [{ id: "one" }] }] }, [], resolve)
    compare(pages.length, 2)
    compare(pages[0].title, "Work")
    compare(pages[1].title, "Page 2")
    compare(pages[1].items.length, 0)
  }

  function test_move_and_resize_are_immutable() {
    var source = [{ id: "one", height: 0 }, { id: "two", height: 0 }, { id: "three", height: 0 }]
    var moved = DrawerModel.move(source, "one", "three", true)
    compare(moved.map(function(item) { return item.id }).join(","), "two,three,one")
    compare(source[0].id, "one")
    compare(DrawerModel.resizeHeight(200, 10, -1000, 160, 520, 5), 160)
    compare(DrawerModel.resizeHeight(200, 10, 333, 160, 520, 5), 520)
  }

  function test_persisted_entry_uses_only_named_pages() {
    var entry = DrawerModel.persistedEntry(
      { id: "gshulga.drawer", plugins: [{ id: "old" }], pages: [{ title: "Old" }], edge: "left" },
      [{ title: "Main", items: [{ id: "one" }] }]
    )
    compare(entry.edge, "left")
    verify(entry.plugins === undefined)
    compare(entry.pages.length, 1)
    compare(entry.pages[0].title, "Main")
    compare(entry.pages[0].items[0].id, "one")
  }
}
