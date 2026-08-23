pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "gshulga.drawer"

  readonly property string icon: "\ueab6"
  readonly property string edge: {
    var value = String(setting("edge", "left")).toLowerCase()
    return ["left", "right", "top", "bottom"].indexOf(value) >= 0 ? value : "left"
  }
  readonly property bool opened: drawer.opened
  property bool popoutSwitchClosing: false

  function open() { drawer.open() }
  function close() { drawer.close() }
  function togglePanel() { drawer.toggle() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    drawer.close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Drawer {
    id: drawer
    bar: root.bar
    settings: root.settings
    edge: root.edge
    popoutOwner: root
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.opened ? "Close drawer" : "Open drawer"
    active: root.opened
    onPressed: function() { root.togglePanel() }
  }
}
