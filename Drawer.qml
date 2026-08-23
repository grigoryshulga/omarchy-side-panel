pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property var settings: ({})
  property string edge: "left"
  property var popoutOwner: null
  property bool opened: false
  property int selectedPage: 0
  property int selectedItem: 0
  readonly property int drawerWidth: Math.round(Style.space(420))
  readonly property int drawerHeight: Math.round(Style.space(330))
  readonly property color foreground: Color.popups.text
  readonly property var anchorWidget: bar && typeof bar.findPanelWidget === "function"
    ? bar.findPanelWidget("gshulga.drawer") : null
  readonly property var anchorWindow: anchorWidget ? anchorWidget.QsWindow.window : null
  readonly property var pages: configuredPages()
  readonly property var currentPage: pages.length > 0
    ? pages[Math.max(0, Math.min(selectedPage, pages.length - 1))] : null
  readonly property var currentItem: currentPage && Array.isArray(currentPage.items)
    && currentPage.items.length > 0
    ? currentPage.items[Math.max(0, Math.min(selectedItem, currentPage.items.length - 1))] : null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function configuredPages() {
    var configured = setting("pages", [])
    if (!Array.isArray(configured) || configured.length === 0) {
      return [{
        title: "Plugins",
        items: [
          { id: "io.github.sotoaugusto.ticktick", label: "TickTick", icon: "\uf0ae" },
          { id: "gshulga.jira", label: "Jira", icon: "\ue75c" },
          { id: "b.everything", label: "Everything", icon: "\uf002" }
        ]
      }]
    }

    var valid = []
    for (var i = 0; i < configured.length; i++) {
      var page = configured[i]
      if (!page || !Array.isArray(page.items)) continue
      valid.push({
        title: String(page.title || "Plugins"),
        items: page.items.filter(function(item) { return item && String(item.id || "") !== "" })
      })
    }
    return valid
  }

  function pluginFor(id) {
    if (!bar || !bar.shell || !bar.shell.pluginRegistry) return null
    var registry = bar.shell.pluginRegistry
    var resolved = typeof registry.resolveEnabledId === "function" ? registry.resolveEnabledId(id) : id
    return registry.installedPlugins ? registry.installedPlugins[resolved] : null
  }

  function resolvedPluginId(item) {
    if (!item || !bar || !bar.shell || !bar.shell.pluginRegistry) return ""
    var registry = bar.shell.pluginRegistry
    return typeof registry.resolveEnabledId === "function"
      ? registry.resolveEnabledId(String(item.id)) : String(item.id)
  }

  function drawerPageUrl(item) {
    if (!item || !bar || !bar.shell || !bar.shell.pluginRegistry) return ""
    var registry = bar.shell.pluginRegistry
    var manifest = pluginFor(item.id)
    if (!manifest || !manifest.entryPoints || !manifest.entryPoints.drawerPage) return ""
    return registry.entryPointUrl(manifest, "drawerPage")
  }

  function isEmbedded(item) { return drawerPageUrl(item) !== "" }

  function selectPage(index) {
    if (index < 0 || index >= pages.length) return
    selectedPage = index
    selectedItem = 0
  }

  function selectItem(index) {
    if (!currentPage || !Array.isArray(currentPage.items)) return
    if (index < 0 || index >= currentPage.items.length) return
    selectedItem = index
  }

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened ? close() : open() }

  function launchFallback(item) {
    if (!item || !bar || !bar.shell) return
    close()
    if (!bar.shell.summon(String(item.id)))
      console.warn("Drawer: plugin is unavailable or disabled:", item.id)
  }

  function activateItem(item) {
    if (!item) return
    if (!isEmbedded(item)) launchFallback(item)
  }

  function injectPage(item) {
    var page = pageLoader.item
    if (!page) return
    if ("drawer" in page) page.drawer = root
    if ("bar" in page) page.bar = root.bar
    if ("settings" in page) page.settings = item || ({})
    if ("pluginId" in page) page.pluginId = item ? String(item.id) : ""
    if ("service" in page && root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      page.service = root.bar.shell.serviceFor(root.resolvedPluginId(item))
  }

  onOpenedChanged: {
    if (!bar || !popoutOwner) return
    if (opened) bar.requestPopout(popoutOwner)
    else bar.releasePopout(popoutOwner)
  }

  onPagesChanged: {
    if (selectedPage >= pages.length) selectedPage = Math.max(0, pages.length - 1)
    if (currentPage && selectedItem >= currentPage.items.length) selectedItem = 0
  }
  onCurrentItemChanged: Qt.callLater(function() { root.injectPage(root.currentItem) })

  PanelWindow {
    id: surface
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gshulga-drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      left: root.edge === "left"
      right: root.edge === "right"
      top: root.edge !== "bottom"
      bottom: root.edge !== "top"
    }

    implicitWidth: root.edge === "left" || root.edge === "right" ? root.drawerWidth : 0
    implicitHeight: root.edge === "top" || root.edge === "bottom" ? root.drawerHeight : 0

    Rectangle {
      anchors.fill: parent
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.opened

        Keys.onEscapePressed: root.close()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left && root.pages.length > 1) {
            root.selectPage(Math.max(0, root.selectedPage - 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Right && root.pages.length > 1) {
            root.selectPage(Math.min(root.pages.length - 1, root.selectedPage + 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectItem(Math.max(0, root.selectedItem - 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Down && root.currentPage) {
            root.selectItem(Math.min(root.currentPage.items.length - 1, root.selectedItem + 1))
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.currentItem) {
            root.activateItem(root.currentItem)
            event.accepted = true
          }
        }

        Row {
          anchors.fill: parent
          spacing: 0

          Rectangle {
            width: Style.space(122)
            height: parent.height
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(5)

              Text {
                text: "DRAWER"
                color: root.foreground
                opacity: 0.62
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.3
              }

              Repeater {
                model: root.pages

                delegate: Button {
                  required property int index
                  required property var modelData
                  width: parent.width
                  text: String(modelData.title || "Plugins")
                  foreground: root.foreground
                  bordered: false
                  onClicked: root.selectPage(index)
                  opacity: root.selectedPage === index ? 1 : 0.62
                }
              }

              Item { width: 1; height: 1 }

              Button {
                width: parent.width
                text: "Close"
                foreground: root.foreground
                bordered: false
                onClicked: root.close()
              }
            }
          }

          Item {
            width: parent.width - Style.space(122)
            height: parent.height

            Column {
              id: body
              anchors.fill: parent
              anchors.margins: Style.space(16)
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: parent.width - closeButton.width - parent.spacing
                  text: root.currentPage ? String(root.currentPage.title || "Plugins") : "No pages"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Button {
                  id: closeButton
                  text: "×"
                  foreground: root.foreground
                  onClicked: root.close()
                }
              }

              Row {
                width: parent.width
                height: parent.height - Style.space(52)
                spacing: Style.space(12)

                ListView {
                  id: pluginList
                  width: Style.space(136)
                  height: parent.height
                  clip: true
                  model: root.currentPage ? root.currentPage.items : []
                  currentIndex: root.selectedItem
                  spacing: Style.space(4)
                  onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                  delegate: Button {
                    required property int index
                    required property var modelData
                    width: pluginList.width
                    text: (String(modelData.icon || "\uf0c9") + "  " + String(modelData.label || modelData.id))
                    foreground: root.foreground
                    bordered: false
                    opacity: root.selectedItem === index ? 1 : 0.62
                    onClicked: {
                      root.selectItem(index)
                      root.activateItem(modelData)
                    }
                  }
                }

                Rectangle {
                  width: parent.width - pluginList.width - parent.spacing
                  height: parent.height
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

                  Loader {
                    id: pageLoader
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    active: root.opened && root.isEmbedded(root.currentItem)
                    source: root.drawerPageUrl(root.currentItem)
                    onLoaded: root.injectPage(root.currentItem)
                  }

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(36)
                    spacing: Style.space(8)
                    visible: !root.isEmbedded(root.currentItem)

                    Text {
                      width: parent.width
                      text: root.currentItem ? String(root.currentItem.label || root.currentItem.id) : "No plugin selected"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.subtitle
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: "This plugin has no drawer page. Open it in its native Omarchy panel instead."
                      color: root.foreground
                      opacity: 0.64
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                    }

                    Button {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Open native panel"
                      foreground: root.foreground
                      onClicked: root.launchFallback(root.currentItem)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
