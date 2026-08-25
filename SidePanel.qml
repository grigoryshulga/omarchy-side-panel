pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "SidePanelModel.js" as SidePanelModel

Item {
  id: root

  property QtObject bar: null
  property Item anchorItem: null
  property var settings: ({})
  property string edge: "left"
  property string layoutMode: "overlay"
  property var popoutOwner: null
  property bool opened: false
  property bool closing: false
  property bool suppressPanelClose: false
  property bool pinned: false
  property bool editing: false
  property bool catalogOpen: false
  property bool settingsOpen: false
  property bool renamingPage: false
  property string expandedId: ""
  property string draggedId: ""
  property real dragWidth: 0
  property string resizingId: ""
  property real resizeStartExtent: 0
  property real resizeStartPosition: 0
  property real resizePreviewExtent: 0
  property string dropTargetId: ""
  property bool dropAfter: false
  property real dropLineY: 0
  property var activePanels: []
  property var sidePanelPages: []
  property int currentPage: 0
  readonly property var pluginItems: sidePanelPages.length > 0 && sidePanelPages[currentPage]
    ? sidePanelPages[currentPage].items : []
  property var adaptedUrls: ({})
  property string adaptingId: ""
  property var adaptationErrors: ({})
  property var panelErrors: ({})
  property int panelEpoch: 0
  property bool resizingSidePanel: false
  property real sidePanelResizeStart: 0
  property real sidePanelResizeStartExtent: 0
  property real sidePanelResizePreview: 0
  property int keyboardPluginIndex: -1
  property string hoveredPanelId: ""
  property var sidePanelState: ({})

  readonly property int sidePanelWidth: Math.round(Style.space(480))
  readonly property int sidePanelHeight: Math.round(Style.space(420))
  readonly property bool verticalEdge: edge === "left" || edge === "right"
  readonly property bool reservesSpace: layoutMode === "reserve"
  readonly property bool transparentBackground: reservesSpace && bar && bar.transparent === true
  readonly property real overlayGap: reservesSpace ? 0 : Style.gapsOut
  readonly property string barPosition: bar ? String(bar.position || "top") : "top"
  readonly property real barInset: bar ? Number(bar.barSize || 0) : 0
  readonly property bool edgeRevealConfigured: setting("edgeRevealEnabled", true) === true
  readonly property bool edgeRevealEnabled: !!anchorWindow && edgeRevealConfigured
  readonly property int edgeRevealDelayMs: SidePanelModel.boundedInteger(
    setting("edgeRevealDelayMs", 250), 250, 0, 2000
  )
  readonly property real configuredExtent: SidePanelModel.boundedEdgeSize(
    setting("edgeSize", verticalEdge ? sidePanelWidth : sidePanelHeight),
    verticalEdge ? sidePanelWidth : sidePanelHeight
  )
  readonly property real sidePanelExtent: resizingSidePanel ? sidePanelResizePreview : configuredExtent
  readonly property color foreground: Color.popups.text
  readonly property color transparentTextForeground: Color.bar.text
  readonly property color transparentContrastForeground: Color.background
  property color transparentForeground: transparentTextForeground
  readonly property color chromeForeground: transparentBackground ? transparentForeground : foreground
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omarchy-side-panel"
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/gshulga.side-panel.json"
  readonly property var availablePlugins: discoverAvailablePlugins()

  function setting(name, fallback) {
    var value = sidePanelState && sidePanelState[name] !== undefined ? sidePanelState[name]
      : (settings ? settings[name] : undefined)
    return value === undefined || value === null ? fallback : value
  }

  function colorHex(colorValue) {
    var color = typeof colorValue === "string" ? Qt.color(colorValue) : colorValue
    function channel(value) {
      var hex = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
      return hex.length < 2 ? "0" + hex : hex
    }
    return "#" + channel(color.r) + channel(color.g) + channel(color.b)
  }

  function scheduleTransparentForegroundRefresh() {
    if (!transparentBackground) {
      transparentForeground = transparentTextForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!transparentBackground || transparentForegroundProc.running) return
    // Match Bar's wallpaper-sampled contrast choice for the side panel's own edge.
    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      edge,
      String(Math.max(1, Math.round(sidePanelExtent))),
      colorHex(transparentTextForeground),
      colorHex(transparentContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  function defaultPluginItems() {
    return []
  }

  function normalizeItems(items) {
    return SidePanelModel.normalize(items, function(item) { return root.resolvedPluginId(item) })
  }

  function pagesFromSettings() {
    var source = sidePanelState && Array.isArray(sidePanelState.pages) && sidePanelState.pages.length > 0
      ? sidePanelState : settings
    return SidePanelModel.pagesFromSettings(source, defaultPluginItems(), function(item) {
      return root.resolvedPluginId(item)
    })
  }

  function copyItems(items) {
    return SidePanelModel.copy(items)
  }

  function copyPages(pages) {
    return SidePanelModel.copyPages(pages)
  }

  function currentPageRecord() {
    return sidePanelPages.length > 0 ? sidePanelPages[currentPage] : null
  }

  function persistPages(pages, nextPage) {
    var nextPages = SidePanelModel.normalizePages(pages, defaultPluginItems(), function(item) {
      return root.resolvedPluginId(item)
    })
    deactivateActivePanels()
    sidePanelPages = nextPages
    currentPage = Math.max(0, Math.min(nextPages.length - 1, nextPage === undefined ? currentPage : nextPage))
    persistSidePanelState()
    var entry = SidePanelModel.persistedEntry(settings, nextPages)
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline("gshulga.side-panel", entry)
  }

  function persistItems(items) {
    var nextItems = normalizeItems(items)
    var nextPages = copyPages(sidePanelPages)
    if (nextPages.length === 0) nextPages.push({ title: "Plugins", items: [] })
    nextPages[currentPage].items = nextItems
    persistPages(nextPages, currentPage)
  }

  function selectPage(index) {
    if (index < 0 || index >= sidePanelPages.length || index === currentPage) return
    deactivateActivePanels("page-change")
    currentPage = index
    expandedId = ""
    renamingPage = false
    persistSidePanelState()
    panelEpoch += 1
    if (opened) adaptPreferredPanels()
  }

  function movePage(delta) {
    if (sidePanelPages.length < 2) return
    selectPage((currentPage + delta + sidePanelPages.length) % sidePanelPages.length)
  }

  function addPage() {
    var nextPages = copyPages(sidePanelPages)
    nextPages.push({ title: "Page " + (nextPages.length + 1), items: [] })
    persistPages(nextPages, nextPages.length - 1)
  }

  function renameCurrentPage(title) {
    var nextPages = copyPages(sidePanelPages)
    if (nextPages.length === 0) return
    nextPages[currentPage].title = String(title || "").trim() || "Page " + (currentPage + 1)
    persistPages(nextPages, currentPage)
  }

  function beginPageRename() {
    if (!currentPageRecord()) return
    renamingPage = true
    Qt.callLater(function() {
      if (!renamingPage) return
      pageTitleInput.forceActiveFocus()
      pageTitleInput.selectAll()
    })
  }

  function finishPageRename(title) {
    if (!renamingPage) return
    renamingPage = false
    renameCurrentPage(title)
  }

  function removeCurrentPage() {
    if (sidePanelPages.length <= 1) return
    var nextPages = copyPages(sidePanelPages)
    nextPages.splice(currentPage, 1)
    persistPages(nextPages, Math.min(currentPage, nextPages.length - 1))
  }

  function moveKeyboardPlugin(delta) {
    if (pluginItems.length === 0) return
    keyboardPluginIndex = (keyboardPluginIndex + delta + pluginItems.length) % pluginItems.length
    pluginList.positionViewAtIndex(keyboardPluginIndex, ListView.Contain)
  }

  function focusKeyboardPlugin(delta) {
    moveKeyboardPlugin(delta)
    Qt.callLater(function() {
      var row = pluginList.itemAtIndex(keyboardPluginIndex)
      if (row && typeof row.focusPanel === "function") row.focusPanel()
    })
  }

  function scrollPluginList(deltaX, deltaY) {
    if (hoveredPanelId !== "") return
    var delta = verticalEdge ? deltaY : (deltaX !== 0 ? deltaX : deltaY)
    if (delta === 0) return
    if (verticalEdge) {
      var maxY = Math.max(0, pluginList.contentHeight - pluginList.height)
      pluginList.contentY = Math.max(0, Math.min(maxY, pluginList.contentY - delta))
    } else {
      var maxX = Math.max(0, pluginList.contentWidth - pluginList.width)
      pluginList.contentX = Math.max(0, Math.min(maxX, pluginList.contentX - delta))
    }
  }

  function handlePanelWheel(modifiers, deltaX, deltaY) {
    if (modifiers & Qt.AltModifier) {
      if (deltaY > 0) movePage(1)
      else if (deltaY < 0) movePage(-1)
      return
    }
    scrollPluginList(deltaX, deltaY)
  }

  function persistSidePanelSetting(name, value) {
    if (name === "edgeSize")
      value = SidePanelModel.boundedEdgeSize(value, verticalEdge ? sidePanelWidth : sidePanelHeight)
    var entry = SidePanelModel.persistedEntry(settings, sidePanelPages)
    entry[name] = value
    var overrides = ({})
    overrides[name] = value
    persistSidePanelState(overrides)
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline("gshulga.side-panel", entry)
  }

  function persistSidePanelState(overrides) {
    var state = {
      version: 1,
      pages: copyPages(sidePanelPages),
      currentPage: currentPage
    }
    var settingNames = ["edge", "edgeSize", "layoutMode"]
    for (var index = 0; index < settingNames.length; index++) {
      var name = settingNames[index]
      var value = overrides && overrides[name] !== undefined ? overrides[name] : setting(name, undefined)
      if (name === "edgeSize")
        value = SidePanelModel.boundedEdgeSize(value, verticalEdge ? sidePanelWidth : sidePanelHeight)
      if (value !== undefined && value !== null) state[name] = value
    }
    sidePanelState = state
    sidePanelStateFile.setText(JSON.stringify(state, null, 2) + "\n")
  }

  function loadSidePanelState(raw) {
    var state = SidePanelModel.parseState(raw, defaultPluginItems(), function(item) {
      return root.resolvedPluginId(item)
    })
    if (!state) {
      console.warn("SidePanel: cannot load saved state")
      return
    }
    deactivateActivePanels("state-load")
    sidePanelState = state
    sidePanelPages = state.pages
    currentPage = state.currentPage
  }

  function loadSavedSidePanelState() {
    stateReader.command = [
      "python3", pluginDir + "/bin/omarchy-side-panel-read-state",
      statePath, String(SidePanelModel.MAX_STATE_BYTES)
    ]
    stateReader.running = true
  }

  function startEdgeReveal() {
    if (!edgeRevealEnabled || opened) return
    edgeRevealTimer.restart()
  }

  function cancelEdgeReveal() {
    edgeRevealTimer.stop()
  }

  function resizePosition(handle, x, y) {
    var target = anchorWindow ? anchorWindow.contentItem : surface.contentItem
    var point = handle.mapToItem(target, x, y)
    return verticalEdge ? point.x : point.y
  }

  function beginSidePanelResize(position) {
    resizingSidePanel = true
    sidePanelResizeStart = position
    sidePanelResizeStartExtent = sidePanelExtent
    sidePanelResizePreview = sidePanelExtent
  }

  function updateSidePanelResize(position) {
    if (!resizingSidePanel) return
    var delta = position - sidePanelResizeStart
    if (edge === "right" || edge === "bottom") delta = -delta
    sidePanelResizePreview = Math.round(Math.max(Style.space(260), Math.min(Style.space(900), sidePanelResizeStartExtent + delta)) / 5) * 5
  }

  function finishSidePanelResize() {
    if (!resizingSidePanel) return
    persistSidePanelSetting("edgeSize", sidePanelResizePreview)
    resizingSidePanel = false
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

  function hasPlugin(id) {
    var wanted = resolvedPluginId({ id: id })
    for (var pageIndex = 0; pageIndex < sidePanelPages.length; pageIndex++) {
      var items = sidePanelPages[pageIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        if (resolvedPluginId(items[itemIndex]) === wanted) return true
      }
    }
    return false
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
    cancelDrag()
    cancelResize()
    deactivateActivePanels()
    editing = value
    renamingPage = false
    resizingId = ""
    expandedId = ""
    catalogOpen = false
    settingsOpen = false
    panelEpoch += 1
  }

  function panelHeight(item) {
    if (item && resizingId === item.id) return resizePreviewExtent
    var height = Number(item ? item.height : 0)
    if (!height) height = Style.space(280)
    return Math.max(5, Math.round(height))
  }

  function panelWidth(item) {
    if (item && resizingId === item.id) return resizePreviewExtent
    var width = Number(item ? item.width : 0)
    if (!width) width = Style.space(360)
    return Math.max(5, Math.round(width))
  }

  function beginResize(item, position) {
    resizeStartExtent = verticalEdge ? panelHeight(item) : panelWidth(item)
    resizingId = item.id
    resizeStartPosition = position
    resizePreviewExtent = resizeStartExtent
  }

  function updateResize(position) {
    if (resizingId === "") return
    resizePreviewExtent = SidePanelModel.resizeHeight(resizeStartExtent, resizeStartPosition, position, 5, 5)
  }

  function finishResize() {
    var index = itemIndex(resizingId)
    if (index >= 0) {
      var next = copyItems(pluginItems)
      if (verticalEdge) next[index].height = resizePreviewExtent
      else next[index].width = resizePreviewExtent
      persistItems(next)
    }
    resizingId = ""
  }

  function cancelResize() {
    resizingId = ""
    resizePreviewExtent = 0
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
    var listPoint = keyCatcher.mapToItem(pluginList, point.x, point.y)
    updateDropTarget(listPoint.x, listPoint.y)
  }

  function updateDrag(row, x, y) {
    if (draggedId !== row.pluginId) return
    var point = row.mapToItem(keyCatcher, x, y)
    dragPreview.x = point.x - dragWidth / 2
    dragPreview.y = point.y - dragPreview.height / 2
    var listPoint = keyCatcher.mapToItem(pluginList, point.x, point.y)
    updateDropTarget(listPoint.x, listPoint.y)
  }

  function finishDrag() {
    if (draggedId === "") return
    var sourceId = draggedId
    var targetId = dropTargetId
    var after = dropAfter
    cancelDrag()
    if (targetId !== "") moveItem(sourceId, targetId, after)
  }

  function cancelDrag() {
    draggedId = ""
    dragWidth = 0
    clearDropTarget()
  }

  function clearDropTarget() {
    dropTargetId = ""
    dropAfter = false
  }

  function updateDropTarget(x, y) {
    if (!editing || draggedId === "") return
    var position = verticalEdge ? y : x
    var previousRow = null
    for (var i = 0; i < pluginItems.length; i++) {
      var row = pluginList.itemAtIndex(i)
      if (!row) continue
      var start = verticalEdge ? row.y : row.x
      var extent = verticalEdge ? row.height : row.width
      if (position < start + extent / 2) {
        dropTargetId = row.pluginId
        dropAfter = false
        dropLineY = start
        return
      }
      previousRow = row
    }
    if (!previousRow) return
    dropTargetId = previousRow.pluginId
    dropAfter = true
    dropLineY = (verticalEdge ? previousRow.y + previousRow.height : previousRow.x + previousRow.width)
  }

  function moveItem(sourceId, targetId, after) {
    if (sourceId === "" || sourceId === targetId) return
    var sourceIndex = itemIndex(sourceId)
    var targetIndex = itemIndex(targetId)
    if (sourceIndex < 0 || targetIndex < 0) return
    persistItems(SidePanelModel.move(pluginItems, sourceId, targetId, after))
  }

  function addPlugin(id) {
    id = resolvedPluginId({ id: id })
    if (id === "" || hasPlugin(id) || id === "gshulga.side-panel") return
    var manifest = pluginFor(id)
    if (!manifest) return
    var next = copyItems(pluginItems)
    next.push({
      id: id,
      label: String(manifest.name || id),
      icon: ""
    })
    persistItems(next)
    enablePluginForSidePanel(id, manifest)
    catalogOpen = false
    setExpanded(id)
  }

  function enablePluginForSidePanel(id, manifest) {
    if (pluginEnabled({ id: id }) || !bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function(config) {
      var disabled = Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []
      config.disabledPlugins = disabled.filter(function(entry) { return String(entry) !== id })
      if (config.disabledPlugins.length === 0) delete config.disabledPlugins
      if (manifest.__isFirstParty) return
      if (!Array.isArray(config.plugins)) config.plugins = []
      for (var index = 0; index < config.plugins.length; index++)
        if (config.plugins[index] && String(config.plugins[index].id) === id) return
      config.plugins.push({ id: id })
    })
  }

  function pluginFor(id) {
    if (!bar || !bar.shell || !bar.shell.pluginRegistry) return null
    var registry = bar.shell.pluginRegistry
    var resolved = typeof registry.resolveEnabledId === "function" ? registry.resolveEnabledId(id) : id
    return registry.installedPlugins ? registry.installedPlugins[resolved] : null
  }

  function pluginEnabled(item) {
    if (!item || !bar || !bar.shell || !bar.shell.pluginRegistry) return false
    return bar.shell.pluginRegistry.isEnabled(resolvedPluginId(item))
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
      if (resolvedId === "gshulga.side-panel" || hasPlugin(resolvedId) || seen[resolvedId]) continue
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

  function sidePanelPageUrl(item) {
    if (!item || !bar || !bar.shell || !bar.shell.pluginRegistry) return ""
    if (!pluginEnabled(item)) return ""
    var registry = bar.shell.pluginRegistry
    var manifest = pluginFor(item.id)
    if (!manifest || !manifest.entryPoints || !manifest.entryPoints.sidePanelPage) return ""
    return registry.entryPointUrl(manifest, "sidePanelPage")
  }

  function adaptedUrl(item) {
    if (!item) return ""
    return String(adaptedUrls[resolvedPluginId(item)] || "")
  }

  function panelUrl(item) { return sidePanelPageUrl(item) || adaptedUrl(item) }

  function panelSource(item) {
    var url = panelUrl(item)
    if (url === "") return ""
    return url + (url.indexOf("?") >= 0 ? "&" : "?") + "sidePanelEpoch=" + panelEpoch
  }

  function panelError(item) {
    return String(panelErrors[resolvedPluginId(item)] || "The embedded page could not be loaded.")
  }

  function panelLoadFailed(item) {
    return panelErrors[resolvedPluginId(item)] !== undefined
  }

  function setPanelError(item, message) {
    var next = ({})
    for (var key in panelErrors) next[key] = panelErrors[key]
    next[resolvedPluginId(item)] = String(message || "The embedded page could not be loaded.")
    panelErrors = next
  }

  function clearPanelError(item) {
    var id = resolvedPluginId(item)
    if (panelErrors[id] === undefined) return
    var next = ({})
    for (var key in panelErrors) if (key !== id) next[key] = panelErrors[key]
    panelErrors = next
  }

  function canAdapt(item) {
    var manifest = item ? pluginFor(item.id) : null
    return !!(pluginEnabled(item) && manifest && manifest.entryPoints
      && manifest.entryPoints.barWidget && manifest.__sourceDir)
  }

  function adaptStandardPanel(item) {
    if (!item || !canAdapt(item) || adaptingId !== "") return
    var id = resolvedPluginId(item)
    var manifest = pluginFor(item.id)
    adaptingId = id
    clearAdaptationError(id)
    adapter.command = [
      "bash",
      pluginDir + "bin/omarchy-side-panel-adapt",
      String(manifest.__sourceDir),
      String(manifest.entryPoints.barWidget),
      cacheRoot,
      id,
      pluginDir
    ]
    adapter.running = true
  }

  function adaptPreferredPanels() {
    if (!opened || adaptingId !== "") return
    for (var pageIndex = 0; pageIndex < sidePanelPages.length; pageIndex++) {
      var items = sidePanelPages[pageIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        var item = items[itemIndex]
        if (adaptedUrl(item) === "" && canAdapt(item) && !adaptationFailed(item)) {
          adaptStandardPanel(item)
          return
        }
      }
    }
  }

  function adaptationFailed(item) { return adaptationErrors[resolvedPluginId(item)] !== undefined }

  function adaptationError(item) {
    return String(adaptationErrors[resolvedPluginId(item)] || "")
  }

  function setAdaptationError(id, message) {
    var next = ({})
    for (var key in adaptationErrors) next[key] = adaptationErrors[key]
    next[id] = String(message || "This plugin does not expose a standard Omarchy panel.")
    adaptationErrors = next
  }

  function clearAdaptationError(id) {
    if (adaptationErrors[id] === undefined) return
    var next = ({})
    for (var key in adaptationErrors) if (key !== id) next[key] = adaptationErrors[key]
    adaptationErrors = next
  }

  function activateItem(item) {
    if (!item) return
    if (panelLoadFailed(item)) {
      launchFallback(item)
      return
    }
    if (panelUrl(item) !== "") return
    if (canAdapt(item)) adaptStandardPanel(item)
    else launchFallback(item)
  }

  function injectPanel(page, item) {
    if (!page) return
    var id = root.resolvedPluginId(item)
    var context = {
      sidePanel: root,
      sidePanelItem: item || ({}),
      bar: root.bar,
      pluginId: id,
      settings: root.nativeSettings(id),
      service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
        ? root.bar.shell.serviceFor(id) : null
    }
    if (typeof page.initializeSidePanel === "function") {
      page.initializeSidePanel(context)
    } else {
      assignPanelProperty(page, "sidePanel", context.sidePanel)
      assignPanelProperty(page, "sidePanelHost", context.sidePanel)
      assignPanelProperty(page, "sidePanelItem", context.sidePanelItem)
      assignPanelProperty(page, "bar", context.bar)
      assignPanelProperty(page, "settings", context.settings)
      assignPanelProperty(page, "pluginId", context.pluginId)
      assignPanelProperty(page, "service", context.service)
    }
    var nextPanels = activePanels.slice()
    if (nextPanels.indexOf(page) < 0) nextPanels.push(page)
    activePanels = nextPanels
    if (typeof page.sidePanelActivate === "function" && opened) page.sidePanelActivate(context)
    else if (typeof page.open === "function" && opened) page.open()
  }

  function assignPanelProperty(page, name, value) {
    if (!(name in page)) return
    try {
      page[name] = value
    } catch (error) {
      console.warn("SidePanel: cannot inject " + name + ":", error)
    }
  }

  function nativeSettings(id) {
    if (!bar || typeof bar.moduleWidgets !== "function") return ({})
    var widgets = bar.moduleWidgets(id)
    return widgets.length > 0 && widgets[0] && widgets[0].settings ? widgets[0].settings : ({})
  }

  function deactivateActivePanels(reason) {
    var panels = activePanels.slice()
    activePanels = []
    var previousSuppression = suppressPanelClose
    suppressPanelClose = true
    for (var i = 0; i < panels.length; i++) {
      var panel = panels[i]
      if (!panel) continue
      if ("sidePanelHost" in panel && typeof panel.close === "function") panel.close()
      else if (typeof panel.sidePanelDeactivate === "function") panel.sidePanelDeactivate(reason || "sidePanel")
      else if (typeof panel.close === "function") panel.close()
    }
    suppressPanelClose = previousSuppression
  }

  function panelClosed(page) {
    if (closing || suppressPanelClose || !opened) return
    var nextPanels = []
    var wasActive = false
    for (var i = 0; i < activePanels.length; i++) {
      if (activePanels[i] === page) wasActive = true
      else nextPanels.push(activePanels[i])
    }
    // Panel hosts report close asynchronously. A panel removed during edit or
    // page navigation must not be mistaken for a user-requested sidePanel close.
    if (!wasActive) return
    activePanels = nextPanels
    close()
  }

  function open() { opened = true }
  function close() {
    if (closing || !opened) return
    closing = true
    deactivateActivePanels("sidePanel-close")
    opened = false
    pinned = false
    catalogOpen = false
    editing = false
    expandedId = ""
    renamingPage = false
    hoveredPanelId = ""
    cancelResize()
    cancelDrag()
    closing = false
  }
  function toggle() { opened ? close() : open() }

  function handleEscape() {
    if (catalogOpen) catalogOpen = false
    else if (settingsOpen) settingsOpen = false
    else if (!pinned) close()
  }

  function launchFallback(item) {
    if (!item || !bar || !bar.shell || !pluginEnabled(item)) {
      setPanelError(item, "Enable this plugin in Omarchy before opening its native panel.")
      return
    }
    if (bar.shell.summon(String(resolvedPluginId(item)))) close()
    else setPanelError(item, "This plugin has no native panel that Omarchy can open.")
  }

  onSettingsChanged: {
    cancelEdgeReveal()
    deactivateActivePanels("settings-change")
    var selectedTitle = currentPageRecord() ? String(currentPageRecord().title) : ""
    sidePanelPages = pagesFromSettings()
    currentPage = 0
    for (var index = 0; index < sidePanelPages.length; index++) {
      if (String(sidePanelPages[index].title) === selectedTitle) {
        currentPage = index
        break
      }
    }
    // Reload adapted panels after their previous instances have been closed.
    panelEpoch += 1
    if (opened) adaptPreferredPanels()
  }
  Component.onCompleted: {
    sidePanelPages = pagesFromSettings()
    scheduleTransparentForegroundRefresh()
    loadSavedSidePanelState()
  }
  onTransparentBackgroundChanged: scheduleTransparentForegroundRefresh()
  onTransparentTextForegroundChanged: scheduleTransparentForegroundRefresh()
  onTransparentContrastForegroundChanged: scheduleTransparentForegroundRefresh()
  onEdgeChanged: {
    cancelEdgeReveal()
    scheduleTransparentForegroundRefresh()
  }
  onSidePanelExtentChanged: scheduleTransparentForegroundRefresh()

  FileView {
    id: sidePanelStateFile
    path: root.statePath
    atomicWrites: true
    preload: false
    printErrors: false
  }

  Process {
    id: stateReader
    stdout: StdioCollector {
      id: stateReaderOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.loadSidePanelState(String(stateReaderOutput.text || ""))
      } else if (exitCode === 2) {
        console.warn("SidePanel: saved state exceeds the size limit")
      } else if (exitCode === 3) {
        console.warn("SidePanel: refusing unsafe saved state file")
      } else if (root.sidePanelPages.length > 0) {
        root.persistSidePanelState()
      }
    }
  }

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Timer {
    id: edgeRevealTimer
    interval: root.edgeRevealDelayMs
    repeat: false
    onTriggered: {
      if (root.edgeRevealEnabled && !root.opened) root.open()
    }
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (/^#[0-9A-Fa-f]{6}$/.test(value)) root.transparentForeground = value
      }
    }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  onOpenedChanged: {
    if (bar && popoutOwner) {
      if (opened) bar.requestPopout(popoutOwner)
      else bar.releasePopout(popoutOwner)
    }
    if (opened) {
      currentPage = 0
      adaptationErrors = ({})
      adaptPreferredPanels()
    }
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
        root.setAdaptationError(id, String(adapterErrors.text || "This plugin does not expose a standard Omarchy panel.").trim())
        root.adaptPreferredPanels()
        return
      }
      var url = String(adapterOutput.text || "").trim()
      if (url === "") {
        root.setAdaptationError(id, "The adapter produced no embedded page.")
        root.adaptPreferredPanels()
        return
      }
      var next = ({})
      for (var key in root.adaptedUrls) next[key] = root.adaptedUrls[key]
      next[id] = url
      root.adaptedUrls = next
      root.adaptPreferredPanels()
    }
  }

  PanelWindow {
    id: edgeRevealSurface
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.edgeRevealEnabled && !root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gshulga-side-panel-edge-reveal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    // Only the two-pixel edge strip receives pointer input; the rest of this
    // transparent fullscreen surface remains click-through.
    mask: Region { item: edgeRevealArea }

    Item {
      id: edgeRevealArea
      x: root.edge === "right" ? parent.width - width : 0
      y: root.edge === "bottom" ? parent.height - height : 0
      width: root.verticalEdge ? 2 : parent.width
      height: root.verticalEdge ? parent.height : 2

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.startEdgeReveal()
        onExited: root.cancelEdgeReveal()
      }
    }
  }

  PanelWindow {
    id: surface
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.opened
    color: "transparent"
    exclusionMode: root.reservesSpace ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "gshulga-side-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    // An Exclusive focus prime is needed when reopening a still-mapped
    // layer surface; OnDemand alone does not reliably restore key delivery.
    WlrLayershell.keyboardFocus: root.opened
      ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    property bool focusPrimed: false

    function primeFocus() {
      if (root.opened && backingWindowVisible) focusPrimeTimer.restart()
    }

    onBackingWindowVisibleChanged: primeFocus()

    Timer {
      id: focusPrimeTimer
      interval: 75
      onTriggered: {
        if (!root.opened) return
        surface.focusPrimed = true
        keyCatcher.forceActiveFocus()
      }
    }

    Connections {
      target: root
      function onOpenedChanged() {
        root.cancelEdgeReveal()
        if (!root.opened) {
          surface.focusPrimed = false
          return
        }
        surface.focusPrimed = false
        surface.primeFocus()
        Qt.callLater(function() {
          if (root.opened) keyCatcher.forceActiveFocus()
        })
      }
    }

    anchors {
      left: !root.reservesSpace || root.edge === "left" || !root.verticalEdge
      right: !root.reservesSpace || root.edge === "right" || !root.verticalEdge
      top: !root.reservesSpace || root.verticalEdge || root.edge === "top"
      bottom: !root.reservesSpace || root.verticalEdge || root.edge === "bottom"
    }

    // Transparent layer surfaces need an explicit input region; otherwise the
    // compositor routes clicks outside SidePanel directly to the app beneath it.
    mask: Region {
      width: surface.width
      height: surface.height
    }

    implicitWidth: root.verticalEdge
      ? Math.min(root.sidePanelExtent, screen ? screen.width : root.sidePanelExtent) : 0
    implicitHeight: root.verticalEdge ? 0
      : Math.min(root.sidePanelExtent, screen ? screen.height : root.sidePanelExtent)

    Shortcut {
      sequence: "Escape"
      enabled: root.opened
      // Embedded panels move active focus into their own key catchers. An
      // application shortcut still reaches SidePanel and provides one consistent
      // close path in both normal and edit modes.
      context: Qt.ApplicationShortcut
      onActivated: {
        root.handleEscape()
      }
    }

    // The fullscreen layer surface sits above the bar while SidePanel is open.
    // Forward clicks in the bar strip to the registered WidgetButton so its
    // icon can close SidePanel or switch to another Omarchy popup in one click.
    MouseArea {
      id: surfaceClickForwarder
      anchors.fill: parent
      z: 0
      enabled: root.opened
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

      function inBarRegion(x, y) {
        if (root.barPosition === "bottom") return y >= height - root.barInset
        if (root.barPosition === "left") return x <= root.barInset
        if (root.barPosition === "right") return x >= width - root.barInset
        return y <= root.barInset
      }

      function barPoint(x, y) {
        if (root.barPosition === "bottom") return Qt.point(x, y - (height - root.barInset))
        if (root.barPosition === "right") return Qt.point(x - (width - root.barInset), y)
        return Qt.point(x, y)
      }

      function forwardBarClick(x, y, button) {
        if (!root.bar || !root.anchorWindow || !root.anchorWindow.contentItem || !root.bar.clickTargets) return false
        var point = barPoint(x, y)
        var targets = root.bar.clickTargets
        for (var i = targets.length - 1; i >= 0; i--) {
          var target = targets[i]
          if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
          if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
          var position = root.anchorWindow.itemPosition(target)
          if (point.x >= position.x && point.x <= position.x + target.width
              && point.y >= position.y && point.y <= position.y + target.height) {
            target.triggerPress(button)
            return true
          }
        }
        return false
      }

      onClicked: function(mouse) {
        if (inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
        if (!root.pinned) root.close()
      }
    }

    Shortcut {
      sequence: "Alt+1"
      enabled: root.opened
      context: Qt.WindowShortcut
      onActivated: root.selectPage(0)
    }
    Shortcut { sequence: "Alt+2"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(1) }
    Shortcut { sequence: "Alt+3"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(2) }
    Shortcut { sequence: "Alt+4"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(3) }
    Shortcut { sequence: "Alt+5"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(4) }
    Shortcut { sequence: "Alt+6"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(5) }
    Shortcut { sequence: "Alt+7"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(6) }
    Shortcut { sequence: "Alt+8"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(7) }
    Shortcut { sequence: "Alt+9"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.selectPage(8) }
    Shortcut { sequence: "Alt+Right"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.movePage(1) }
    Shortcut { sequence: "Alt+Left"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.movePage(-1) }
    Shortcut { sequence: "Ctrl+Tab"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.focusKeyboardPlugin(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.focusKeyboardPlugin(-1) }

    Rectangle {
      id: sidePanelBody
      anchors.fill: parent
      z: 1
      anchors.topMargin: root.overlayGap + (!root.reservesSpace && root.barPosition === "top" ? root.barInset : 0)
        + (!root.verticalEdge && root.edge === "bottom" ? Math.max(0, parent.height - root.sidePanelExtent) : 0)
      anchors.rightMargin: root.overlayGap + (!root.reservesSpace && root.barPosition === "right" ? root.barInset : 0)
        + (root.verticalEdge && root.edge === "left" ? Math.max(0, parent.width - root.sidePanelExtent) : 0)
      anchors.bottomMargin: root.overlayGap + (!root.reservesSpace && root.barPosition === "bottom" ? root.barInset : 0)
        + (!root.verticalEdge && root.edge === "top" ? Math.max(0, parent.height - root.sidePanelExtent) : 0)
      anchors.leftMargin: root.overlayGap + (!root.reservesSpace && root.barPosition === "left" ? root.barInset : 0)
        + (root.verticalEdge && root.edge === "right" ? Math.max(0, parent.width - root.sidePanelExtent) : 0)
      radius: root.reservesSpace ? 0 : Style.cornerRadius
      color: root.transparentBackground ? "transparent" : Color.popups.background
      border.width: root.reservesSpace || root.transparentBackground ? 0 : 1
      border.color: root.transparentBackground ? "transparent" : Color.popups.border

      MouseArea {
        anchors.fill: parent
        z: -1
        onWheel: function(wheel) {
          root.handlePanelWheel(wheel.modifiers, wheel.angleDelta.x, wheel.angleDelta.y)
          wheel.accepted = true
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.opened
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.handleEscape()
            event.accepted = true
          }
        }
        Item {
          visible: !root.settingsOpen
          anchors.fill: parent
          anchors.margins: Style.space(14)

          Item {
            id: titleRow
            anchors.top: parent.top
            width: parent.width
            height: title.implicitHeight

            Text {
              id: title
              visible: !root.renamingPage
              anchors.left: parent.left
              anchors.right: root.editing ? removePageButton.left : editButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.currentPageRecord() ? String(root.currentPageRecord().title).toUpperCase() : "PLUGINS"
              textFormat: Text.PlainText
              color: root.chromeForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1.1
              elide: Text.ElideRight

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onDoubleClicked: root.beginPageRename()
              }
            }

            TextInput {
              id: pageTitleInput
              visible: root.renamingPage
              anchors.left: parent.left
              anchors.right: root.editing ? removePageButton.left : editButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.currentPageRecord() ? String(root.currentPageRecord().title) : ""
              color: root.chromeForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1.1
              selectByMouse: true
              onEditingFinished: root.finishPageRename(text)
              Keys.onEscapePressed: function(event) {
                root.renamingPage = false
                event.accepted = true
              }
            }

            Rectangle {
              id: settingsButton
              visible: !root.editing && (titleRowHover.hovered || root.settingsOpen)
              anchors.right: editButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(Style.space(28))
              height: width
              radius: height / 2
              color: settingsHover.containsMouse ? Style.hoverFillFor(root.chromeForeground, Color.accent) : "transparent"
              Text { anchors.centerIn: parent; text: "\uf013"; color: root.chromeForeground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              MouseArea { id: settingsHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsOpen = true }
            }

            Rectangle {
              id: editButton
              visible: titleRowHover.hovered || root.editing
              anchors.right: root.editing ? parent.right : pinButton.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              color: root.editing
                ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                : (editHover.containsMouse
                  ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06))

              Text {
                id: editText
                anchors.centerIn: parent
                text: root.editing ? "\uf00c" : "\uf044"
                color: root.chromeForeground
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
              id: addButton
              visible: root.editing
              anchors.right: editButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              readonly property bool expanded: addHover.containsMouse
              width: expanded ? Math.round(Style.space(118)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: addHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: "+"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  visible: addButton.expanded
                  text: "Add Plugin"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: addHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.catalogOpen = true
              }
            }

            Rectangle {
              id: removePageButton
              visible: root.editing
              enabled: root.sidePanelPages.length > 1
              anchors.right: addButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              readonly property bool expanded: removePageHover.containsMouse
              width: expanded ? Math.round(Style.space(126)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              opacity: enabled ? 1 : 0.42
              color: removePageHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: "\uf1f8"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  visible: removePageButton.expanded
                  text: "Remove page"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: removePageHover
                anchors.fill: parent
                enabled: removePageButton.enabled
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removeCurrentPage()
              }
            }

            Rectangle {
              id: pinButton
              visible: !root.editing && (titleRowHover.hovered || root.pinned)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              color: root.pinned
                ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                : (pinHover.containsMouse
                  ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06))

              Text {
                id: pinText
                anchors.centerIn: parent
                text: "\uf08d"
                color: root.chromeForeground
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

            HoverHandler { id: titleRowHover }

          }

          ListView {
            id: pluginList
            anchors.top: titleRow.bottom
            anchors.topMargin: Style.space(10)
            anchors.bottom: pageCarousel.top
            anchors.bottomMargin: Style.space(8)
            width: parent.width
            orientation: root.verticalEdge ? ListView.Vertical : ListView.Horizontal
            clip: true
            // A plugin without its own Flickable must still let its oversized
            // panel scroll in SidePanel's viewport. Nested Flickables consume the
            // wheel first, so their local scrolling is preserved.
            interactive: root.resizingId === "" && root.draggedId === ""
            spacing: Style.space(7)
            model: root.pluginItems
            // Stack mode keeps every embedded panel instantiated; lifecycle is
            // therefore independent of ListView delegate recycling. Do not
            // bind this to contentHeight: that creates a ListView layout loop.
            cacheBuffer: 100000

            // ListView consumes a normal vertical mouse wheel before the
            // background MouseArea sees it, and on a horizontal Side Panel it
            // turns that wheel into horizontal content scrolling. Intercept
            // Alt+vertical wheel here, before that conversion happens.
            WheelHandler {
              id: altWheelPageNavigation
              objectName: "altWheelPageNavigation"
              acceptedModifiers: Qt.AltModifier
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.movePage(event.angleDelta.y > 0 ? 1 : -1)
                event.accepted = true
              }
            }

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
              width: root.verticalEdge ? pluginList.width : root.panelWidth(pluginRow.plugin)
              height: root.verticalEdge ? (root.editing ? header.height : 0) + content.height : pluginList.height
              z: root.draggedId === pluginId ? 3 : 1

              function focusPanel() {
                if (pageLoader.item && typeof pageLoader.item.sidePanelFocus === "function") pageLoader.item.sidePanelFocus()
                else forceActiveFocus()
              }

              Rectangle {
                id: header
                visible: root.editing
                width: parent.width
                height: Math.round(Style.space(42))
                radius: Style.cornerRadius / 2
                color: pluginRow.expanded
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : (headerDrag.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035))
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, pluginRow.expanded ? 0.22 : 0.09)

                MouseArea {
                  id: headerDrag
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: dragStarted ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  property real pressX: 0
                  property real pressY: 0
                  property bool dragStarted: false

                  onPressed: function(mouse) {
                    pressX = mouse.x
                    pressY = mouse.y
                    dragStarted = false
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    if (!dragStarted && Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) >= 6) {
                      dragStarted = true
                      root.beginDrag(pluginRow, mouse.x, mouse.y)
                    }
                    if (dragStarted) root.updateDrag(pluginRow, mouse.x, mouse.y)
                  }
                  onReleased: function(mouse) {
                    if (dragStarted) root.finishDrag()
                    else root.setExpanded(pluginRow.pluginId)
                  }
                  onCanceled: {
                    if (dragStarted) root.cancelDrag()
                  }
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.pluginIcon(pluginRow.plugin)
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: pluginRow.expanded
                  elide: Text.ElideRight
                }

                Text {
                  id: expansionIndicator
                  anchors.right: deleteButton.left
                  anchors.rightMargin: Style.space(7)
                  anchors.verticalCenter: parent.verticalCenter
                  text: pluginRow.expanded ? "-" : "+"
                  color: root.foreground
                  opacity: 0.62
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
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
                  ? (root.verticalEdge ? root.panelHeight(pluginRow.plugin) : pluginList.height - (root.editing ? header.height : 0))
                  : 0
                clip: true

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: Style.space(5)
                  radius: Style.cornerRadius / 2
                  color: root.transparentBackground
                    ? Color.popups.background
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
                  border.width: 1
                  border.color: pluginRow.index === root.keyboardPluginIndex
                    ? Color.accent
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

                  HoverHandler {
                    id: panelHover
                    onHoveredChanged: {
                      if (hovered) {
                        root.hoveredPanelId = pluginRow.pluginId
                        // Hover makes the panel's key catcher active, matching
                        // Ctrl+Tab navigation between embedded panels.
                        root.keyboardPluginIndex = pluginRow.index
                        pluginRow.focusPanel()
                      } else if (root.hoveredPanelId === pluginRow.pluginId) {
                        root.hoveredPanelId = ""
                      }
                    }
                  }

                  Loader {
                    id: pageLoader
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    active: root.opened && pluginRow.expanded && root.panelUrl(pluginRow.plugin) !== ""
                    source: root.panelSource(pluginRow.plugin)
                    onLoaded: {
                      root.clearPanelError(pluginRow.plugin)
                      root.injectPanel(item, pluginRow.plugin)
                    }
                    onStatusChanged: {
                      if (status === Loader.Error) root.setPanelError(pluginRow.plugin, "The embedded page could not be loaded.")
                    }
                  }

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(36)
                    spacing: Style.space(8)
                    visible: root.panelUrl(pluginRow.plugin) === "" || root.panelLoadFailed(pluginRow.plugin)

                    Text {
                      width: parent.width
                        text: root.panelLoadFailed(pluginRow.plugin)
                          ? root.panelError(pluginRow.plugin)
                          : (root.adaptingId === root.resolvedPluginId(pluginRow.plugin)
                          ? "Embedding the standard Omarchy panel..."
                          : (root.adaptationFailed(pluginRow.plugin) && root.adaptationError(pluginRow.plugin) !== ""
                            ? root.adaptationError(pluginRow.plugin)
                            : (root.canAdapt(pluginRow.plugin)
                              ? "Preparing embedded panel..."
                              : "This plugin does not support embedding in the side panel.")))
                      textFormat: Text.PlainText
                      color: root.foreground
                      opacity: 0.65
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                    }

                  }
                }

                Rectangle {
                  id: resizeHandle
                  visible: root.editing && pluginRow.expanded
                  width: root.verticalEdge ? parent.width : Math.round(Style.space(8))
                  height: root.verticalEdge ? Math.round(Style.space(8)) : parent.height
                  x: root.verticalEdge ? 0 : parent.width - width
                  y: root.verticalEdge ? parent.height - height : 0
                  color: resizeMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : "transparent"

                  MouseArea {
                    id: resizeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: root.verticalEdge ? Qt.SizeVerCursor : Qt.SizeHorCursor
                    onPressed: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.beginResize(pluginRow.plugin, root.verticalEdge ? point.y : point.x)
                    }
                    onPositionChanged: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.updateResize(root.verticalEdge ? point.y : point.x)
                    }
                    onReleased: root.finishResize()
                    onCanceled: root.cancelResize()
                  }
                }
              }
            }

            Rectangle {
              visible: root.draggedId !== "" && root.dropTargetId !== ""
              x: root.verticalEdge ? Style.space(4) : root.dropLineY - width / 2
              y: root.verticalEdge ? root.dropLineY - height / 2 : Style.space(4)
              width: root.verticalEdge ? parent.width - Style.space(8) : Math.max(2, Math.round(Style.space(2)))
              height: root.verticalEdge ? Math.max(2, Math.round(Style.space(2))) : parent.height - Style.space(8)
              radius: height / 2
              color: Color.accent
              z: 3
            }
          }

          Rectangle {
            id: pageCarousel
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: pageDots.width + (root.editing ? pageAdd.width + Style.space(10) : 0)
            height: Math.round(Style.space(24))
            color: "transparent"

            Row {
              id: pageDots
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Repeater {
                model: root.sidePanelPages
                delegate: Rectangle {
                  required property int index
                  width: root.currentPage === index ? Math.round(Style.space(10)) : Math.round(Style.space(7))
                  height: width
                  radius: width / 2
                  color: root.currentPage === index ? Color.accent : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.35)
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectPage(index) }
                }
              }
            }

            Text {
              id: pageAdd
              visible: root.editing
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf067"
              color: root.chromeForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.addPage() }
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
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

        }
      }

      Rectangle {
        id: sidePanelResizeHandle
        visible: root.editing
        width: Math.round(root.verticalEdge ? Style.space(12) : Style.space(48))
        height: Math.round(root.verticalEdge ? Style.space(48) : Style.space(12))
        x: root.verticalEdge
          ? (root.edge === "left" ? parent.width - width : 0)
          : (parent.width - width) / 2
        y: root.verticalEdge
          ? (parent.height - height) / 2
          : (root.edge === "top" ? parent.height - height : 0)
        radius: Math.min(width, height) / 2
        color: sidePanelResizeMouse.containsMouse || root.resizingSidePanel
          ? Style.hoverFillFor(root.chromeForeground, Color.accent)
          : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.18)
        z: 9

        Item {
          anchors.centerIn: parent
          width: root.verticalEdge ? Math.round(Style.space(5)) : Math.round(Style.space(20))
          height: root.verticalEdge ? Math.round(Style.space(20)) : Math.round(Style.space(5))

          Row {
            visible: root.verticalEdge
            anchors.centerIn: parent
            spacing: 1
            Repeater {
              model: 3
              delegate: Rectangle {
                width: 1
                height: Math.round(Style.space(14))
                radius: width / 2
                color: root.chromeForeground
                opacity: 0.52
              }
            }
          }

          Column {
            visible: !root.verticalEdge
            anchors.centerIn: parent
            spacing: 1
            Repeater {
              model: 3
              delegate: Rectangle {
                width: Math.round(Style.space(14))
                height: 1
                radius: height / 2
                color: root.chromeForeground
                opacity: 0.52
              }
            }
          }
        }

        MouseArea {
          id: sidePanelResizeMouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          cursorShape: root.verticalEdge ? Qt.SizeHorCursor : Qt.SizeVerCursor
          onPressed: function(mouse) {
            root.beginSidePanelResize(root.resizePosition(sidePanelResizeHandle, mouse.x, mouse.y))
          }
          onPositionChanged: function(mouse) {
            root.updateSidePanelResize(root.resizePosition(sidePanelResizeHandle, mouse.x, mouse.y))
          }
          onReleased: root.finishSidePanelResize()
          onCanceled: function() { root.resizingSidePanel = false }
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
              width: ListView.view ? ListView.view.width : 0
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
                textFormat: Text.PlainText
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
                text: modelData.enabled ? String(modelData.description) : "Enable and add to side panel"
                textFormat: Text.PlainText
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

    Item {
      id: settingsPage
      anchors.fill: sidePanelBody
      visible: root.settingsOpen
      z: 11

      Column {
        id: settingsContent
        anchors.fill: parent
        anchors.margins: Style.space(14)
        spacing: Style.space(14)

          Item {
            width: parent.width
            height: Math.max(settingsTitle.implicitHeight, settingsClose.height)
            Text {
              id: settingsTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "SIDE PANEL"
              color: root.chromeForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Rectangle {
              id: settingsClose
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(Style.space(28))
              height: width
              radius: height / 2
              color: settingsCloseHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : "transparent"

              Text {
                anchors.centerIn: parent
                text: "\uf00d"
                color: root.chromeForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: settingsCloseHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsOpen = false
              }
            }
          }

          Text {
            text: "EDGE"
            color: root.chromeForeground
            opacity: 0.6
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
                radius: Style.cornerRadius / 2
                color: root.edge === modelData.edge
                  ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.icon
                    color: root.chromeForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: root.chromeForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.persistSidePanelSetting("edge", modelData.edge)
                }
              }
            }
          }

          Text {
            text: "DISPLAY MODE"
            color: root.chromeForeground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            id: displayModeOptions
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: [
                { mode: "overlay", label: "Overlay" },
                { mode: "reserve", label: "Push screen" }
              ]
              delegate: Rectangle {
                required property var modelData
                width: Math.floor((displayModeOptions.width - displayModeOptions.spacing) / 2)
                height: Math.round(Style.space(42))
                radius: Style.cornerRadius / 2
                color: root.layoutMode === modelData.mode
                  ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.persistSidePanelSetting("layoutMode", modelData.mode)
                }
              }
            }
          }

          Text {
            text: "EDGE REVEAL"
            color: root.chromeForeground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            id: edgeRevealSettings
            objectName: "edgeRevealSettings"
            width: parent.width
            height: Math.max(edgeRevealLabel.implicitHeight, edgeRevealToggle.implicitHeight)

            Text {
              id: edgeRevealLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Reveal at screen edge"
              color: root.chromeForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            ToggleSwitch {
              id: edgeRevealToggle
              objectName: "edgeRevealEnabledControl"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.edgeRevealConfigured
              foreground: root.chromeForeground
              onToggled: root.persistSidePanelSetting("edgeRevealEnabled", !root.edgeRevealConfigured)
            }
          }

          Row {
            width: parent.width
            height: Math.max(edgeRevealDelayLabel.implicitHeight, edgeRevealDelayControl.implicitHeight)

            Text {
              id: edgeRevealDelayLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Delay"
              color: root.chromeForeground
              opacity: root.edgeRevealConfigured ? 1 : 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: edgeRevealDelayControl.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "ms"
              color: root.chromeForeground
              opacity: root.edgeRevealConfigured ? 0.7 : 0.35
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            NumberField {
              id: edgeRevealDelayControl
              objectName: "edgeRevealDelayControl"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              value: root.edgeRevealDelayMs
              from: 0
              to: 2000
              stepSize: 50
              foreground: root.chromeForeground
              enabled: root.edgeRevealConfigured
              opacity: enabled ? 1 : 0.5
              onModified: function(value) { root.persistSidePanelSetting("edgeRevealDelayMs", value) }
            }
          }
      }
    }
  }
}
