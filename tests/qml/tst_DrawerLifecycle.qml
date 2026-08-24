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

  Component {
    id: drawerComponent
    Project.Drawer {}
  }

  function init() {
    drawer = drawerComponent.createObject(this)
    verify(drawer !== null)
    drawer.drawerState = { version: 1, pages: [fixturePage], currentPage: 0 }
    drawer.settings = { edge: "left", layoutMode: "overlay", pages: [fixturePage] }
    drawer.adaptedUrls = ({ fixture: Qt.resolvedUrl("FixtureDrawerPanel.qml").toString() })
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
}
