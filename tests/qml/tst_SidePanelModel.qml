import QtQuick
import QtTest
import "../../SidePanelModel.js" as SidePanelModel

TestCase {
  name: "SidePanelModel"

  function resolve(item) { return item.id === "alias" ? "resolved" : item.id }

  function test_normalize_deduplicates_and_canonicalizes_dimensions() {
    var items = SidePanelModel.normalize([
      { id: "alias", height: 13.5, width: 315 },
      { id: "resolved", height: -4, width: -4 },
      { id: "gshulga.side-panel" },
      { id: "", height: 100 }
    ], resolve)
    compare(items.length, 1)
    compare(items[0].id, "resolved")
    compare(items[0].height, 13.5)
    compare(items[0].width, 315)
    compare(items[0].embedding, "")
  }

  function test_pages_preserve_names_and_migrate_the_legacy_plugin_list() {
    var legacy = SidePanelModel.pagesFromSettings({ plugins: [{ id: "one" }] }, [], resolve)
    compare(legacy.length, 1)
    compare(legacy[0].title, "Plugins")
    compare(legacy[0].items[0].id, "one")

    var pages = SidePanelModel.pagesFromSettings({ pages: [{ title: "Work", items: [{ id: "one" }] }, { items: [{ id: "one" }] }] }, [], resolve)
    compare(pages.length, 2)
    compare(pages[0].title, "Work")
    compare(pages[1].title, "Page 2")
    compare(pages[1].items.length, 0)
  }

  function test_parse_state_rejects_large_input_and_bounds_models() {
    var oversized = "{\"version\":1,\"pages\":[]}" + new Array(SidePanelModel.MAX_STATE_BYTES + 1).join(" ")
    verify(SidePanelModel.parseState(oversized, [], resolve) === null)

    var pages = []
    for (var pageIndex = 0; pageIndex < SidePanelModel.MAX_PAGES + 2; pageIndex++) {
      var items = []
      for (var itemIndex = 0; itemIndex < SidePanelModel.MAX_ITEMS_PER_PAGE + 2; itemIndex++)
        items.push({
          id: "plugin-" + pageIndex + "-" + itemIndex,
          label: pageIndex === 0 && itemIndex === 0 ? new Array(300).join("x") : "Label",
          icon: pageIndex === 0 && itemIndex === 0 ? new Array(100).join("i") : "i"
        })
      pages.push({ title: new Array(200).join("t"), items: items })
    }

    var state = SidePanelModel.parseState(JSON.stringify({ version: 1, pages: pages }), [], resolve)
    compare(state.pages.length, SidePanelModel.MAX_PAGES)
    compare(state.pages[0].items.length, SidePanelModel.MAX_ITEMS_PER_PAGE)
    compare(state.pages[0].title.length, SidePanelModel.MAX_PAGE_TITLE_LENGTH)
    compare(state.pages[0].items[0].label.length, SidePanelModel.MAX_ITEM_LABEL_LENGTH)
    compare(state.pages[0].items[0].icon.length, SidePanelModel.MAX_ITEM_ICON_LENGTH)
  }

  function test_move_and_resize_are_immutable() {
    var source = [{ id: "one", height: 0, width: 315 }, { id: "two", height: 0 }, { id: "three", height: 0 }]
    var moved = SidePanelModel.move(source, "one", "three", true)
    compare(moved.map(function(item) { return item.id }).join(","), "two,three,one")
    compare(SidePanelModel.move(source, "three", "one", false).map(function(item) { return item.id }).join(","), "three,one,two")
    compare(SidePanelModel.move(source, "two", "three", false).map(function(item) { return item.id }).join(","), "one,two,three")
    compare(source[0].id, "one")
    compare(moved[2].width, 315)
    compare(SidePanelModel.resizeHeight(200, 10, -1000, 5, 5), 5)
    compare(SidePanelModel.resizeHeight(200, 10, 333, 5, 5), 525)
  }

  function test_persisted_entry_uses_only_named_pages() {
    var entry = SidePanelModel.persistedEntry(
      { id: "gshulga.side-panel", plugins: [{ id: "old" }], pages: [{ title: "Old" }], edge: "left", transparentBackground: true },
      [{ title: "Main", items: [{ id: "one" }] }]
    )
    compare(entry.edge, "left")
    verify(entry.plugins === undefined)
    verify(entry.transparentBackground === undefined)
    compare(entry.pages.length, 1)
    compare(entry.pages[0].title, "Main")
    compare(entry.pages[0].items[0].id, "one")
  }
}
