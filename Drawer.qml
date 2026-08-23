pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property var settings: ({})
  property string edge: "left"
  property string layoutMode: "overlay"
  property var popoutOwner: null
  property bool opened: false
  property bool pinned: false
  property bool editing: false
  property bool catalogOpen: false
  property string expandedId: ""
  property string draggedId: ""
  property real dragWidth: 0
  property string resizingId: ""
  property real resizeStartHeight: 0
  property real resizeStartY: 0
  property real resizePreviewHeight: 0
  property string dropTargetId: ""
  property bool dropAfter: false
  property real dropLineY: 0
  property var activePanels: []
  property var pluginItems: []
  property var adaptedUrls: ({})
  property string adaptingId: ""
  property string adaptationFailedId: ""
  property string adapterError: ""

  readonly property int drawerWidth: Math.round(Style.space(480))
  readonly property int drawerHeight: Math.round(Style.space(420))
  readonly property bool reservesSpace: layoutMode === "reserve"
  readonly property color foreground: Color.popups.text
  readonly property var anchorWidget: bar && typeof bar.findPanelWidget === "function"
    ? bar.findPanelWidget("gshulga.drawer") : null
  readonly property var anchorWindow: anchorWidget ? anchorWidget.QsWindow.window : null
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omarchy-drawer"
  readonly property var availablePlugins: discoverAvailablePlugins()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function defaultPluginItems() {
    return [
      { id: "io.github.sotoaugusto.ticktick", label: "TickTick", icon: "\uf0ae" },
      { id: "gshulga.jira", label: "Jira", icon: "\ue75c" },
      { id: "omarchy.bluetooth", label: "Bluetooth", icon: "\uf293" },
      { id: "b.everything", label: "Everything", icon: "\uf002" }
    ]
  }

  function normalizeItems(items) {
    var normalized = []
    var seen = ({})
    for (var i = 0; i < (items || []).length; i++) {
      var item = items[i]
      var id = item ? resolvedPluginId(item) : ""
      if (id === "" || id === "gshulga.drawer" || seen[id]) continue
      seen[id] = true
      normalized.push({
        id: id,
        label: String(item.label || ""),
        icon: String(item.icon || ""),
        height: Number(item.height) || 0
      })
    }
    return normalized
  }

  function itemsFromSettings() {
    var configured = setting("plugins", null)
    if (Array.isArray(configured)) return normalizeItems(configured)

    // Preserve users' early page configuration when it is first edited under
    // the new single-list layout.
    var legacyPages = setting("pages", [])
    if (Array.isArray(legacyPages) && legacyPages.length > 0) {
      var flattened = []
      for (var i = 0; i < legacyPages.length; i++) {
        var page = legacyPages[i]
        if (page && Array.isArray(page.items)) flattened = flattened.concat(page.items)
      }
      return normalizeItems(flattened)
    }
    return defaultPluginItems()
  }

  function copyItems(items) {
    var copy = []
    for (var i = 0; i < items.length; i++) {
      copy.push({
        id: items[i].id,
        label: items[i].label,
        icon: items[i].icon,
        height: items[i].height
      })
    }
    return copy
  }

  function persistItems(items) {
    var nextItems = normalizeItems(items)
    pluginItems = nextItems
    var entry = ({ id: "gshulga.drawer" })
    for (var key in settings) if (key !== "id" && key !== "pages") entry[key] = settings[key]
    entry.plugins = copyItems(nextItems)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline("gshulga.drawer", entry)
  }

  function itemFor(id) {
    for (var i = 0; i < pluginItems.length; i++)
      if (pluginItems[i].id === id) return pluginItems[i]
    return null
  }

  function itemIndex(id) {
    var wanted = resolvedPluginId({ id: id })
    for (var i = 0; i < pluginItems.length; i++)
      if (resolvedPluginId(pluginItems[i]) === wanted) return i
    return -1
  }

  function setExpanded(id) {
    if (expandedId === id) {
      deactivateActivePanels()
      expandedId = ""
      return
    }
    deactivateActivePanels()
    expandedId = id
  }

  function setEditing(value) {
    if (editing === value) return
    deactivateActivePanels()
    editing = value
    resizingId = ""
    expandedId = ""
    catalogOpen = false
  }

  function panelHeight(item) {
    if (item && resizingId === item.id) return resizePreviewHeight
    var height = Number(item ? item.height : 0)
    if (!height) height = Style.space(280)
    return Math.round(Math.max(Style.space(160), Math.min(Style.space(520), height)))
  }

  function beginResize(item, y) {
    resizeStartHeight = panelHeight(item)
    resizingId = item.id
    resizeStartY = y
    resizePreviewHeight = resizeStartHeight
  }

  function updateResize(y) {
    if (resizingId === "") return
    var height = resizeStartHeight + y - resizeStartY
    resizePreviewHeight = Math.round(Math.max(Style.space(160), Math.min(Style.space(520), height)) / 5) * 5
  }

  function finishResize() {
    var index = itemIndex(resizingId)
    if (index >= 0) {
      var next = copyItems(pluginItems)
      next[index].height = resizePreviewHeight
      persistItems(next)
    }
    resizingId = ""
  }

  function removePlugin(id) {
    var index = itemIndex(id)
    if (index < 0) return
    if (expandedId === id) {
      deactivateActivePanels()
      expandedId = ""
    }
    var next = copyItems(pluginItems)
    next.splice(index, 1)
    persistItems(next)
  }

  function beginDrag(row, x, y) {
    draggedId = row.pluginId
    var point = row.mapToItem(keyCatcher, x, y)
    dragWidth = row.width
    dragPreview.x = point.x - dragWidth / 2
    dragPreview.y = point.y - dragPreview.height / 2
  }

  function finishDrag() {
    if (draggedId === "") return
    dragPreview.Drag.drop()
    draggedId = ""
  }

  function clearDropTarget() {
    dropTargetId = ""
    dropAfter = false
  }

  function updateDropTarget(x, y) {
    if (!editing || draggedId === "") return
    var contentY = y + pluginList.contentY
    var previousRow = null
    for (var i = 0; i < pluginItems.length; i++) {
      var row = pluginList.itemAtIndex(i)
      if (!row) continue
      if (contentY < row.y + row.height / 2) {
        dropTargetId = row.pluginId
        dropAfter = false
        dropLineY = row.y - pluginList.contentY
        return
      }
      previousRow = row
    }
    if (!previousRow) return
    dropTargetId = previousRow.pluginId
    dropAfter = true
    dropLineY = previousRow.y + previousRow.height - pluginList.contentY
  }

  function moveItem(sourceId, targetId, after) {
    if (sourceId === "" || sourceId === targetId) return
    var sourceIndex = itemIndex(sourceId)
    var targetIndex = itemIndex(targetId)
    if (sourceIndex < 0 || targetIndex < 0) return
    var next = copyItems(pluginItems)
    var item = next.splice(sourceIndex, 1)[0]
    targetIndex = next.map(function(value) { return value.id }).indexOf(targetId)
    next.splice(after ? targetIndex + 1 : targetIndex, 0, item)
    persistItems(next)
  }

  function addPlugin(id) {
    id = resolvedPluginId({ id: id })
    if (id === "" || itemIndex(id) >= 0 || id === "gshulga.drawer") return
    var manifest = pluginFor(id)
    var next = copyItems(pluginItems)
    next.push({
      id: id,
      label: manifest ? String(manifest.name || id) : id,
      icon: ""
    })
    persistItems(next)
    catalogOpen = false
    setExpanded(id)
  }

  function pluginFor(id) {
    if (!bar || !bar.shell || !bar.shell.pluginRegistry) return null
    var registry = bar.shell.pluginRegistry
    var resolved = typeof registry.resolveEnabledId === "function" ? registry.resolveEnabledId(id) : id
    return registry.installedPlugins ? registry.installedPlugins[resolved] : null
  }

  function resolvedPluginId(item) {
    if (!item) return ""
    var id = String(item.id || "")
    if (id === "" || !bar || !bar.shell || !bar.shell.pluginRegistry) return id
    var registry = bar.shell.pluginRegistry
    return typeof registry.resolveEnabledId === "function"
      ? registry.resolveEnabledId(id) : id
  }

  function pluginLabel(item) {
    if (!item) return ""
    if (String(item.label || "") !== "") return String(item.label)
    var manifest = pluginFor(item.id)
    return manifest ? String(manifest.name || item.id) : String(item.id)
  }

  function pluginIcon(item) {
    return item && String(item.icon || "") !== "" ? String(item.icon) : "\uf0c9"
  }

  function discoverAvailablePlugins() {
    if (!bar || !bar.shell || !bar.shell.pluginRegistry) return []
    var plugins = bar.shell.pluginRegistry.installedPlugins || ({})
    var entries = []
    var seen = ({})
    for (var id in plugins) {
      var resolvedId = resolvedPluginId({ id: id })
      if (resolvedId === "gshulga.drawer" || itemIndex(resolvedId) >= 0 || seen[resolvedId]) continue
      seen[resolvedId] = true
      var manifest = pluginFor(resolvedId)
      if (!manifest) continue
      entries.push({
        id: resolvedId,
        label: String(manifest.name || resolvedId),
        description: String(manifest.description || ""),
        enabled: bar.shell.pluginRegistry.isEnabled(resolvedId)
      })
    }
    entries.sort(function(a, b) { return a.label.localeCompare(b.label) })
    return entries
  }

  function drawerPageUrl(item) {
    if (!item || !bar || !bar.shell || !bar.shell.pluginRegistry) return ""
    var registry = bar.shell.pluginRegistry
    var manifest = pluginFor(item.id)
    if (!manifest || !manifest.entryPoints || !manifest.entryPoints.drawerPage) return ""
    return registry.entryPointUrl(manifest, "drawerPage")
  }

  function adaptedUrl(item) {
    if (!item) return ""
    return String(adaptedUrls[resolvedPluginId(item)] || "")
  }

  function panelUrl(item) { return drawerPageUrl(item) || adaptedUrl(item) }

  function canAdapt(item) {
    var manifest = item ? pluginFor(item.id) : null
    return !!(manifest && manifest.entryPoints && manifest.entryPoints.barWidget && manifest.__sourceDir)
  }

  function cacheName(id) { return encodeURIComponent(String(id || "")) }

  function adaptStandardPanel(item) {
    if (!item || !canAdapt(item) || adaptingId !== "") return
    var manifest = pluginFor(item.id)
    var id = resolvedPluginId(item)
    adaptingId = id
    adaptationFailedId = ""
    adapterError = ""
    adapter.command = [
      "bash",
      pluginDir + "bin/omarchy-drawer-adapt",
      String(manifest.__sourceDir),
      String(manifest.entryPoints.barWidget),
      cacheRoot + "/" + cacheName(id),
      pluginDir
    ]
    adapter.running = true
  }

  function adaptationFailed(item) { return resolvedPluginId(item) === adaptationFailedId }

  function activateItem(item) {
    if (!item) return
    if (panelUrl(item) !== "") return
    if (canAdapt(item) && !adaptationFailed(item)) adaptStandardPanel(item)
    else launchFallback(item)
  }

  function injectPanel(page, item) {
    if (!page) return
    if ("drawer" in page) page.drawer = root
    if ("drawerHost" in page) page.drawerHost = root
    if ("bar" in page) page.bar = root.bar
    if ("settings" in page) page.settings = item || ({})
    if ("pluginId" in page) page.pluginId = item ? String(item.id) : ""
    if ("service" in page && root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      page.service = root.bar.shell.serviceFor(root.resolvedPluginId(item))
    var nextPanels = activePanels.slice()
    if (nextPanels.indexOf(page) < 0) nextPanels.push(page)
    activePanels = nextPanels
    if (typeof page.open === "function" && opened) page.open()
  }

  function deactivateActivePanels() {
    for (var i = 0; i < activePanels.length; i++) {
      var panel = activePanels[i]
      if (panel && typeof panel.drawerDeactivate === "function") panel.drawerDeactivate()
    }
    activePanels = []
  }

  function open() { opened = true }
  function close() {
    // Hide the host before deactivating embedded panels: their own lifecycle
    // callbacks must not keep the Drawer surface visible.
    opened = false
    deactivateActivePanels()
    catalogOpen = false
    editing = false
    expandedId = ""
    resizingId = ""
  }
  function toggle() { opened ? close() : open() }

  function launchFallback(item) {
    if (!item || !bar || !bar.shell) return
    close()
    if (!bar.shell.summon(String(item.id)))
      console.warn("Drawer: plugin is unavailable or disabled:", item.id)
  }

  onSettingsChanged: pluginItems = itemsFromSettings()
  Component.onCompleted: pluginItems = itemsFromSettings()

  onOpenedChanged: {
    if (!bar || !popoutOwner) return
    if (opened) bar.requestPopout(popoutOwner)
    else bar.releasePopout(popoutOwner)
  }

  Process {
    id: adapter
    stdout: StdioCollector {
      id: adapterOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: adapterErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var id = root.adaptingId
      root.adaptingId = ""
      if (exitCode !== 0) {
        root.adaptationFailedId = id
        root.adapterError = String(adapterErrors.text || "This plugin does not expose a standard Omarchy panel.").trim()
        return
      }
      var url = String(adapterOutput.text || "").trim()
      if (url === "") {
        root.adaptationFailedId = id
        root.adapterError = "The adapter produced no embedded page."
        return
      }
      var next = ({})
      for (var key in root.adaptedUrls) next[key] = root.adaptedUrls[key]
      next[id] = url
      root.adaptedUrls = next
    }
  }

  PanelWindow {
    id: surface
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.opened
    color: "transparent"
    exclusionMode: root.reservesSpace ? ExclusionMode.Auto : ExclusionMode.Ignore
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

    Shortcut {
      sequence: "Escape"
      enabled: root.opened
      context: Qt.WindowShortcut
      onActivated: {
        if (root.catalogOpen) root.catalogOpen = false
        else root.close()
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.opened
        Item {
          anchors.fill: parent
          anchors.margins: Style.space(14)

          Item {
            id: titleRow
            anchors.top: parent.top
            width: parent.width
            height: title.implicitHeight

            Text {
              id: title
              anchors.left: parent.left
              anchors.right: editButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "PLUGINS"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1.1
              elide: Text.ElideRight
            }

            Rectangle {
              id: editButton
              anchors.right: pinButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: editText.implicitWidth + Style.space(16)
              height: Math.round(Style.space(28))
              radius: height / 2
              color: root.editing
                ? Style.selectedFillFor(root.foreground, Color.accent)
                : (editHover.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06))

              Text {
                id: editText
                anchors.centerIn: parent
                text: root.editing ? "DONE" : "EDIT"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                id: editHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setEditing(!root.editing)
              }
            }

            Rectangle {
              id: pinButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: pinText.implicitWidth + Style.space(16)
              height: Math.round(Style.space(28))
              radius: height / 2
              color: root.pinned
                ? Style.selectedFillFor(root.foreground, Color.accent)
                : (pinHover.containsMouse
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06))

              Text {
                id: pinText
                anchors.centerIn: parent
                text: root.pinned ? "UNPIN" : "PIN"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                id: pinHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pinned = !root.pinned
              }
            }

          }

          ListView {
            id: pluginList
            anchors.top: titleRow.bottom
            anchors.topMargin: Style.space(10)
            anchors.bottom: root.editing ? addButton.top : parent.bottom
            anchors.bottomMargin: root.editing ? Style.space(10) : 0
            width: parent.width
            clip: true
            spacing: Style.space(7)
            model: root.pluginItems

            displaced: Transition {
              NumberAnimation { properties: "x,y"; duration: 150; easing.type: Easing.OutCubic }
            }

            delegate: Item {
              id: pluginRow
              required property int index
              required property var modelData
              readonly property string pluginId: String(modelData.id)
              readonly property bool expanded: !root.editing || root.expandedId === pluginId
              readonly property var plugin: modelData
              width: pluginList.width
              height: (root.editing ? header.height : 0) + content.height
              z: root.draggedId === pluginId ? 3 : 1

              Rectangle {
                id: header
                visible: root.editing
                width: parent.width
                height: Math.round(Style.space(42))
                radius: Style.cornerRadius / 2
                color: pluginRow.expanded
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : (headerHover.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035))
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, pluginRow.expanded ? 0.22 : 0.09)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.pluginIcon(pluginRow.plugin)
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(42)
                  anchors.right: expansionIndicator.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.pluginLabel(pluginRow.plugin)
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: pluginRow.expanded
                  elide: Text.ElideRight
                }

                Text {
                  id: expansionIndicator
                  anchors.right: reorderButton.left
                  anchors.rightMargin: Style.space(7)
                  anchors.verticalCenter: parent.verticalCenter
                  text: pluginRow.expanded ? "-" : "+"
                  color: root.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                }

                MouseArea {
                  id: headerHover
                  anchors.left: parent.left
                  anchors.right: expansionIndicator.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setExpanded(pluginRow.pluginId)
                }

                Item {
                  id: reorderButton
                  anchors.right: deleteButton.left
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.round(Style.space(30))
                  height: width

                  Text {
                    anchors.centerIn: parent
                    text: "\u2195"
                    color: root.foreground
                    opacity: 0.5
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                  }

                  MouseArea {
                    id: reorderMouse
                    anchors.fill: parent
                    cursorShape: Qt.DragMoveCursor
                    drag.target: dragPreview
                    drag.smoothed: false
                    onPressed: function(mouse) {
                      root.beginDrag(pluginRow, reorderButton.x + mouse.x, reorderButton.y + mouse.y)
                    }
                    onReleased: root.finishDrag()
                  }
                }

                Item {
                  id: deleteButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.round(Style.space(30))
                  height: width

                  Text {
                    anchors.centerIn: parent
                    text: "\uf1f8"
                    color: root.foreground
                    opacity: 0.5
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removePlugin(pluginRow.pluginId)
                  }

                }
              }

              Item {
                id: content
                anchors.top: root.editing ? header.bottom : parent.top
                width: parent.width
                height: pluginRow.expanded
                  ? root.panelHeight(pluginRow.plugin)
                  : 0
                clip: true

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: Style.space(5)
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  Loader {
                    id: pageLoader
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    active: root.opened && pluginRow.expanded && root.panelUrl(pluginRow.plugin) !== ""
                    source: root.panelUrl(pluginRow.plugin)
                    onLoaded: root.injectPanel(item, pluginRow.plugin)
                  }

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(36)
                    spacing: Style.space(8)
                    visible: root.panelUrl(pluginRow.plugin) === ""

                    Text {
                      width: parent.width
                      text: root.adaptingId === root.resolvedPluginId(pluginRow.plugin)
                        ? "Embedding the standard Omarchy panel..."
                        : (root.adaptationFailed(pluginRow.plugin) && root.adapterError !== ""
                          ? root.adapterError
                          : "Embed this panel in Drawer without changing its plugin.")
                      color: root.foreground
                      opacity: 0.65
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                    }

                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: actionText.implicitWidth + Style.space(20)
                      height: actionText.implicitHeight + Style.space(12)
                      radius: Style.cornerRadius / 2
                      color: actionHover.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                      Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: root.canAdapt(pluginRow.plugin) && !root.adaptationFailed(pluginRow.plugin)
                          ? "Embed in Drawer" : "Open native panel"
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }

                      MouseArea {
                        id: actionHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.adaptingId === ""
                        onClicked: root.activateItem(pluginRow.plugin)
                      }
                    }
                  }
                }

                Rectangle {
                  id: resizeHandle
                  visible: root.editing && pluginRow.expanded
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.round(Style.space(8))
                  color: resizeMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : "transparent"

                  MouseArea {
                    id: resizeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeVerCursor
                    onPressed: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.beginResize(pluginRow.plugin, point.y)
                    }
                    onPositionChanged: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.updateResize(point.y)
                    }
                    onReleased: root.finishResize()
                  }
                }
              }
            }

            DropArea {
              id: listDropArea
              anchors.fill: parent
              enabled: root.editing
              keys: ["omarchy-drawer-plugin"]
              z: 2
              onEntered: function(drag) { root.updateDropTarget(drag.position.x, drag.position.y) }
              onPositionChanged: function(drag) { root.updateDropTarget(drag.position.x, drag.position.y) }
              onExited: root.clearDropTarget()
              onDropped: function(drop) {
                root.moveItem(root.draggedId, root.dropTargetId, root.dropAfter)
                root.clearDropTarget()
                drop.accepted = true
              }
            }

            Rectangle {
              visible: root.draggedId !== "" && root.dropTargetId !== ""
              x: Style.space(4)
              y: root.dropLineY - height / 2
              width: parent.width - Style.space(8)
              height: Math.max(2, Math.round(Style.space(2)))
              radius: height / 2
              color: Color.accent
              z: 3
            }
          }

          Rectangle {
            id: addButton
            visible: root.editing
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, Style.space(210))
            height: Math.round(Style.space(36))
            radius: height / 2
            color: addHover.containsMouse
              ? Style.hoverFillFor(root.foreground, Color.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

            Text {
              anchors.centerIn: parent
              text: "+ Add installed plugin"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: addHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.catalogOpen = true
            }
          }
        }

        Rectangle {
          id: dragPreview
          visible: root.editing && root.draggedId !== ""
          width: root.dragWidth
          height: Math.round(Style.space(42))
          radius: Style.cornerRadius / 2
          color: Style.selectedFillFor(root.foreground, Color.accent)
          border.width: 1
          border.color: Color.popups.border
          opacity: 0.92
          z: 8

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.pluginLabel(root.itemFor(root.draggedId))
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Drag.active: root.draggedId !== ""
          Drag.keys: ["omarchy-drawer-plugin"]
          Drag.hotSpot.x: width / 2
          Drag.hotSpot.y: height / 2
        }
      }
    }

    Rectangle {
      id: catalog
      anchors.fill: parent
      visible: root.catalogOpen
      z: 10
      color: Qt.rgba(0, 0, 0, 0.56)

      MouseArea {
        anchors.fill: parent
        onClicked: root.catalogOpen = false
      }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(36), Style.space(420))
        height: Math.min(parent.height - Style.space(36), Style.space(520))
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
          anchors.fill: parent
          anchors.margins: Style.space(14)

          Item {
            id: catalogTitleRow
            anchors.top: parent.top
            width: parent.width
            height: Math.max(catalogTitle.implicitHeight, catalogClose.height)

            Text {
              id: catalogTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "ADD PLUGIN"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              id: catalogClose
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "x"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.catalogOpen = false
              }
            }
          }

          ListView {
            anchors.top: catalogTitleRow.bottom
            anchors.topMargin: Style.space(10)
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            spacing: Style.space(5)
            model: root.availablePlugins

            delegate: Rectangle {
              required property var modelData
              width: parent.width
              height: Math.round(Style.space(48))
              radius: Style.cornerRadius / 2
              color: catalogRowHover.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: addAvailable.left
                anchors.rightMargin: Style.space(10)
                anchors.top: parent.top
                anchors.topMargin: Style.space(6)
                text: String(modelData.label)
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: addAvailable.left
                anchors.rightMargin: Style.space(10)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(6)
                text: modelData.enabled ? String(modelData.description) : "Installed, currently disabled"
                color: root.foreground
                opacity: 0.56
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                id: addAvailable
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
              }

              MouseArea {
                id: catalogRowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addPlugin(String(modelData.id))
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.availablePlugins.length === 0
              text: "All installed plugins are already in this list."
              color: root.foreground
              opacity: 0.64
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
