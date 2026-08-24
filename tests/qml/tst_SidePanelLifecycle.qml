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
    sidePanel.selectPage(1)

    wait(1)
    verify(sidePanel.opened)
    compare(sidePanel.currentPage, 1)
    tryVerify(function() { return sidePanel.activePanels.length === 1 }, 1000)
  }
}
