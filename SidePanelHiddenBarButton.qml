import QtQuick

// Adapted panels keep their original bar-button declarations for their local
// behavior, but must not register a second live button with the Omarchy bar.
Item {
  property var bar: null
  property string text: ""
  property string fontFamily: ""
  property real fontSize: 0
  property color foreground: "transparent"
  property color activeColor: "transparent"
  property string tooltipText: ""
  property bool active: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: false
  property bool pressable: false
  property bool useActiveColor: true
  property bool maintainIndicatorReveal: false
  property bool labelVisible: true
  property bool hasVisualContent: false
  property var revealHost: null
  property real horizontalMargin: 0
  property real verticalPadding: 0
  property real fixedWidth: 0
  property real fixedHeight: 0
  property real textRotation: 0
  property bool keepSpace: false
  property int slotSize: 0
  property var iconComponent: null
  signal pressed(var button)
  signal wheelMoved(var delta)
  implicitWidth: fixedWidth
  implicitHeight: fixedHeight
  visible: false
}
