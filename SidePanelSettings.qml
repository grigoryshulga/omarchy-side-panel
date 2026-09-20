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
  property string openTrigger: "hover"
  property int edgeRevealDelayMs: 250
  property bool openAnimationEnabled: true
  property bool openTriggerMenuOpen: false
  property string surfaceMode: "auto"
  property bool dimBackground: false
  property bool blurBackground: true

  signal closeRequested()
  signal settingRequested(string name, var value)
  signal resizeModeRequested(bool enabled)

  function openTriggerLabel(value) {
    if (value === "double-click") return "Double-click screen edge"
    if (value === "none") return "Don't open from screen edge"
    return "Hover at screen edge"
  }

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
          text: "SETTINGS"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        SidePanelActionButton {
          id: close
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: "\uf00d"
          text: "Close"
          foreground: root.foreground
          onClicked: root.closeRequested()
        }
      }

      Text { text: "PLACEMENT"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Text {
        width: parent.width
        text: "Choose the screen edge where the Side Panel appears."
        color: root.foreground
        opacity: 0.62
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

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
          model: [
            { mode: "overlay", icon: "\uf06e", label: "Overlay" },
            { mode: "reserve", icon: "\uf0db", label: "Reserve Space" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((displayModeOptions.width - displayModeOptions.spacing) / 2)
            height: Math.round(Style.space(42))
            radius: Style.cornerRadius
            color: root.layoutMode === modelData.mode
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Row {
              anchors.centerIn: parent
              spacing: Style.space(5)
              Text { text: modelData.icon; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Text { text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingRequested("layoutMode", modelData.mode) }
          }
        }
      }

      Text {
        width: parent.width
        text: root.layoutMode === "reserve"
          ? "Reserves space for the Side Panel and shifts windows away from its edge."
          : "Floats over windows without moving them."
        color: root.foreground
        opacity: 0.62
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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
            ? [{ value: "top", icon: "\uf062", label: "Top" }, { value: "center", icon: "\uf0b2", label: "Center" }, { value: "bottom", icon: "\uf063", label: "Bottom" }]
            : [{ value: "left", icon: "\uf060", label: "Left" }, { value: "center", icon: "\uf0b2", label: "Center" }, { value: "right", icon: "\uf061", label: "Right" }]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((alignmentOptions.width - alignmentOptions.spacing * 2) / 3)
            height: alignmentOptions.height
            radius: Style.cornerRadius
            color: root.overlayAlignment === modelData.value
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Row {
              anchors.centerIn: parent
              spacing: Style.space(5)
              Text { text: modelData.icon; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Text { text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingRequested("overlayAlignment", modelData.value) }
          }
        }
      }

      Text { text: "SIZE"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Rectangle {
        id: resizePanelButton
        objectName: "resizePanelButton"
        width: parent.width
        height: Math.round(Style.space(42))
        radius: Style.cornerRadius
        color: resizeMouse.containsMouse || root.resizeMode
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
        Row {
          anchors.centerIn: parent
          spacing: Style.space(7)
          Text { text: root.resizeMode ? "\uf00c" : "\uf065"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: root.resizeMode ? "Done resizing" : "Resize Panel"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
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
        id: surfaceModeOptions
        objectName: "surfaceModeOptions"
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: [
            { mode: "Auto", icon: "\uf021", label: "Auto" },
            { mode: "Framed", icon: "\uf0c8", label: "Framed" },
            { mode: "Glass", icon: "\uf06e", label: "Glass" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: Math.floor((surfaceModeOptions.width - surfaceModeOptions.spacing * 2) / 3)
            height: Math.round(Style.space(42))
            radius: Style.cornerRadius
            color: String(root.surfaceMode).toLowerCase() === modelData.mode.toLowerCase()
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Row {
              anchors.centerIn: parent
              spacing: Style.space(5)
              Text { text: modelData.icon; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Text { text: modelData.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingRequested("surfaceMode", modelData.mode)
            }
          }
        }
      }

      Text {
        width: parent.width
        text: "Auto turns the panel glassy only while reserving screen space for a transparent bar."
        color: root.foreground
        opacity: 0.62
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item {
        objectName: "dimBackgroundRow"
        visible: !root.reservesSpace
        width: parent.width
        height: visible ? Math.round(Style.space(34)) : 0
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)
          Text { text: "\uf185"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: "Dim background"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        ToggleSwitch {
          objectName: "dimBackgroundControl"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.dimBackground
          foreground: root.foreground
          onToggled: root.settingRequested("dimBackground", !root.dimBackground)
        }
      }

      Item {
        objectName: "blurBackgroundRow"
        visible: root.reservesSpace && String(root.surfaceMode).toLowerCase() !== "framed"
        width: parent.width
        height: visible ? Math.round(Style.space(34)) : 0
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)
          Text { text: "\uf1fc"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: "Blur background"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        ToggleSwitch {
          objectName: "blurBackgroundControl"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.blurBackground
          foreground: root.foreground
          onToggled: root.settingRequested("blurBackground", !root.blurBackground)
        }
      }

      Text { text: "BEHAVIOR"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        width: parent.width
        height: Math.max(animationLabel.implicitHeight, animationToggle.implicitHeight)
        Row {
          id: animationLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)
          Text { text: "\uf01e"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: "Animate opening"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
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

      Text { text: "OPENING"; color: root.foreground; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption }

      Row {
        width: parent.width
        height: Math.max(openTriggerLabel.implicitHeight, openTriggerSelector.height)
        Row {
          id: openTriggerLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)
          Text { text: "\uf0a9"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: "Open from screen edge"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        Rectangle {
          id: openTriggerSelector
          objectName: "openTriggerSelector"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(Math.round(Style.space(230)), parent.width - openTriggerLabel.width - Style.space(16))
          height: Math.round(Style.space(36))
          radius: Style.cornerRadius
          color: openTriggerMouse.containsMouse
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          Text {
            anchors.left: parent.left
            anchors.right: openTriggerChevron.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(6)
            text: root.openTriggerLabel(root.openTrigger)
            color: root.foreground
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            id: openTriggerChevron
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.openTriggerMenuOpen ? "\uf0d8" : "\uf0d7"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          MouseArea {
            id: openTriggerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openTriggerMenuOpen = !root.openTriggerMenuOpen
          }
        }
      }

      Rectangle {
        id: openTriggerMenu
        objectName: "openTriggerListbox"
        visible: root.openTriggerMenuOpen
        width: parent.width
        height: visible ? openTriggerOptions.implicitHeight + Style.space(8) : 0
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
        clip: true
        Column {
          id: openTriggerOptions
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          spacing: Style.space(2)
          Repeater {
            model: [
              { value: "double-click", label: "Double-click screen edge" },
              { value: "hover", label: "Hover at screen edge" },
              { value: "none", label: "Don't open from screen edge" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: openTriggerOptions.width
              height: Math.round(Style.space(34))
              radius: Style.cornerRadius
              color: openTriggerOptionMouse.containsMouse || root.openTrigger === modelData.value
                ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(8)
                text: modelData.label
                color: root.foreground
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: openTriggerOptionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.settingRequested("openTrigger", modelData.value)
                  root.openTriggerMenuOpen = false
                }
              }
            }
          }
        }
      }

      Row {
        visible: root.openTrigger === "hover"
        width: parent.width
        height: visible ? Math.max(revealLabel.implicitHeight, delayControl.implicitHeight) : 0
        Row {
          id: revealLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)
          Text { text: "\uf017"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Text { text: "Reveal delay"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        Text {
          anchors.right: delayControl.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "ms"
          color: root.foreground
          opacity: 0.7
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
          onModified: function(value) { root.settingRequested("edgeRevealDelayMs", value) }
        }
      }
    }
  }
}
