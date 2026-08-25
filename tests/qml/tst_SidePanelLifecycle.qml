import QtQuick
import QtTest
import "../.." as Project

TestCase {
  name: "SidePanelLifecycle"

  property var sidePanel: null
  readonly property var fixturePage: ({
    title: "Plugins",
    items: [{ id: "fixture", label: "Fixture", icon: "" }]
  })
  readonly property var secondFixturePage: ({
    title: "Second",
    items: [{ id: "fixture-two", label: "Second fixture", icon: "" }]
  })

  Component {
    id: sidePanelComponent
    Project.SidePanel {}
  }

  function init() {
    sidePanel = sidePanelComponent.createObject(this)
    verify(sidePanel !== null)
    sidePanel.sidePanelState = { version: 1, pages: [fixturePage, secondFixturePage], currentPage: 0 }
    sidePanel.settings = { edge: "left", layoutMode: "overlay", pages: [fixturePage, secondFixturePage] }
    sidePanel.adaptedUrls = ({
      fixture: Qt.resolvedUrl("FixtureSidePanelPage.qml").toString(),
      "fixture-two": Qt.resolvedUrl("FixtureSidePanelPage.qml").toString()
    })
    sidePanel.open()
    tryVerify(function() { return sidePanel.activePanels.length === 1 }, 1000)
  }

  function cleanup() {
    if (!sidePanel) return
    sidePanel.close()
    sidePanel.destroy()
    sidePanel = null
  }

  function test_settings_change_reactivates_embedded_panels() {
    var epoch = sidePanel.panelEpoch
    sidePanel.settings = { edge: "right", layoutMode: "overlay", pages: [fixturePage] }

    tryVerify(function() { return sidePanel.panelEpoch === epoch + 1 }, 1000)
    tryVerify(function() { return sidePanel.activePanels.length === 1 }, 1000)
    verify(sidePanel.activePanels[0].activated)
  }

  function test_edit_mode_does_not_close_sidePanel_when_embedded_panel_deactivates() {
    sidePanel.setEditing(true)

    wait(1)
    verify(sidePanel.opened)
  }

  function test_page_change_does_not_close_sidePanel_when_embedded_panel_deactivates() {
    var firstPanel = sidePanel.activePanels[0]
    sidePanel.selectPage(1)

    wait(1)
    verify(sidePanel.opened)
    compare(sidePanel.currentPage, 1)
    tryVerify(function() { return sidePanel.activePanels.length === 2 }, 1000)
    verify(sidePanel.activePanels.indexOf(firstPanel) >= 0)
    verify(sidePanel.pageIsLoaded(0))
    verify(sidePanel.pageIsLoaded(1))
  }

  function test_background_warmup_loads_all_pages() {
    tryVerify(function() { return sidePanel.pageIsLoaded(0) }, 1000)
    tryVerify(function() { return sidePanel.pageIsLoaded(1) }, 1000)
    tryVerify(function() { return sidePanel.activePanels.length === 2 }, 1000)
  }

  function test_edge_reveal_settings_are_bounded() {
    sidePanel.settings = {
      edge: "left",
      layoutMode: "overlay",
      edgeRevealEnabled: false,
      edgeRevealDelayMs: 3000,
      pages: [fixturePage]
    }

    compare(sidePanel.edgeRevealConfigured, false)
    compare(sidePanel.edgeRevealDelayMs, 2000)

    sidePanel.settings = {
      edge: "left",
      layoutMode: "overlay",
      edgeRevealEnabled: true,
      edgeRevealDelayMs: -1,
      pages: [fixturePage]
    }

    compare(sidePanel.edgeRevealConfigured, true)
    compare(sidePanel.edgeRevealDelayMs, 0)
  }

  function test_edge_reveal_controls_are_available_in_side_panel_settings() {
    verify(findChild(sidePanel, "edgeRevealEnabledControl") !== null)
    verify(findChild(sidePanel, "edgeRevealDelayControl") !== null)
  }

  function test_panel_resize_controls_are_scoped_to_settings_and_display_mode() {
    var primaryHandle = findChild(sidePanel, "sidePanelResizeHandle")
    var crossHandle = findChild(sidePanel, "sidePanelCrossResizeHandle")
    verify(findChild(sidePanel, "resizePanelButton") !== null)
    verify(primaryHandle !== null)
    verify(crossHandle !== null)
    verify(!primaryHandle.visible)
    verify(!crossHandle.visible)

    sidePanel.settingsOpen = true
    sidePanel.panelResizeMode = true
    verify(primaryHandle.visible)
    verify(crossHandle.visible)

    sidePanel.layoutMode = "reserve"
    verify(primaryHandle.visible)
    verify(!crossHandle.visible)

    sidePanel.settingsOpen = false
    verify(!sidePanel.panelResizeMode)
    verify(!primaryHandle.visible)
  }

  function test_overlay_alignment_is_limited_to_the_current_edge_orientation() {
    sidePanel.edge = "left"
    sidePanel.settings = { edge: "left", layoutMode: "overlay", overlayAlignment: "right", pages: [fixturePage] }
    compare(sidePanel.overlayAlignment, "center")

    sidePanel.settings = { edge: "left", layoutMode: "overlay", overlayAlignment: "top", pages: [fixturePage] }
    compare(sidePanel.overlayAlignment, "top")

    sidePanel.edge = "top"
    sidePanel.settings = { edge: "top", layoutMode: "overlay", overlayAlignment: "bottom", pages: [fixturePage] }
    compare(sidePanel.overlayAlignment, "center")

    sidePanel.settings = { edge: "top", layoutMode: "overlay", overlayAlignment: "left", pages: [fixturePage] }
    compare(sidePanel.overlayAlignment, "left")
  }

  function test_cross_axis_resize_does_not_change_the_edge_axis_preview() {
    sidePanel.layoutMode = "overlay"
    var edgeExtent = sidePanel.sidePanelExtent
    sidePanel.sidePanelResizeAxis = "cross"
    sidePanel.sidePanelResizePreview = 300
    sidePanel.resizingSidePanel = true

    compare(sidePanel.sidePanelExtent, edgeExtent)
    compare(sidePanel.overlayCrossExtent, 300)

    sidePanel.cancelSidePanelResize()
  }

  function test_shortcuts_page_is_available_and_escape_closes_it() {
    verify(findChild(sidePanel, "shortcutsButton") !== null)
    verify(findChild(sidePanel, "shortcutsPage") !== null)

    sidePanel.shortcutsOpen = true
    verify(sidePanel.shortcutsOpen)
    sidePanel.handleEscape()
    verify(!sidePanel.shortcutsOpen)
    verify(sidePanel.opened)
  }

  function test_reveal_animation_starts_outside_the_configured_edge() {
    sidePanel.panelRevealProgress = 0
    wait(180)

    sidePanel.edge = "left"
    verify(sidePanel.panelRevealOffsetX < 0)
    compare(sidePanel.panelRevealOffsetY, 0)

    sidePanel.edge = "right"
    verify(sidePanel.panelRevealOffsetX > 0)

    sidePanel.edge = "top"
    compare(sidePanel.panelRevealOffsetX, 0)
    verify(sidePanel.panelRevealOffsetY < 0)

    sidePanel.edge = "bottom"
    verify(sidePanel.panelRevealOffsetY > 0)

    sidePanel.panelRevealProgress = 1
    wait(180)
    compare(sidePanel.panelRevealOffsetX, 0)
    compare(sidePanel.panelRevealOffsetY, 0)
  }

  function test_horizontal_edges_use_vertical_page_dots() {
    var horizontalDots = findChild(sidePanel, "pageDotsHorizontal")
    var verticalDots = findChild(sidePanel, "pageDotsVertical")
    verify(horizontalDots !== null)
    verify(verticalDots !== null)

    sidePanel.edge = "left"
    verify(horizontalDots.visible)
    verify(!verticalDots.visible)

    sidePanel.edge = "top"
    verify(!horizontalDots.visible)
    verify(verticalDots.visible)
  }

  function test_alt_wheel_moves_between_pages() {
    sidePanel.currentPage = 0
    sidePanel.handlePanelWheel(Qt.AltModifier, 120, 0)
    compare(sidePanel.currentPage, 1)

    sidePanel.handlePanelWheel(Qt.AltModifier, -120, 0)
    compare(sidePanel.currentPage, 0)

    sidePanel.handlePanelWheel(Qt.AltModifier, 0, 120)
    compare(sidePanel.currentPage, 1)

    sidePanel.handlePanelWheel(Qt.AltModifier, 0, -120)
    compare(sidePanel.currentPage, 0)
  }

  function test_edit_keyboard_commands_focus_resize_and_reorder_a_plugin() {
    sidePanel.sidePanelPages = [{
      title: "Plugins",
      items: [fixturePage.items[0], secondFixturePage.items[0]]
    }]
    sidePanel.currentPage = 0
    sidePanel.setEditing(true)
    compare(sidePanel.keyboardPluginIndex, 0)
    compare(sidePanel.expandedId, "fixture")

    sidePanel.focusEditPlugin(1)
    compare(sidePanel.keyboardPluginIndex, 1)
    compare(sidePanel.expandedId, "fixture-two")

    sidePanel.toggleFocusedPlugin()
    compare(sidePanel.expandedId, "")
    sidePanel.toggleFocusedPlugin()
    compare(sidePanel.expandedId, "fixture-two")

    var initialHeight = sidePanel.panelHeight(sidePanel.focusedPlugin())
    sidePanel.resizeFocusedPlugin(1)
    verify(sidePanel.panelHeight(sidePanel.focusedPlugin()) > initialHeight)

    var initialWidth = sidePanel.panelWidth(sidePanel.focusedPlugin())
    sidePanel.resizeFocusedPlugin(1, "width")
    verify(sidePanel.panelWidth(sidePanel.focusedPlugin()) > initialWidth)

    sidePanel.moveFocusedPlugin(-1)
    compare(sidePanel.keyboardPluginIndex, 0)
    compare(sidePanel.pluginItems[0].id, "fixture-two")

    sidePanel.removeFocusedPlugin()
    compare(sidePanel.pluginItems.length, 1)
    compare(sidePanel.keyboardPluginIndex, 0)
    compare(sidePanel.pluginItems[0].id, "fixture")
  }

  function test_escape_keeps_a_pinned_side_panel_open() {
    sidePanel.pinned = true
    sidePanel.opened = true

    sidePanel.handleEscape()

    verify(sidePanel.opened)
  }

  function test_focus_change_closes_an_unpinned_side_panel() {
    var openedWindow = ({ name: "opened-window" })
    var nextWindow = ({ name: "next-window" })
    sidePanel.opened = true
    sidePanel.pinned = false
    sidePanel.openedToplevel = openedWindow
    sidePanel.focusDismissalArmed = true

    verify(sidePanel.shouldDismissForToplevelChange(nextWindow))
    sidePanel.handleActiveToplevelChange(nextWindow)

    verify(!sidePanel.opened)
  }

  function test_focus_change_keeps_a_pinned_side_panel_open() {
    sidePanel.opened = true
    sidePanel.pinned = true
    sidePanel.openedToplevel = ({ name: "opened-window" })
    sidePanel.focusDismissalArmed = true

    sidePanel.handleActiveToplevelChange({ name: "next-window" })

    verify(sidePanel.opened)
  }

  function test_outside_click_capture_is_only_needed_for_unpinned_reserve_mode() {
    sidePanel.settings = { edge: "left", layoutMode: "reserve", pages: [fixturePage] }
    sidePanel.opened = true
    sidePanel.pinned = false

    verify(sidePanel.outsideClickCaptureEnabled())
    verify(findChild(sidePanel, "outsideClickCapture") !== null)

    sidePanel.pinned = true
    verify(!sidePanel.outsideClickCaptureEnabled())
  }

  function test_outside_click_keeps_a_pinned_side_panel_open() {
    sidePanel.opened = true
    sidePanel.pinned = true

    sidePanel.handleOutsideClick()

    verify(sidePanel.opened)
  }
}
