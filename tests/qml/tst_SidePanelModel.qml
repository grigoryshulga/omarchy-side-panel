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

  function test_items_track_their_own_background() {
    var items = SidePanelModel.normalize([
      { id: "one" },
      { id: "two", background: false },
      { id: "three", background: true }
    ], resolve)
    compare(items[0].background, true)
    compare(items[1].background, false)
    compare(items[2].background, true)

    var copied = SidePanelModel.copy(items)
    compare(copied[0].background, true)
    compare(copied[1].background, false)

    var entry = SidePanelModel.persistedEntry({}, [{ title: "Main", items: [{ id: "one", background: false }] }])
    compare(entry.pages[0].items[0].background, false)
  }

  function test_normalize_bounds_item_extents() {
    var items = SidePanelModel.normalize([{ id: "one", height: Infinity, width: SidePanelModel.MAX_ITEM_EXTENT + 1 }], resolve)
    compare(items[0].height, 0)
    compare(items[0].width, SidePanelModel.MAX_ITEM_EXTENT)
    compare(SidePanelModel.boundedEdgeSize(Infinity, 480), 480)
    compare(SidePanelModel.boundedEdgeSize(SidePanelModel.MAX_EDGE_SIZE + 1, 480), SidePanelModel.MAX_EDGE_SIZE)
    compare(SidePanelModel.boundedExtent(-1, 260, 900), 260)
    compare(SidePanelModel.boundedExtent(950, 260, 900), 900)
    compare(SidePanelModel.boundedExtent(287.5, 260, 900), 287.5)
    compare(SidePanelModel.boundedExtent(260, 260, 200), 200)
    compare(SidePanelModel.boundedInteger(Infinity, 250, 0, 2000), 250)
    compare(SidePanelModel.boundedInteger(-1, 250, 0, 2000), 0)
    compare(SidePanelModel.boundedInteger(3000, 250, 0, 2000), 2000)
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
    var totalItems = 0
    for (var normalizedPageIndex = 0; normalizedPageIndex < state.pages.length; normalizedPageIndex++)
      totalItems += state.pages[normalizedPageIndex].items.length
    compare(totalItems, SidePanelModel.MAX_TOTAL_ITEMS)
    compare(state.pages[0].title.length, SidePanelModel.MAX_PAGE_TITLE_LENGTH)
    compare(state.pages[0].items[0].label.length, SidePanelModel.MAX_ITEM_LABEL_LENGTH)
    compare(state.pages[0].items[0].icon.length, SidePanelModel.MAX_ITEM_ICON_LENGTH)

    state = SidePanelModel.parseState(JSON.stringify({
      version: 1,
      pages: [{ items: [{ id: "one", height: SidePanelModel.MAX_ITEM_EXTENT + 1, width: SidePanelModel.MAX_ITEM_EXTENT + 1 }] }],
      edgeSize: SidePanelModel.MAX_EDGE_SIZE + 1,
      overlayCrossSize: SidePanelModel.MAX_EDGE_SIZE + 1,
      overlayAlignment: "bottom",
      openTrigger: "none",
      edgeRevealEnabled: false,
      edgeRevealDelayMs: 3000,
      openAnimationEnabled: false,
      revision: SidePanelModel.MAX_REVISION + 1
    }), [], resolve)
    compare(state.pages[0].items[0].height, SidePanelModel.MAX_ITEM_EXTENT)
    compare(state.pages[0].items[0].width, SidePanelModel.MAX_ITEM_EXTENT)
    compare(state.edgeSize, SidePanelModel.MAX_EDGE_SIZE)
    compare(state.overlayCrossSize, SidePanelModel.MAX_EDGE_SIZE)
    compare(state.overlayAlignment, "bottom")
    compare(state.openTrigger, "none")
    compare(state.edgeRevealEnabled, false)
    compare(state.edgeRevealDelayMs, 2000)
    compare(state.openAnimationEnabled, false)
    compare(state.revision, SidePanelModel.MAX_REVISION)

    var fullCrossAxis = SidePanelModel.parseState(JSON.stringify({
      version: 1,
      pages: [],
      overlayCrossSize: 0
    }), [], resolve)
    compare(fullCrossAxis.overlayCrossSize, 0)
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
    compare(SidePanelModel.resizeHeight(200, 10, SidePanelModel.MAX_ITEM_EXTENT * 2, 5, 5), SidePanelModel.MAX_ITEM_EXTENT)
  }

  function test_persisted_entry_uses_only_named_pages() {
    var entry = SidePanelModel.persistedEntry(
      {
        id: "gshulga.side-panel",
        plugins: [{ id: "old" }],
        pages: [{ title: "Old" }],
        edge: "left",
        edgeSize: SidePanelModel.MAX_EDGE_SIZE + 1,
        overlayCrossSize: SidePanelModel.MAX_EDGE_SIZE + 1,
        overlayAlignment: "top",
        transparentBackground: true
      },
      [{ title: "Main", items: [{ id: "one" }] }]
    )
    compare(entry.edge, "left")
    compare(entry.edgeSize, SidePanelModel.MAX_EDGE_SIZE)
    compare(entry.overlayCrossSize, SidePanelModel.MAX_EDGE_SIZE)
    compare(entry.overlayAlignment, "top")
    verify(entry.plugins === undefined)
    verify(entry.transparentBackground === undefined)
    compare(entry.pages.length, 1)
    compare(entry.pages[0].title, "Main")
    compare(entry.pages[0].items[0].id, "one")
  }

  function test_plugin_catalog_uses_public_list_and_manifests() {
    var catalog = SidePanelModel.pluginCatalogFromPublicSources(
      JSON.stringify([
        { id: "omarchy.clock", name: "Clock", enabled: true, firstParty: true, kinds: ["bar-widget"] },
        { id: "gshulga.side-panel", name: "Side Panel", enabled: true },
        { id: "acme.weather", name: "Weather", enabled: false, firstParty: false },
        { id: "acme.weather", name: "Duplicate" }
      ]),
      JSON.stringify([
        {
          id: "acme.weather",
          name: "Weather Panel",
          description: "Forecast",
          firstParty: false,
          sourceDir: "/tmp/acme.weather",
          entryPoints: { barWidget: "Panel.qml" }
        }
      ])
    )
    compare(catalog.length, 2)
    compare(catalog[0].id, "omarchy.clock")
    compare(catalog[0].name, "Clock")
    compare(catalog[0].__isFirstParty, true)
    compare(catalog[1].id, "acme.weather")
    compare(catalog[1].name, "Weather Panel")
    compare(catalog[1].description, "Forecast")
    compare(catalog[1].enabled, false)
    compare(catalog[1].entryPoints.barWidget, "Panel.qml")
    compare(catalog[1].__sourceDir, "/tmp/acme.weather")
    compare(SidePanelModel.pluginCatalogFromPublicSources("{", "[]").length, 0)
  }

  function test_enable_in_config_does_not_place_bar_widgets() {
    var config = {
      version: 1,
      bar: { layout: { left: [{ id: "gshulga.side-panel" }], center: [], right: [] } },
      plugins: [{ id: "already" }],
      disabledPlugins: ["acme.weather"]
    }
    verify(SidePanelModel.enableInConfig(config, "acme.weather", false))
    compare(config.plugins.length, 2)
    compare(config.plugins[1].id, "acme.weather")
    compare(config.bar.layout.left.length, 1)
    compare(config.bar.layout.left[0].id, "gshulga.side-panel")
    verify(config.disabledPlugins === undefined)
    verify(SidePanelModel.enableInConfig(config, "acme.weather", false))
    compare(config.plugins.length, 2)
    verify(SidePanelModel.enableInConfig(config, "omarchy.clock", true))
    compare(config.plugins.length, 2)
    verify(!SidePanelModel.enableInConfig(config, "gshulga.side-panel", false))
  }

  function test_parse_shell_config_rejects_non_objects_and_oversized_input() {
    var config = SidePanelModel.parseShellConfig("{\"version\":1,\"plugins\":[]}")
    compare(config.version, 1)
    verify(SidePanelModel.parseShellConfig("[]") === null)
    verify(SidePanelModel.parseShellConfig("not json") === null)
    verify(SidePanelModel.parseShellConfig("") === null)
    var oversized = "{\"pad\":\"" + new Array(SidePanelModel.MAX_CONFIG_BYTES + 1).join(" ") + "\"}"
    verify(SidePanelModel.parseShellConfig(oversized) === null)
  }

  function test_plugin_enabled_in_config_matches_shell_loadability() {
    var widget = { kinds: ["bar-widget"], __isFirstParty: false }
    // A widget enabled through plugins[] loads even though the public plugin
    // list reports enabled:false for it (it is not placed on the bar).
    verify(SidePanelModel.pluginEnabledInConfig({ plugins: [{ id: "acme.weather" }] }, widget, "acme.weather"))
    // A widget placed on the bar is enabled too.
    verify(SidePanelModel.pluginEnabledInConfig(
      { bar: { layout: { left: [], center: [], right: [{ id: "acme.weather" }] } } }, widget, "acme.weather"))
    // Unreferenced widgets stay disabled.
    verify(!SidePanelModel.pluginEnabledInConfig({ plugins: [] }, widget, "acme.weather"))
  }

  function test_plugin_enabled_in_config_honours_first_party_and_disabled() {
    var firstParty = { kinds: ["panel"], __isFirstParty: true }
    var disabled = { kinds: ["panel"], __isFirstParty: true }
    verify(SidePanelModel.pluginEnabledInConfig({}, firstParty, "omarchy.osd"))
    verify(!SidePanelModel.pluginEnabledInConfig({ disabledPlugins: ["omarchy.osd"] }, disabled, "omarchy.osd"))

    var panel = { kinds: ["panel"], __isFirstParty: false }
    verify(SidePanelModel.pluginEnabledInConfig({ plugins: [{ id: "acme.panel" }] }, panel, "acme.panel"))
  }

  function test_plugin_enabled_in_config_resolves_bar_option() {
    var bar = { kinds: ["bar"], __isFirstParty: true }
    verify(SidePanelModel.pluginEnabledInConfig({}, bar, "omarchy.bar"))
    verify(!SidePanelModel.pluginEnabledInConfig({}, bar, "acme.bar"))
    verify(SidePanelModel.pluginEnabledInConfig({ bar: { id: "acme.bar" } }, bar, "acme.bar"))
  }

  function test_persisted_entry_allowlists_and_bounds_settings() {
    var settings = {
      edge: "outside",
      layoutMode: "overlay",
      overlayAlignment: "center",
      openTrigger: "hover",
      edgeRevealEnabled: true,
      edgeRevealDelayMs: 9000,
      openAnimationEnabled: false,
      sidePanelRevision: SidePanelModel.MAX_REVISION + 1,
      unknown: "must not be persisted"
    }
    settings.circular = settings

    var entry = SidePanelModel.persistedEntry(settings, [{ title: "Main", items: [] }])

    verify(entry.edge === undefined)
    compare(entry.layoutMode, "overlay")
    compare(entry.overlayAlignment, "center")
    compare(entry.openTrigger, "hover")
    compare(entry.edgeRevealEnabled, true)
    compare(entry.edgeRevealDelayMs, 2000)
    compare(entry.openAnimationEnabled, false)
    compare(entry.sidePanelRevision, SidePanelModel.MAX_REVISION)
    verify(entry.unknown === undefined)
    verify(entry.circular === undefined)
    verify(JSON.stringify(entry).length > 0)
  }
}
