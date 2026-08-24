import QtQuick
import QtTest
import "../.." as Project

TestCase {
  name: "DrawerLifecycle"

  property var drawer: null
  readonly property var fixturePage: ({
    title: "Plugins",
    items: [{ id: "fixture", label: "Fixture", icon: "" }]
  })
  readonly property var secondFixturePage: ({
    title: "Second",
    items: [{ id: "fixture-two", label: "Second fixture", icon: "" }]
  })

  Component {
    id: drawerComponent
    Project.Drawer {}
  }

  function init() {
    drawer = drawerComponent.createObject(this)
    verify(drawer !== null)
    drawer.drawerState = { version: 1, pages: [fixturePage, secondFixturePage], currentPage: 0 }
    drawer.settings = { edge: "left", layoutMode: "overlay", pages: [fixturePage, secondFixturePage] }
    drawer.adaptedUrls = ({
      fixture: Qt.resolvedUrl("FixtureDrawerPanel.qml").toString(),
      "fixture-two": Qt.resolvedUrl("FixtureDrawerPanel.qml").toString()
    })
    drawer.open()
    tryVerify(function() { return drawer.activePanels.length === 1 }, 1000)
  }

  function cleanup() {
    if (!drawer) return
    drawer.close()
    drawer.destroy()
    drawer = null
  }

  function test_settings_change_reactivates_embedded_panels() {
    var epoch = drawer.panelEpoch
    drawer.settings = { edge: "right", layoutMode: "overlay", pages: [fixturePage] }

    tryVerify(function() { return drawer.panelEpoch === epoch + 1 }, 1000)
    tryVerify(function() { return drawer.activePanels.length === 1 }, 1000)
    verify(drawer.activePanels[0].activated)
  }

  function test_edit_mode_does_not_close_drawer_when_embedded_panel_deactivates() {
    drawer.setEditing(true)

    wait(1)
    verify(drawer.opened)
  }

  function test_page_change_does_not_close_drawer_when_embedded_panel_deactivates() {
    drawer.selectPage(1)

    wait(1)
    verify(drawer.opened)
    compare(drawer.currentPage, 1)
    tryVerify(function() { return drawer.activePanels.length === 1 }, 1000)
  }
}
