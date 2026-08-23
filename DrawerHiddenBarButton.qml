import QtQuick

// Adapted panels keep their original bar-button declarations for their local
// behavior, but must not register a second live button with the Omarchy bar.
Item {
  property var bar: null
  property string text: ""
  property string tooltipText: ""
  property bool active: false
  property int slotSize: 0
  property var iconComponent: null
  signal pressed(var button)
  signal wheelMoved(var delta)
  visible: false
}
