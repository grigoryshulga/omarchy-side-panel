import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string edge: "left"
  property string layoutMode: "overlay"
  property bool verticalEdge: true
  property bool reservesSpace: false
  property string overlayAlignment: "center"
  property color foreground: Color.popups.text
  property bool resizeMode: false
  property bool edgeRevealEnabled: true
  property int edgeRevealDelayMs: 250
  property bool openAnimationEnabled: true

  signal closeRequested()
  signal settingRequested(string name, var value)
  signal resizeModeRequested(bool enabled)

  visible: false

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    contentWidth: width
    contentHeight: content.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: content
      objectName: "settingsContent"
      x: (parent.width - width) / 2
      width: root.verticalEdge ? parent.width : Math.min(parent.width, Style.space(680))
      spacing: Style.space(14)

      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, close.height)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "SIDE PANEL"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Rectangle {
          id: close
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          readonly property bool expanded: closeHover.containsMouse
          width: expanded ? Math.round(Style.space(80)) : Math.round(Style.space(28))
          height: Math.round(Style.space(28))
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          clip: true
          color: closeHover.containsMouse
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(5)
            Text { text: "\uf00d"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { visible: close.expanded; text: "Close"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }

          MouseArea {
            id: closeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
          }
        }
      }

      Text { text: "EDGE"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        id: edgeOptions
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: [
            { edge: "left", icon: "", label: "Left" },
            { edge: "right", icon: "", label: "Right" },
            { edge: "top", icon: "󱔓", label: "Top" },
            { edge: "bottom", icon: "󱂩", label: "Bottom" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((edgeOptions.width - edgeOptions.spacing * 3) / 4)
            height: Math.round(Style.space(52))
            radius: Style.cornerRadius
            color: root.edge === modelData.edge
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingRequested("edge", modelData.edge) }
          }
        }
      }

      Text { text: "DISPLAY MODE"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        id: displayModeOptions
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: [{ mode: "overlay", label: "Overlay" }, { mode: "reserve", label: "Reserve Space" }]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((displayModeOptions.width - displayModeOptions.spacing) / 2)
            height: Math.round(Style.space(42))
            radius: Style.cornerRadius
            color: root.layoutMode === modelData.mode
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Text { anchors.centerIn: parent; text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingRequested("layoutMode", modelData.mode) }
          }
        }
      }

      Text {
        visible: !root.reservesSpace
        height: visible ? implicitHeight : 0
        text: root.verticalEdge ? "OVERLAY ALIGNMENT (VERTICAL)" : "OVERLAY ALIGNMENT (HORIZONTAL)"
        color: root.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Row {
        id: alignmentOptions
        objectName: "overlayAlignmentOptions"
        visible: !root.reservesSpace
        width: parent.width
        height: visible ? Math.round(Style.space(36)) : 0
        spacing: Style.space(8)
        Repeater {
          model: root.verticalEdge
            ? [{ value: "top", label: "Top" }, { value: "center", label: "Center" }, { value: "bottom", label: "Bottom" }]
            : [{ value: "left", label: "Left" }, { value: "center", label: "Center" }, { value: "right", label: "Right" }]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((alignmentOptions.width - alignmentOptions.spacing * 2) / 3)
            height: alignmentOptions.height
            radius: Style.cornerRadius
            color: root.overlayAlignment === modelData.value
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Text { anchors.centerIn: parent; text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingRequested("overlayAlignment", modelData.value) }
          }
        }
      }

      Text { text: "PANEL SIZE"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Rectangle {
        id: resizePanelButton
        objectName: "resizePanelButton"
        width: parent.width
        height: Math.round(Style.space(42))
        radius: Style.cornerRadius
        color: resizeMouse.containsMouse || root.resizeMode
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
        Text { anchors.centerIn: parent; text: root.resizeMode ? "Done resizing" : "Resize Panel"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        MouseArea {
          id: resizeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.resizeModeRequested(!root.resizeMode)
        }
      }

      Text { text: "APPEARANCE"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        width: parent.width
        height: Math.max(animationLabel.implicitHeight, animationToggle.implicitHeight)
        Text {
          id: animationLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Animate opening"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        ToggleSwitch {
          id: animationToggle
          objectName: "openAnimationEnabledControl"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.openAnimationEnabled
          foreground: root.foreground
          onToggled: root.settingRequested("openAnimationEnabled", !root.openAnimationEnabled)
        }
      }

      Text { text: "EDGE REVEAL"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        width: parent.width
        height: Math.max(revealLabel.implicitHeight, revealToggle.implicitHeight)
        Text {
          id: revealLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Reveal at screen edge"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        ToggleSwitch {
          id: revealToggle
          objectName: "edgeRevealEnabledControl"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.edgeRevealEnabled
          foreground: root.foreground
          onToggled: root.settingRequested("edgeRevealEnabled", !root.edgeRevealEnabled)
        }
      }

      Row {
        width: parent.width
        height: Math.max(delayLabel.implicitHeight, delayControl.implicitHeight)
        Text {
          id: delayLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Delay"
          color: root.foreground
          opacity: root.edgeRevealEnabled ? 1 : 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.right: delayControl.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "ms"
          color: root.foreground
          opacity: root.edgeRevealEnabled ? 0.7 : 0.35
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        NumberField {
          id: delayControl
          objectName: "edgeRevealDelayControl"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          value: root.edgeRevealDelayMs
          from: 0
          to: 2000
          stepSize: 50
          foreground: root.foreground
          enabled: root.edgeRevealEnabled
          opacity: enabled ? 1 : 0.5
          onModified: function(value) { root.settingRequested("edgeRevealDelayMs", value) }
        }
      }
    }
  }
}
