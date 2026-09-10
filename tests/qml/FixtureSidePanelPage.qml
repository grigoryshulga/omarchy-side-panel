import QtQuick

Item {
  id: root

  property var sidePanel: null
  property var sidePanelHost: null
  property bool activated: false

  function open() { activated = true }
  function close() { activated = false }
}
