import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property Item body
  property bool enabled: false
  property bool reservesSpace: false
  property bool verticalEdge: true
  property string edge: "left"
  property string overlayAlignment: "center"
  property color foreground: Color.popups.text
  property bool resizing: false
  property string resizeAxis: "edge"

  signal resizeStarted(string axis, real position)
  signal resizeUpdated(real position)
  signal resizeFinished()
  signal resizeCanceled()

  // This Item is a sibling of the Side Panel body. Its own stacking level,
  // rather than the levels of its children, must place both resize handles
  // above the body.
  z: 12

  function pointerPosition(handle, mouse) {
    var point = handle.mapToGlobal(mouse.x, mouse.y)
    return root.verticalEdge ? point.x : point.y
  }

  Rectangle {
    id: edgeHandle
    objectName: "sidePanelResizeHandle"
    visible: root.enabled
    width: Math.round(root.verticalEdge ? Style.space(12) : Style.space(48))
    height: Math.round(root.verticalEdge ? Style.space(48) : Style.space(12))
    x: root.verticalEdge
      ? (root.edge === "left" ? root.body.x + root.body.width - width : root.body.x)
      : root.body.x + (root.body.width - width) / 2
    y: root.verticalEdge
      ? root.body.y + (root.body.height - height) / 2
      : (root.edge === "top" ? root.body.y + root.body.height - height : root.body.y)
    radius: Math.min(width, height) / 2
    color: edgeMouse.containsMouse || (root.resizing && root.resizeAxis === "edge")
      ? Style.hoverFillFor(root.foreground, Color.accent)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    z: 12

    Item {
      anchors.centerIn: parent
      width: root.verticalEdge ? Math.round(Style.space(5)) : Math.round(Style.space(20))
      height: root.verticalEdge ? Math.round(Style.space(20)) : Math.round(Style.space(5))
      Row {
        visible: root.verticalEdge
        anchors.centerIn: parent
        spacing: 1
        Repeater { model: 3; delegate: Rectangle { width: 1; height: Math.round(Style.space(14)); radius: width / 2; color: root.foreground; opacity: 0.52 } }
      }
      Column {
        visible: !root.verticalEdge
        anchors.centerIn: parent
        spacing: 1
        Repeater { model: 3; delegate: Rectangle { width: Math.round(Style.space(14)); height: 1; radius: height / 2; color: root.foreground; opacity: 0.52 } }
      }
    }

    MouseArea {
      id: edgeMouse
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: root.verticalEdge ? Qt.SizeHorCursor : Qt.SizeVerCursor
      onPressed: function(mouse) { root.resizeStarted("edge", root.pointerPosition(edgeHandle, mouse)) }
      onPositionChanged: function(mouse) { root.resizeUpdated(root.pointerPosition(edgeHandle, mouse)) }
      onReleased: root.resizeFinished()
      onCanceled: root.resizeCanceled()
    }
  }

  Rectangle {
    id: crossHandle
    objectName: "sidePanelCrossResizeHandle"
    visible: root.enabled && !root.reservesSpace
    width: root.verticalEdge ? Style.space(48) : Style.space(12)
    height: root.verticalEdge ? Style.space(12) : Style.space(48)
    x: root.verticalEdge
      ? root.body.x + (root.body.width - width) / 2
      : (root.overlayAlignment === "right" ? root.body.x : root.body.x + root.body.width - width)
    y: root.verticalEdge
      ? (root.overlayAlignment === "bottom" ? root.body.y : root.body.y + root.body.height - height)
      : root.body.y + (root.body.height - height) / 2
    radius: Math.min(width, height) / 2
    color: crossMouse.containsMouse || (root.resizing && root.resizeAxis === "cross")
      ? Style.hoverFillFor(root.foreground, Color.accent)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    z: 12

    MouseArea {
      id: crossMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.verticalEdge ? Qt.SizeVerCursor : Qt.SizeHorCursor
      onPressed: function(mouse) { root.resizeStarted("cross", root.pointerPosition(crossHandle, mouse)) }
      onPositionChanged: function(mouse) { root.resizeUpdated(root.pointerPosition(crossHandle, mouse)) }
      onReleased: root.resizeFinished()
      onCanceled: root.resizeCanceled()
    }
  }
}
