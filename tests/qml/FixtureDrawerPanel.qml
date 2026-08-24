import QtQuick

Item {
  property var drawer: null
  property bool activated: false

  function open() { activated = true }
  function close() { activated = false }
}
