import QtQuick

Item {
  id: root

  property var sidePanel: null
  property var sidePanelHost: null
  property bool activated: false

  function open() { activated = true }
  function close() {
    activated = false
    // SidePanelHost reports a native panel closing on the next event-loop turn.
    Qt.callLater(function() { sidePanelHost.panelClosed(root) })
  }
}
