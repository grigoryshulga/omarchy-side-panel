import QtQuick

Item {
  id: root

  property var drawer: null
  property var drawerHost: null
  property bool activated: false

  function open() { activated = true }
  function close() {
    activated = false
    // DrawerPanelHost reports a native panel closing on the next event-loop turn.
    Qt.callLater(function() { drawerHost.panelClosed(root) })
  }
}
