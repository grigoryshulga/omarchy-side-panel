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
  readonly property string layoutMode: {
    var value = String(setting("layoutMode", "overlay")).toLowerCase()
    return ["overlay", "reserve"].indexOf(value) >= 0 ? value : "overlay"
  }
  readonly property bool opened: drawer.opened
  property bool popoutSwitchClosing: false

  function open() { drawer.open() }
  function close() { drawer.close() }
  function togglePanel() { drawer.toggle() }
  function summonFromIpc() {
    if (bar && bar.shell && typeof bar.shell.summon === "function") bar.shell.summon(moduleName)
    else open()
  }
  function hideFromIpc() {
    if (bar && bar.shell && typeof bar.shell.hide === "function") bar.shell.hide(moduleName)
    else close()
  }
  function toggleFromIpc() {
    if (bar && bar.shell && typeof bar.shell.toggle === "function") bar.shell.toggle(moduleName)
    else togglePanel()
  }
  function closeForPopoutSwitch() {
    if (drawer.pinned) return
    popoutSwitchClosing = true
    drawer.close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Drawer {
    id: drawer
    bar: root.bar
    anchorItem: root
    settings: root.settings
    edge: root.edge
    layoutMode: root.layoutMode
    popoutOwner: root
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.summonFromIpc() }
    function close(): void { root.hideFromIpc() }
    function show(): void { root.summonFromIpc() }
    function hide(): void { root.hideFromIpc() }
    function toggle(): void { root.toggleFromIpc() }
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
