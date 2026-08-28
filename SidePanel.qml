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
  property bool shortcutsOpen: false
  property bool renamingPage: false
  property string expandedId: ""
  property string draggedId: ""
  property real dragWidth: 0
  property string resizingId: ""
  property string resizingAxis: ""
  property real resizeStartExtent: 0
  property real resizeStartPosition: 0
  property real resizePreviewExtent: 0
  property string dropTargetId: ""
  property bool dropAfter: false
  property real dropLineY: 0
  property var activePanels: []
  // Layer-shell surfaces do not report whether they own focus. Keep the
  // ordinary window that was focused when SidePanel opened instead.
  property var openedToplevel: null
  property bool focusDismissalArmed: false
  property var sidePanelPages: []
  property var warmedPanelIds: []
  property var warmupQueue: []
  property var currentPluginList: null
  property int currentPage: 0
  readonly property var pluginItems: sidePanelPages.length > 0 && sidePanelPages[currentPage]
    ? sidePanelPages[currentPage].items : []
  readonly property int sidePanelItemCount: countSidePanelItems()
  readonly property bool sidePanelItemLimitReached: sidePanelItemCount >= SidePanelModel.MAX_TOTAL_ITEMS
  readonly property bool sidePanelPageItemLimitReached: pluginItems.length >= SidePanelModel.MAX_ITEMS_PER_PAGE
  property var adaptedUrls: ({})
  property string adaptingId: ""
  property string adaptationTimedOutId: ""
  property int adaptationRegistryRevision: -1
  property var adaptationErrors: ({})
  property var panelErrors: ({})
  property int panelEpoch: 0
  property bool resizingSidePanel: false
  property bool panelResizeMode: false
  property string sidePanelResizeAxis: "edge"
  property real sidePanelResizeStart: 0
  property real sidePanelResizeStartExtent: 0
  property real sidePanelResizePreview: 0
  property int keyboardPluginIndex: -1
  property string hoveredPanelId: ""
  property var sidePanelState: ({})
  property int stateRevision: 0
  property int stateReadRevision: 0
  property bool stateReadTimedOut: false
  property string stateSaveError: ""
  property string pendingStateText: ""
  property string stateWritingText: ""
  property bool stateWriteInProgress: false
  property int stateSaveRetryCount: 0
  property real configurationRevision: 0
  property int transparentForegroundGeneration: 0
  property int transparentForegroundRequestGeneration: -1
  property bool transparentForegroundDirty: false

  readonly property int sidePanelWidth: Math.round(Style.space(480))
  readonly property int sidePanelHeight: Math.round(Style.space(420))
  readonly property string effectiveEdge: {
    var value = String(setting("edge", edge)).toLowerCase()
    return ["left", "right", "top", "bottom"].indexOf(value) >= 0 ? value : edge
  }
  readonly property string effectiveLayoutMode: String(setting("layoutMode", layoutMode)).toLowerCase() === "reserve"
    ? "reserve" : "overlay"
  readonly property bool verticalEdge: effectiveEdge === "left" || effectiveEdge === "right"
  readonly property bool reservesSpace: effectiveLayoutMode === "reserve"
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
  readonly property real sidePanelExtent: resizingSidePanel && sidePanelResizeAxis === "edge"
    ? boundedSidePanelExtent(sidePanelResizePreview, "edge")
    : boundedSidePanelExtent(configuredExtent, "edge")
  readonly property real configuredOverlayCrossExtent: SidePanelModel.boundedEdgeSize(setting("overlayCrossSize", 0), 0)
  readonly property real overlayCrossExtent: {
    if (reservesSpace) return 0
    var extent = resizingSidePanel && sidePanelResizeAxis === "cross"
      ? sidePanelResizePreview : configuredOverlayCrossExtent
    // Zero is the persisted value for filling the whole cross axis.
    return extent > 0 ? boundedSidePanelExtent(extent, "cross") : 0
  }
  readonly property string overlayAlignment: {
    var value = String(setting("overlayAlignment", "center")).toLowerCase()
    var options = verticalEdge ? ["top", "center", "bottom"] : ["left", "center", "right"]
    return options.indexOf(value) >= 0 ? value : "center"
  }
  readonly property real sidePanelInsetTop: reservesSpace ? 0
    : overlayGap + (barPosition === "top" ? barInset : 0)
  readonly property real sidePanelInsetRight: reservesSpace ? 0
    : overlayGap + (barPosition === "right" ? barInset : 0)
  readonly property real sidePanelInsetBottom: reservesSpace ? 0
    : overlayGap + (barPosition === "bottom" ? barInset : 0)
  readonly property real sidePanelInsetLeft: reservesSpace ? 0
    : overlayGap + (barPosition === "left" ? barInset : 0)
  readonly property real sidePanelAvailableWidth: Math.max(0, surface.width - sidePanelInsetLeft - sidePanelInsetRight)
  readonly property real sidePanelAvailableHeight: Math.max(0, surface.height - sidePanelInsetTop - sidePanelInsetBottom)
  readonly property real sidePanelResizeHitSlop: settingsOpen && panelResizeMode
    ? Math.round(Style.space(16)) : 0

  function sidePanelResizeMaximum(axis) {
    // In Reserve Space mode the surface contracts together with the Side Panel,
    // so use the physical screen for the edge-axis bound.
    if (axis === "edge" && reservesSpace && sidePanelScreen)
      return Math.min(SidePanelModel.MAX_EDGE_SIZE, verticalEdge ? sidePanelScreen.width : sidePanelScreen.height)
    var available = axis === "edge"
      ? (verticalEdge ? sidePanelAvailableWidth : sidePanelAvailableHeight)
      : (verticalEdge ? sidePanelAvailableHeight : sidePanelAvailableWidth)
    return available > 0 ? Math.min(SidePanelModel.MAX_EDGE_SIZE, available) : SidePanelModel.MAX_EDGE_SIZE
  }

  function sidePanelResizeMinimum(axis) {
    return Math.min(Style.space(260), sidePanelResizeMaximum(axis))
  }

  function boundedSidePanelExtent(value, axis) {
    return SidePanelModel.boundedExtent(
      value, sidePanelResizeMinimum(axis), sidePanelResizeMaximum(axis)
    )
  }

  function overlayCrossOffset(available) {
    if (overlayCrossExtent <= 0) return 0
    var remaining = Math.max(0, available - Math.min(overlayCrossExtent, available))
    if (overlayAlignment === "left" || overlayAlignment === "top") return 0
    if (overlayAlignment === "right" || overlayAlignment === "bottom") return remaining
    return remaining / 2
  }
  // The layer surface itself maps on open. Animate its content from the chosen
  // Edge so opening reads as a quick slide rather than a fade-in.
  property real panelRevealProgress: 0
  readonly property real panelRevealOffsetX: verticalEdge
    ? (effectiveEdge === "left" ? -(1 - panelRevealProgress) * sidePanelExtent : (1 - panelRevealProgress) * sidePanelExtent)
    : 0
  readonly property real panelRevealOffsetY: !verticalEdge
    ? (effectiveEdge === "top" ? -(1 - panelRevealProgress) * sidePanelExtent : (1 - panelRevealProgress) * sidePanelExtent)
    : 0
  readonly property color foreground: Color.popups.text
  readonly property color transparentTextForeground: Color.bar.text
  readonly property color transparentContrastForeground: Color.background
  property color transparentForeground: transparentTextForeground
  readonly property color chromeForeground: transparentBackground ? transparentForeground : foreground
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  // The BarWidget's QsWindow is briefly unavailable while the shell reloads.
  // A PanelWindow without an explicit screen falls back to its own current
  // size, which creates a resize binding loop in Reserve Space mode.
  readonly property var sidePanelScreen: anchorWindow && anchorWindow.screen
    ? anchorWindow.screen
    : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
  readonly property string cacheBase: absoluteXdgBase("XDG_CACHE_HOME", "/.cache")
  readonly property string stateBase: absoluteXdgBase("XDG_STATE_HOME", "/.local/state")
  property string cacheRoot: cacheBase === "" ? "" : cacheBase + "/omarchy-side-panel"
  property string statePath: stateBase === "" ? "" : stateBase + "/omarchy/gshulga.side-panel.json"
  readonly property int pluginRegistryRevision: bar && bar.shell && bar.shell.pluginRegistry
    ? Number(bar.shell.pluginRegistry.registryRevision || 0) : 0
  readonly property var availablePlugins: discoverAvailablePlugins()

  function absoluteXdgBase(environmentName, homeSuffix) {
    var configured = String(Quickshell.env(environmentName) || "")
    if (configured.charAt(0) === "/") return configured.replace(/\/+$/, "")
    var home = String(Quickshell.env("HOME") || "")
    return home.charAt(0) === "/" ? home.replace(/\/+$/, "") + homeSuffix : ""
  }

  function setting(name, fallback) {
    var stateIsNewer = stateConfigurationRevision(sidePanelState) > settingsConfigurationRevision()
    var source = stateIsNewer ? sidePanelState : settings
    var value = source ? source[name] : undefined
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
    transparentForegroundGeneration += 1
    if (!transparentBackground) {
      transparentForeground = transparentTextForeground
      return
    }
    if (transparentForegroundProc.running) transparentForegroundDirty = true
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!transparentBackground) return
    if (transparentForegroundProc.running) {
      transparentForegroundDirty = true
      return
    }
    transparentForegroundDirty = false
    transparentForegroundRequestGeneration = transparentForegroundGeneration
    // Match Bar's wallpaper-sampled contrast choice for the side panel's own edge.
    transparentForegroundProc.command = [
      "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", "5s",
      "/usr/share/omarchy/bin/omarchy-bar-text-color",
      effectiveEdge,
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

  function settingsConfigurationRevision() {
    return SidePanelModel.normalizedRevision(settings ? settings.sidePanelRevision : 0)
  }

  function stateConfigurationRevision(state) {
    return SidePanelModel.normalizedRevision(state ? state.revision : 0)
  }

  function nextConfigurationRevision() {
    configurationRevision = Math.max(configurationRevision + 1, Date.now())
    return configurationRevision
  }

  function pagesFromSettings() {
    var configured = settings && ((Array.isArray(settings.pages) && settings.pages.length > 0)
      || Array.isArray(settings.plugins))
    var savedStateIsNewer = stateConfigurationRevision(sidePanelState) > settingsConfigurationRevision()
    var source = savedStateIsNewer || !configured ? sidePanelState : settings
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
    var revision = nextConfigurationRevision()
    persistSidePanelState(null, revision)
    var entry = SidePanelModel.persistedEntry(settings, nextPages)
    entry.sidePanelRevision = revision
    try {
      if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
        bar.shell.updateEntryInline("gshulga.side-panel", entry)
    } catch (error) {
      console.warn("SidePanel: cannot persist pages:", error)
    }
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
    currentPage = index
    enqueuePageWarmup(index, true)
    advancePanelWarmup()
    keyboardPluginIndex = -1
    expandedId = ""
    renamingPage = false
    persistSidePanelState()
  }

  function countSidePanelItems() {
    var count = 0
    for (var pageIndex = 0; pageIndex < sidePanelPages.length; pageIndex++)
      count += (sidePanelPages[pageIndex].items || []).length
    return count
  }

  function panelIsWarmed(item) {
    return warmedPanelIds.indexOf(resolvedPluginId(item)) >= 0
  }

  function pageIsLoaded(index) {
    var page = sidePanelPages[index]
    if (!page) return false
    var items = page.items || []
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++)
      if (!panelIsWarmed(items[itemIndex])) return false
    return true
  }

  function itemForPanelId(id) {
    for (var pageIndex = 0; pageIndex < sidePanelPages.length; pageIndex++) {
      var items = sidePanelPages[pageIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++)
        if (resolvedPluginId(items[itemIndex]) === id) return items[itemIndex]
    }
    return null
  }

  function enqueuePageWarmup(index, prioritize) {
    var page = sidePanelPages[index]
    if (!opened || !page) return
    var requested = []
    var items = page.items || []
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
      var id = resolvedPluginId(items[itemIndex])
      if (!panelIsWarmed(items[itemIndex]) && requested.indexOf(id) < 0)
        requested.push(id)
    }
    var remaining = []
    for (var queueIndex = 0; queueIndex < warmupQueue.length; queueIndex++)
      if (requested.indexOf(warmupQueue[queueIndex]) < 0) remaining.push(warmupQueue[queueIndex])
    warmupQueue = prioritize ? requested.concat(remaining) : remaining.concat(requested)
    if (warmupQueue.length > 0) warmupTimer.restart()
  }

  function enqueueAllPanelWarmups() {
    enqueuePageWarmup(currentPage, true)
    for (var pageIndex = 0; pageIndex < sidePanelPages.length; pageIndex++)
      if (pageIndex !== currentPage) enqueuePageWarmup(pageIndex, false)
    advancePanelWarmup()
  }

  function resetPanelWarmup() {
    warmupTimer.stop()
    warmedPanelIds = []
    warmupQueue = []
  }

  function markPanelWarmed(id) {
    if (warmedPanelIds.indexOf(id) >= 0) return
    warmedPanelIds = warmedPanelIds.concat([id])
  }

  function advancePanelWarmup() {
    if (!opened) {
      warmupTimer.stop()
      return
    }
    while (warmupQueue.length > 0) {
      var id = warmupQueue[0]
      warmupQueue = warmupQueue.slice(1)
      var item = itemForPanelId(id)
      if (!item || panelIsWarmed(item)) continue
      if (panelUrl(item) === "") {
        if (canAdapt(item) && !adaptationFailed(item)) {
          warmupQueue = [id].concat(warmupQueue)
          warmupTimer.stop()
          adaptPreferredPanels()
          return
        }
        markPanelWarmed(id)
        continue
      }
      markPanelWarmed(id)
      return
    }
    warmupTimer.stop()
  }

  function movePage(delta) {
    if (sidePanelPages.length < 2) return
    selectPage((currentPage + delta + sidePanelPages.length) % sidePanelPages.length)
  }

  function addPage() {
    if (sidePanelPages.length >= SidePanelModel.MAX_PAGES) return
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
    if (currentPluginList) currentPluginList.positionViewAtIndex(keyboardPluginIndex, ListView.Contain)
  }

  function focusKeyboardPlugin(delta) {
    if (editing) {
      focusEditPlugin(delta)
      return
    }
    moveKeyboardPlugin(delta)
    Qt.callLater(function() {
      var row = currentPluginList ? currentPluginList.itemAtIndex(keyboardPluginIndex) : null
      if (row && typeof row.focusPanel === "function") row.focusPanel()
    })
  }

  function ensureKeyboardPluginFocus() {
    if (pluginItems.length === 0) {
      keyboardPluginIndex = -1
      return false
    }
    if (keyboardPluginIndex < 0 || keyboardPluginIndex >= pluginItems.length)
      keyboardPluginIndex = 0
    return true
  }

  function focusEditPlugin(delta) {
    if (!editing || !ensureKeyboardPluginFocus()) return
    if (delta !== 0)
      keyboardPluginIndex = (keyboardPluginIndex + delta + pluginItems.length) % pluginItems.length
    var item = pluginItems[keyboardPluginIndex]
    if (!item) return
    setExpanded(resolvedPluginId(item))
    if (currentPluginList) currentPluginList.positionViewAtIndex(keyboardPluginIndex, ListView.Contain)
  }

  function focusedPlugin() {
    return ensureKeyboardPluginFocus() ? pluginItems[keyboardPluginIndex] : null
  }

  function toggleFocusedPlugin() {
    if (!editing) return
    var item = focusedPlugin()
    if (item) setExpanded(resolvedPluginId(item))
  }

  function removeFocusedPlugin() {
    if (!editing) return
    var item = focusedPlugin()
    if (!item) return
    var index = keyboardPluginIndex
    removePlugin(resolvedPluginId(item))
    if (!ensureKeyboardPluginFocus()) return
    keyboardPluginIndex = Math.min(index, pluginItems.length - 1)
    setExpanded(resolvedPluginId(pluginItems[keyboardPluginIndex]))
  }

  function resizeFocusedPlugin(delta, axis) {
    if (!editing || delta === 0) return
    var item = focusedPlugin()
    if (!item) return
    var index = itemIndex(resolvedPluginId(item))
    if (index < 0) return
    var next = copyItems(pluginItems)
    var step = Math.round(Style.space(20))
    var resizeAxis = axis || (verticalEdge ? "height" : "width")
    if (resizeAxis === "height")
      next[index].height = SidePanelModel.resizeHeight(panelHeight(item), 0, delta * step, 5, 5)
    else
      next[index].width = SidePanelModel.resizeHeight(panelWidth(item), 0, delta * step, 5, 5)
    persistItems(next)
  }

  function moveFocusedPlugin(delta) {
    if (!editing || delta === 0) return
    var item = focusedPlugin()
    if (!item) return
    var sourceIndex = keyboardPluginIndex
    var targetIndex = sourceIndex + delta
    if (targetIndex < 0 || targetIndex >= pluginItems.length) return
    moveItem(resolvedPluginId(item), resolvedPluginId(pluginItems[targetIndex]), delta > 0)
    keyboardPluginIndex = targetIndex
  }

  function scrollPluginList(deltaX, deltaY) {
    if (hoveredPanelId !== "") return
    if (!currentPluginList) return
    var delta = verticalEdge ? deltaX : deltaY
    if (delta === 0) return
    if (verticalEdge) {
      var maxY = Math.max(0, currentPluginList.contentHeight - currentPluginList.height)
      currentPluginList.contentY = Math.max(0, Math.min(maxY, currentPluginList.contentY - delta))
    } else {
      var maxX = Math.max(0, currentPluginList.contentWidth - currentPluginList.width)
      currentPluginList.contentX = Math.max(0, Math.min(maxX, currentPluginList.contentX - delta))
    }
  }

  function handlePanelWheel(modifiers, deltaX, deltaY) {
    if (modifiers & Qt.AltModifier) {
      // Treat either wheel axis as page navigation. Prefer the dominant axis
      // for diagonal input so one gesture produces only one page change.
      var pageDelta = Math.abs(deltaX) > Math.abs(deltaY) ? deltaX : deltaY
      if (pageDelta > 0) movePage(1)
      else if (pageDelta < 0) movePage(-1)
      return
    }
    scrollPluginList(deltaX, deltaY)
  }

  function persistSidePanelSetting(name, value) {
    if (name === "edgeSize") {
      value = SidePanelModel.boundedEdgeSize(value, verticalEdge ? sidePanelWidth : sidePanelHeight)
      value = boundedSidePanelExtent(value, "edge")
    } else if (name === "overlayCrossSize") {
      value = SidePanelModel.boundedEdgeSize(value, 0)
      if (value > 0) value = boundedSidePanelExtent(value, "cross")
    }
    var entry = SidePanelModel.persistedEntry(settings, sidePanelPages)
    entry[name] = value
    var overrides = ({})
    overrides[name] = value
    var revision = nextConfigurationRevision()
    persistSidePanelState(overrides, revision)
    entry.sidePanelRevision = revision
    try {
      if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
        bar.shell.updateEntryInline("gshulga.side-panel", entry)
    } catch (error) {
      console.warn("SidePanel: cannot persist setting " + name + ":", error)
    }
  }

  function persistSidePanelState(overrides, requestedConfigurationRevision) {
    var state = {
      version: 1,
      pages: copyPages(sidePanelPages),
      currentPage: currentPage
    }
    var revision = SidePanelModel.normalizedRevision(
      requestedConfigurationRevision === undefined || requestedConfigurationRevision === null
        ? configurationRevision : requestedConfigurationRevision
    )
    if (revision > 0) state.revision = revision
    var requestedEdge = overrides && overrides.edge !== undefined ? overrides.edge : effectiveEdge
    var requestedMode = overrides && overrides.layoutMode !== undefined ? overrides.layoutMode : effectiveLayoutMode
    var requestedAlignment = overrides && overrides.overlayAlignment !== undefined
      ? overrides.overlayAlignment : overlayAlignment
    if (["left", "right", "top", "bottom"].indexOf(requestedEdge) >= 0) state.edge = requestedEdge
    if (["overlay", "reserve"].indexOf(requestedMode) >= 0) state.layoutMode = requestedMode
    if (["left", "center", "right", "top", "bottom"].indexOf(requestedAlignment) >= 0)
      state.overlayAlignment = requestedAlignment
    var requestedRevealEnabled = overrides && overrides.edgeRevealEnabled !== undefined
      ? overrides.edgeRevealEnabled : setting("edgeRevealEnabled", true)
    if (typeof requestedRevealEnabled === "boolean") state.edgeRevealEnabled = requestedRevealEnabled
    var requestedRevealDelay = overrides && overrides.edgeRevealDelayMs !== undefined
      ? overrides.edgeRevealDelayMs : setting("edgeRevealDelayMs", 250)
    state.edgeRevealDelayMs = SidePanelModel.boundedInteger(requestedRevealDelay, 250, 0, 2000)
    var requestedEdgeSize = overrides && overrides.edgeSize !== undefined
      ? overrides.edgeSize : setting("edgeSize", 0)
    requestedEdgeSize = SidePanelModel.normalizedExtent(requestedEdgeSize, SidePanelModel.MAX_EDGE_SIZE)
    if (requestedEdgeSize > 0) state.edgeSize = requestedEdgeSize
    var requestedCrossSize = overrides && overrides.overlayCrossSize !== undefined
      ? overrides.overlayCrossSize : setting("overlayCrossSize", 0)
    state.overlayCrossSize = SidePanelModel.normalizedExtent(requestedCrossSize, SidePanelModel.MAX_EDGE_SIZE)
    var serialized = ""
    try {
      serialized = JSON.stringify(state, null, 2) + "\n"
    } catch (error) {
      console.warn("SidePanel: cannot serialize saved state:", error)
      return
    }
    if (SidePanelModel.utf8ByteLength(serialized) > SidePanelModel.MAX_STATE_BYTES) {
      console.warn("SidePanel: refusing to save state larger than the size limit")
      return
    }
    stateRevision += 1
    sidePanelState = state
    if (statePath !== "") {
      pendingStateText = serialized
      stateSaveRetryCount = 0
      if (!stateWriteInProgress) stateSaveTimer.restart()
    }
  }

  function flushStateWrite() {
    if (statePath === "" || stateWriteInProgress || pendingStateText === "") return
    stateWritingText = pendingStateText
    pendingStateText = ""
    stateWriteInProgress = true
    sidePanelStateFile.setText(stateWritingText)
  }

  function loadSidePanelState(raw, requestedRevision) {
    if (requestedRevision !== stateRevision) return
    var state = SidePanelModel.parseState(raw, defaultPluginItems(), function(item) {
      return root.resolvedPluginId(item)
    })
    if (!state) {
      console.warn("SidePanel: cannot load saved state")
      return
    }
    var savedRevision = stateConfigurationRevision(state)
    var configuredRevision = settingsConfigurationRevision()
    var recoverSavedState = savedRevision > configuredRevision
    var configuredPages = settings && ((Array.isArray(settings.pages) && settings.pages.length > 0)
      || Array.isArray(settings.plugins))
    var nextPages = recoverSavedState || !configuredPages ? state.pages : SidePanelModel.pagesFromSettings(
      settings, defaultPluginItems(), function(item) { return root.resolvedPluginId(item) }
    )
    deactivateActivePanels("state-load")
    resetPanelWarmup()
    currentPluginList = null
    sidePanelState = state
    configurationRevision = Math.max(configurationRevision, savedRevision, configuredRevision)
    sidePanelPages = nextPages
    currentPage = Math.max(0, Math.min(nextPages.length - 1, state.currentPage))
    if (opened) {
      enqueueAllPanelWarmups()
      adaptPreferredPanels()
    }
    if (recoverSavedState) repairShellSettingsFromState(state)
  }

  function repairShellSettingsFromState(state) {
    var entry = SidePanelModel.persistedEntry(settings, state.pages)
    var names = [
      "edge", "edgeSize", "overlayCrossSize", "overlayAlignment", "layoutMode",
      "edgeRevealEnabled", "edgeRevealDelayMs"
    ]
    for (var index = 0; index < names.length; index++)
      if (state[names[index]] !== undefined) entry[names[index]] = state[names[index]]
    entry.sidePanelRevision = stateConfigurationRevision(state)
    try {
      if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
        bar.shell.updateEntryInline("gshulga.side-panel", entry)
    } catch (error) {
      console.warn("SidePanel: cannot recover newer saved state into shell settings:", error)
    }
  }

  function loadSavedSidePanelState() {
    if (statePath === "" || stateReader.running) return
    stateReadRevision = stateRevision
    stateReadTimedOut = false
    stateReader.command = [
      "/usr/bin/python3", "-I", pluginDir + "/bin/omarchy-side-panel-read-state",
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
    // Layer surfaces can move while their reserved extent changes. Global
    // coordinates stay fixed across separate QML windows in both display modes.
    var point = handle.mapToGlobal(x, y)
    return verticalEdge ? point.x : point.y
  }

  function beginSidePanelResize(axis, position) {
    // Snapshot the visible extent before enabling the preview. A zero preview
    // means "fill the available cross axis", so enabling it first made the
    // cross-axis handle jump to fullscreen and the edge handle start at zero.
    var startExtent = axis === "edge" ? sidePanelExtent
      : (verticalEdge ? sidePanelBody.height : sidePanelBody.width)
    resizingSidePanel = true
    sidePanelResizeAxis = axis
    sidePanelResizeStart = position
    sidePanelResizeStartExtent = startExtent
    sidePanelResizePreview = startExtent
  }

  function updateSidePanelResize(position) {
    if (!resizingSidePanel) return
    var delta = position - sidePanelResizeStart
    if (sidePanelResizeAxis === "edge" && (effectiveEdge === "right" || effectiveEdge === "bottom")) delta = -delta
    if (sidePanelResizeAxis === "cross"
        && ((verticalEdge && overlayAlignment === "bottom")
          || (!verticalEdge && overlayAlignment === "right"))) delta = -delta
    var axis = sidePanelResizeAxis
    var snappedExtent = Math.round((sidePanelResizeStartExtent + delta) / 5) * 5
    sidePanelResizePreview = boundedSidePanelExtent(snappedExtent, axis)
  }

  function finishSidePanelResize() {
    if (!resizingSidePanel) return
    persistSidePanelSetting(sidePanelResizeAxis === "edge" ? "edgeSize" : "overlayCrossSize", sidePanelResizePreview)
    resizingSidePanel = false
    sidePanelResizePreview = 0
  }

  function cancelSidePanelResize() {
    resizingSidePanel = false
    sidePanelResizePreview = 0
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
    var index = itemIndex(id)
    if (index >= 0) keyboardPluginIndex = index
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
    keyboardPluginIndex = value && pluginItems.length > 0 ? 0 : -1
    expandedId = keyboardPluginIndex >= 0 ? resolvedPluginId(pluginItems[keyboardPluginIndex]) : ""
    catalogOpen = false
    settingsOpen = false
    shortcutsOpen = false
    panelEpoch += 1
  }

  function panelHeight(item) {
    if (item && resizingId === item.id && resizingAxis === "height") return resizePreviewExtent
    var height = Number(item ? item.height : 0)
    if (!height) height = Style.space(280)
    return Math.max(5, Math.round(height))
  }

  function panelWidth(item) {
    if (item && resizingId === item.id && resizingAxis === "width") return resizePreviewExtent
    var width = Number(item ? item.width : 0)
    if (!width) width = Style.space(360)
    return Math.max(5, Math.round(width))
  }

  function beginResize(item, axis, position) {
    resizeStartExtent = axis === "height" ? panelHeight(item) : panelWidth(item)
    resizingId = item.id
    resizingAxis = axis
    resizeStartPosition = position
    resizePreviewExtent = resizeStartExtent
  }

  function updateResize(position) {
    if (resizingId === "") return
    var adjustedPosition = position
    if ((resizingAxis === "width" && verticalEdge && effectiveEdge === "right")
        || (resizingAxis === "height" && !verticalEdge && effectiveEdge === "bottom"))
      adjustedPosition = resizeStartPosition - (position - resizeStartPosition)
    resizePreviewExtent = SidePanelModel.resizeHeight(resizeStartExtent, resizeStartPosition, adjustedPosition, 5, 5)
  }

  function finishResize() {
    var index = itemIndex(resizingId)
    if (index >= 0) {
      var next = copyItems(pluginItems)
      next[index][resizingAxis] = resizePreviewExtent
      persistItems(next)
    }
    resizingId = ""
    resizingAxis = ""
  }

  function cancelResize() {
    resizingId = ""
    resizingAxis = ""
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
    if (!currentPluginList) return
    draggedId = row.pluginId
    var point = row.mapToItem(keyCatcher, x, y)
    dragWidth = row.width
    dragPreview.x = point.x - dragWidth / 2
    dragPreview.y = point.y - dragPreview.height / 2
    var listPoint = keyCatcher.mapToItem(currentPluginList, point.x, point.y)
    updateDropTarget(listPoint.x, listPoint.y)
  }

  function updateDrag(row, x, y) {
    if (draggedId !== row.pluginId) return
    if (!currentPluginList) return
    var point = row.mapToItem(keyCatcher, x, y)
    dragPreview.x = point.x - dragWidth / 2
    dragPreview.y = point.y - dragPreview.height / 2
    var listPoint = keyCatcher.mapToItem(currentPluginList, point.x, point.y)
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
    if (!currentPluginList) return
    var position = verticalEdge ? y : x
    var previousRow = null
    for (var i = 0; i < pluginItems.length; i++) {
      var row = currentPluginList.itemAtIndex(i)
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
    if (id === "" || hasPlugin(id) || sidePanelItemLimitReached || sidePanelPageItemLimitReached
        || id === "gshulga.side-panel") return
    var manifest = pluginFor(id)
    if (!manifest) return
    if (!enablePluginForSidePanel(id, manifest)) return
    var next = copyItems(pluginItems)
    next.push({
      id: id,
      label: String(manifest.name || id),
      icon: ""
    })
    persistItems(next)
    catalogOpen = false
    setExpanded(id)
    enqueuePageWarmup(currentPage, true)
    adaptPreferredPanels()
  }

  function enablePluginForSidePanel(id, manifest) {
    if (pluginEnabled({ id: id })) return true
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return false
    try {
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
      return true
    } catch (error) {
      console.warn("SidePanel: cannot enable " + id + ":", error)
      return false
    }
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
    var revision = pluginRegistryRevision
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
    if (!item || !pluginEnabled(item) || !pluginFor(item.id)) return ""
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
    return !!(cacheRoot !== "" && pluginEnabled(item) && manifest && manifest.entryPoints
      && manifest.entryPoints.barWidget && manifest.__sourceDir)
  }

  function adaptStandardPanel(item) {
    if (!item || !canAdapt(item) || adaptingId !== "" || adapter.running) return
    var id = resolvedPluginId(item)
    var manifest = pluginFor(item.id)
    adaptingId = id
    adaptationTimedOutId = ""
    adaptationRegistryRevision = pluginRegistryRevision
    clearAdaptationError(id)
    adapter.command = [
      "/usr/bin/python3", "-I", pluginDir + "/lib/omarchy_side_panel_adapter.py", "--",
      String(manifest.__sourceDir),
      String(manifest.entryPoints.barWidget),
      cacheRoot,
      id,
      pluginDir
    ]
    adapter.running = true
    adapterTimeout.restart()
  }

  function adaptPreferredPanels() {
    if (!opened || adaptingId !== "" || adapter.running) return
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

  function adapterUrlIsSafe(url) {
    if (cacheRoot === "" || url.indexOf("\n") >= 0 || url.indexOf("\r") >= 0
        || url.indexOf("file://") !== 0) return false
    try {
      var path = decodeURIComponent(url.slice("file://".length))
      return path.indexOf(cacheRoot + "/") === 0 && path.indexOf("\0") < 0
        && path.indexOf("/../") < 0 && !path.endsWith("/..")
    } catch (error) {
      return false
    }
  }

  function resumePanelPreparation() {
    if (!opened) return
    advancePanelWarmup()
    adaptPreferredPanels()
    if (warmupQueue.length > 0 && adaptingId === "") warmupTimer.restart()
  }

  function handlePluginRegistryChange() {
    deactivateActivePanels("plugin-registry-change")
    resetPanelWarmup()
    adaptedUrls = ({})
    adaptationErrors = ({})
    panelErrors = ({})
    panelEpoch += 1
    if (opened) enqueueAllPanelWarmups()
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
    var service = null
    try {
      service = root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
        ? root.bar.shell.serviceFor(id) : null
    } catch (error) {
      console.warn("SidePanel: cannot resolve service for " + id + ":", error)
    }
    var context = {
      sidePanel: root,
      sidePanelItem: item || ({}),
      bar: root.bar,
      pluginId: id,
      settings: root.nativeSettings(id),
      service: service
    }
    try {
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
    } catch (error) {
      setPanelError(item, "The embedded page failed during initialization.")
      console.warn("SidePanel: plugin " + id + " initialization failed:", error)
      return
    }
    var nextPanels = activePanels.slice()
    if (nextPanels.indexOf(page) < 0) nextPanels.push(page)
    activePanels = nextPanels
    var activationFailed = false
    if (opened && typeof page.sidePanelActivate === "function"
        && !invokePanelMethod(page, "sidePanelActivate", [context], id))
      activationFailed = true
    else if (opened && typeof page.sidePanelActivate !== "function" && typeof page.open === "function"
        && !invokePanelMethod(page, "open", [], id))
      activationFailed = true
    if (activationFailed) {
      removeActivePanel(page)
      setPanelError(item, "The embedded page failed while opening.")
    }
  }

  function removeActivePanel(page) {
    var nextPanels = []
    for (var index = 0; index < activePanels.length; index++)
      if (activePanels[index] && activePanels[index] !== page) nextPanels.push(activePanels[index])
    activePanels = nextPanels
  }

  function invokePanelMethod(page, name, args, id) {
    try {
      page[name].apply(page, args || [])
      return true
    } catch (error) {
      console.warn("SidePanel: plugin " + String(id || "") + " " + name + " failed:", error)
      return false
    }
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
    try {
      if (!bar || typeof bar.moduleWidgets !== "function") return ({})
      var widgets = bar.moduleWidgets(id)
      return widgets.length > 0 && widgets[0] && widgets[0].settings ? widgets[0].settings : ({})
    } catch (error) {
      console.warn("SidePanel: cannot resolve settings for " + id + ":", error)
      return ({})
    }
  }

  function deactivateActivePanels(reason) {
    var panels = activePanels.slice()
    activePanels = []
    var previousSuppression = suppressPanelClose
    suppressPanelClose = true
    try {
      for (var i = 0; i < panels.length; i++) {
        var panel = panels[i]
        if (!panel) continue
        try {
          if ("sidePanelHost" in panel && typeof panel.close === "function")
            invokePanelMethod(panel, "close", [], "")
          else if (typeof panel.sidePanelDeactivate === "function")
            invokePanelMethod(panel, "sidePanelDeactivate", [reason || "sidePanel"], "")
          else if (typeof panel.close === "function") invokePanelMethod(panel, "close", [], "")
        } catch (error) {
          console.warn("SidePanel: cannot inspect plugin during deactivation:", error)
        }
      }
    } finally {
      suppressPanelClose = previousSuppression
    }
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

  function armFocusDismissal() {
    focusDismissalArmed = false
    openedToplevel = ToplevelManager.activeToplevel
    focusDismissalTimer.restart()
  }

  function shouldDismissForToplevelChange(nextToplevel) {
    return opened && focusDismissalArmed && !pinned && nextToplevel !== openedToplevel
  }

  function handleActiveToplevelChange(nextToplevel) {
    if (shouldDismissForToplevelChange(nextToplevel)) close()
  }

  function handleOutsideClick() {
    if (opened && !pinned) close()
  }

  function outsideClickCaptureEnabled() {
    // Overlay mode already has a fullscreen Side Panel surface. Reserve mode
    // only maps the edge itself, so it needs a second input-only surface.
    return opened && !pinned && reservesSpace
  }

  function open() {
    if (opened) return
    panelRevealProgress = 0
    opened = true
    Qt.callLater(function() {
      if (opened) panelRevealProgress = 1
    })
  }
  function close() {
    if (closing || suppressPanelClose || !opened) return
    closing = true
    try {
      deactivateActivePanels("sidePanel-close")
    } finally {
      opened = false
      panelRevealProgress = 0
      pinned = false
      catalogOpen = false
      settingsOpen = false
      shortcutsOpen = false
      editing = false
      expandedId = ""
      renamingPage = false
      hoveredPanelId = ""
      cancelResize()
      cancelDrag()
      closing = false
    }
  }
  function toggle() { opened ? close() : open() }

  Behavior on panelRevealProgress {
    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
  }

  function handleEscape() {
    if (catalogOpen) catalogOpen = false
    else if (settingsOpen) settingsOpen = false
    else if (shortcutsOpen) shortcutsOpen = false
    else if (!pinned) close()
  }

  function launchFallback(item) {
    if (!item || !bar || !bar.shell || !pluginEnabled(item)) {
      setPanelError(item, "Enable this plugin in Omarchy before opening its native panel.")
      return
    }
    try {
      if (typeof bar.shell.summon === "function" && bar.shell.summon(String(resolvedPluginId(item)))) close()
      else setPanelError(item, "This plugin has no native panel that Omarchy can open.")
    } catch (error) {
      setPanelError(item, "The plugin's native panel could not be opened.")
      console.warn("SidePanel: native fallback failed:", error)
    }
  }

  onSettingsChanged: {
    configurationRevision = Math.max(configurationRevision, settingsConfigurationRevision())
    cancelEdgeReveal()
    deactivateActivePanels("settings-change")
    resetPanelWarmup()
    currentPluginList = null
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
    if (opened) {
      enqueueAllPanelWarmups()
      adaptPreferredPanels()
    }
  }
  Component.onCompleted: {
    sidePanelPages = pagesFromSettings()
    scheduleTransparentForegroundRefresh()
    loadSavedSidePanelState()
  }
  onTransparentBackgroundChanged: scheduleTransparentForegroundRefresh()
  onTransparentTextForegroundChanged: scheduleTransparentForegroundRefresh()
  onTransparentContrastForegroundChanged: scheduleTransparentForegroundRefresh()
  onEffectiveEdgeChanged: {
    cancelEdgeReveal()
    scheduleTransparentForegroundRefresh()
  }
  onSettingsOpenChanged: {
    if (!settingsOpen) {
      panelResizeMode = false
      cancelSidePanelResize()
    }
  }
  onSidePanelExtentChanged: scheduleTransparentForegroundRefresh()

  FileView {
    id: sidePanelStateFile
    path: root.statePath
    atomicWrites: true
    preload: false
    printErrors: false
    onSaved: {
      root.stateWriteInProgress = false
      root.stateWritingText = ""
      root.stateSaveRetryCount = 0
      root.stateSaveError = ""
      if (root.pendingStateText !== "") stateSaveTimer.restart()
    }
    onSaveFailed: function(error) {
      root.stateWriteInProgress = false
      if (root.pendingStateText === "") root.pendingStateText = root.stateWritingText
      root.stateWritingText = ""
      root.stateSaveError = String(error)
      console.warn("SidePanel: cannot save state: " + error + " path=" + root.statePath)
      if (root.pendingStateText !== "" && root.stateSaveRetryCount < 2) {
        root.stateSaveRetryCount += 1
        stateSaveTimer.restart()
      }
    }
  }

  Timer {
    id: stateSaveTimer
    interval: root.stateSaveRetryCount > 0 ? 1000 : 100
    repeat: false
    onTriggered: root.flushStateWrite()
  }

  Process {
    id: stateReader
    clearEnvironment: true
    stdout: StdioCollector {
      id: stateReaderOutput
      waitForEnd: true
    }
    onStarted: stateReaderTimeout.restart()
    onExited: function(exitCode) {
      stateReaderTimeout.stop()
      stateReaderKillTimer.stop()
      if (root.stateReadTimedOut) {
        root.stateReadTimedOut = false
        console.warn("SidePanel: state reader timed out; leaving saved state unchanged")
        return
      }
      if (exitCode === 0) {
        root.loadSidePanelState(String(stateReaderOutput.text || ""), root.stateReadRevision)
      } else if (exitCode === 1) {
        if (root.stateReadRevision === root.stateRevision && root.sidePanelPages.length > 0)
          root.persistSidePanelState()
      } else if (exitCode === 2) {
        console.warn("SidePanel: saved state exceeds the size limit")
      } else if (exitCode === 3) {
        console.warn("SidePanel: refusing unsafe saved state file")
      } else if (exitCode === 4) {
        console.warn("SidePanel: saved state could not be read; leaving it unchanged")
      } else {
        console.warn("SidePanel: state reader failed with exit code " + exitCode)
      }
    }
  }

  Timer {
    id: stateReaderTimeout
    interval: 3000
    repeat: false
    onTriggered: {
      if (!stateReader.running) return
      root.stateReadTimedOut = true
      stateReader.running = false
      stateReaderKillTimer.restart()
    }
  }

  Timer {
    id: stateReaderKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (stateReader.running) stateReader.signal(9)
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

  Timer {
    id: warmupTimer
    interval: 35
    repeat: true
    onTriggered: root.advancePanelWarmup()
  }

  Process {
    id: transparentForegroundProc
    environment: ({
      BASH_ENV: null,
      ENV: null,
      CDPATH: null,
      PATH: "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin"
    })
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (root.transparentForegroundRequestGeneration === root.transparentForegroundGeneration
            && /^#[0-9A-Fa-f]{6}$/.test(value)) root.transparentForeground = value
      }
    }
    onStarted: transparentForegroundTimeout.restart()
    onExited: {
      transparentForegroundTimeout.stop()
      transparentForegroundKillTimer.stop()
      if (root.transparentForegroundDirty
          || root.transparentForegroundRequestGeneration !== root.transparentForegroundGeneration)
        transparentForegroundTimer.restart()
    }
  }

  Timer {
    id: transparentForegroundTimeout
    interval: 7000
    repeat: false
    onTriggered: {
      if (!transparentForegroundProc.running) return
      transparentForegroundProc.running = false
      transparentForegroundKillTimer.restart()
    }
  }

  Timer {
    id: transparentForegroundKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (transparentForegroundProc.running) transparentForegroundProc.signal(9)
  }

  FileView {
    path: root.stateBase === "" ? "" : root.stateBase + "/omarchy/current"
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
      armFocusDismissal()
      currentPage = 0
      resetPanelWarmup()
      adaptedUrls = ({})
      adaptationErrors = ({})
      panelErrors = ({})
      enqueueAllPanelWarmups()
      adaptPreferredPanels()
    } else {
      focusDismissalTimer.stop()
      focusDismissalArmed = false
      openedToplevel = null
      resetPanelWarmup()
      currentPluginList = null
    }
  }
  onPinnedChanged: {
    // A pinned panel deliberately ignores focus changes. Once it is unpinned,
    // use the then-current application as a fresh baseline.
    if (opened && !pinned) armFocusDismissal()
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      root.handleActiveToplevelChange(ToplevelManager.activeToplevel)
    }
  }

  Connections {
    target: root.bar && root.bar.shell ? root.bar.shell.pluginRegistry : null
    function onPluginsChanged() { root.handlePluginRegistryChange() }
    function onLocalPluginChanged(pluginId) { root.handlePluginRegistryChange() }
  }

  Timer {
    id: focusDismissalTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (!root.opened) return
      // During startup the compositor can publish the active toplevel a moment
      // after the panel opens. Capture it only after that initial settle.
      root.openedToplevel = ToplevelManager.activeToplevel
      root.focusDismissalArmed = true
    }
  }

  Process {
    id: adapter
    clearEnvironment: true
    stdout: StdioCollector {
      id: adapterOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: adapterErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      adapterTimeout.stop()
      adapterKillTimer.stop()
      if (root.adaptationTimedOutId !== "") {
        root.adaptationTimedOutId = ""
        Qt.callLater(root.resumePanelPreparation)
        return
      }
      var id = root.adaptingId
      root.adaptingId = ""
      if (id === "") return
      if (root.adaptationRegistryRevision !== root.pluginRegistryRevision) {
        Qt.callLater(root.resumePanelPreparation)
        return
      }
      if (exitCode !== 0) {
        root.setAdaptationError(id, String(adapterErrors.text || "This plugin does not expose a standard Omarchy panel.").trim())
        Qt.callLater(root.resumePanelPreparation)
        return
      }
      var url = String(adapterOutput.text || "").trim()
      var item = root.itemForPanelId(id)
      if (!root.opened || !item || !root.canAdapt(item)) {
        Qt.callLater(root.resumePanelPreparation)
        return
      }
      if (!root.adapterUrlIsSafe(url)) {
        root.setAdaptationError(id, "The adapter produced an unsafe embedded-page URL.")
        Qt.callLater(root.resumePanelPreparation)
        return
      }
      var next = ({})
      for (var key in root.adaptedUrls) next[key] = root.adaptedUrls[key]
      next[id] = url
      root.adaptedUrls = next
      Qt.callLater(root.resumePanelPreparation)
    }
  }

  Timer {
    id: adapterTimeout
    interval: 15000
    repeat: false
    onTriggered: {
      if (root.adaptingId === "") return
      var id = root.adaptingId
      root.adaptingId = ""
      root.adaptationTimedOutId = id
      root.setAdaptationError(id, "Preparing this embedded panel timed out.")
      if (adapter.running) {
        adapter.running = false
        adapterKillTimer.restart()
      } else {
        root.adaptationTimedOutId = ""
        root.resumePanelPreparation()
      }
    }
  }

  Timer {
    id: adapterKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (adapter.running) adapter.signal(9)
  }

  PanelWindow {
    id: edgeRevealSurface
    screen: root.sidePanelScreen
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
      x: root.effectiveEdge === "right" ? parent.width - width : 0
      y: root.effectiveEdge === "bottom" ? parent.height - height : 0
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

  // In reserve mode `surface` only covers the Side Panel edge. A separate
  // fullscreen surface receives clicks everywhere else, with a hole for the
  // Side Panel itself so embedded pages keep receiving their own input.
  PanelWindow {
    id: outsideClickSurface
    objectName: "outsideClickCapture"
    screen: root.sidePanelScreen
    visible: root.outsideClickCaptureEnabled()
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gshulga-side-panel-outside-click"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region {
      width: outsideClickSurface.width
      height: outsideClickSurface.height
      Region {
        intersection: Intersection.Subtract
        x: root.verticalEdge && root.effectiveEdge === "right"
          ? outsideClickSurface.width - Math.min(root.sidePanelExtent + root.sidePanelResizeHitSlop, outsideClickSurface.width) : 0
        y: !root.verticalEdge && root.effectiveEdge === "bottom"
          ? outsideClickSurface.height - Math.min(root.sidePanelExtent + root.sidePanelResizeHitSlop, outsideClickSurface.height) : 0
        width: root.verticalEdge
          ? Math.min(root.sidePanelExtent + root.sidePanelResizeHitSlop, outsideClickSurface.width)
          : outsideClickSurface.width
        height: root.verticalEdge
          ? outsideClickSurface.height
          : Math.min(root.sidePanelExtent + root.sidePanelResizeHitSlop, outsideClickSurface.height)
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.handleOutsideClick()
    }
  }

  PanelWindow {
    id: surface
    screen: root.sidePanelScreen
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
      left: !root.reservesSpace || root.effectiveEdge === "left" || !root.verticalEdge
      right: !root.reservesSpace || root.effectiveEdge === "right" || !root.verticalEdge
      top: !root.reservesSpace || root.verticalEdge || root.effectiveEdge === "top"
      bottom: !root.reservesSpace || root.verticalEdge || root.effectiveEdge === "bottom"
    }

    // Unpinned overlay mode captures outside clicks. A pinned Side Panel must
    // only own its visible geometry so the rest of the workspace stays usable.
    mask: Region { item: surfaceInputRegion }

    Item {
      id: surfaceInputRegion
      objectName: "surfaceInputRegion"
      readonly property real panelLeft: sidePanelBody.x + root.panelRevealOffsetX
      readonly property real panelTop: sidePanelBody.y + root.panelRevealOffsetY
      readonly property real panelRight: panelLeft + sidePanelBody.width
      readonly property real panelBottom: panelTop + sidePanelBody.height
      x: root.pinned
        ? Math.max(0, panelLeft - root.sidePanelResizeHitSlop) : 0
      y: root.pinned
        ? Math.max(0, panelTop - root.sidePanelResizeHitSlop) : 0
      width: root.pinned
        ? Math.max(0, Math.min(surface.width, panelRight + root.sidePanelResizeHitSlop) - x) : surface.width
      height: root.pinned
        ? Math.max(0, Math.min(surface.height, panelBottom + root.sidePanelResizeHitSlop) - y) : surface.height
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
        root.handleOutsideClick()
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
    Shortcut { sequence: "Alt+Right"; enabled: root.opened && !root.editing; context: Qt.WindowShortcut; onActivated: root.movePage(1) }
    Shortcut { sequence: "Alt+Left"; enabled: root.opened && !root.editing; context: Qt.WindowShortcut; onActivated: root.movePage(-1) }
    Shortcut { sequence: "Ctrl+Tab"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.focusKeyboardPlugin(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.focusKeyboardPlugin(-1) }

    Shortcut {
      sequence: "Alt+S"
      enabled: root.opened
      context: Qt.WindowShortcut
      onActivated: {
        root.shortcutsOpen = false
        root.settingsOpen = !root.settingsOpen
      }
    }
    Shortcut {
      sequence: "Alt+?"
      enabled: root.opened
      context: Qt.WindowShortcut
      onActivated: {
        root.settingsOpen = false
        root.shortcutsOpen = !root.shortcutsOpen
      }
    }
    Shortcut { sequence: "Alt+P"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.pinned = !root.pinned }
    Shortcut { sequence: "Alt+E"; enabled: root.opened; context: Qt.WindowShortcut; onActivated: root.setEditing(!root.editing) }
    Shortcut {
      sequence: "Alt+R"
      enabled: root.opened
      context: Qt.WindowShortcut
      onActivated: {
        root.settingsOpen = false
        root.shortcutsOpen = false
        root.beginPageRename()
      }
    }
    Shortcut { sequence: "Alt+X"; enabled: root.opened && root.editing; context: Qt.WindowShortcut; onActivated: root.removeCurrentPage() }
    Shortcut { sequence: "Alt+C"; enabled: root.opened && root.editing && root.sidePanelPages.length < SidePanelModel.MAX_PAGES; context: Qt.WindowShortcut; onActivated: root.addPage() }
    Shortcut { sequence: "Alt++"; enabled: root.opened && root.editing && !root.sidePanelItemLimitReached && !root.sidePanelPageItemLimitReached; context: Qt.WindowShortcut; onActivated: root.catalogOpen = true }
    Shortcut { sequence: "Alt+-"; enabled: root.opened && root.editing; context: Qt.WindowShortcut; onActivated: root.removeFocusedPlugin() }
    Shortcut { sequence: "Alt+Space"; enabled: root.opened && root.editing; context: Qt.WindowShortcut; onActivated: root.toggleFocusedPlugin() }

    Shortcut { sequence: "Alt+Up"; enabled: root.opened && root.editing && root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(-1) }
    Shortcut { sequence: "Alt+K"; enabled: root.opened && root.editing && root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(-1) }
    Shortcut { sequence: "Alt+Down"; enabled: root.opened && root.editing && root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(1) }
    Shortcut { sequence: "Alt+J"; enabled: root.opened && root.editing && root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(1) }
    Shortcut { sequence: "Alt+Left"; enabled: root.opened && root.editing && !root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(-1) }
    Shortcut { sequence: "Alt+H"; enabled: root.opened && root.editing && !root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(-1) }
    Shortcut { sequence: "Alt+Right"; enabled: root.opened && root.editing && !root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(1) }
    Shortcut { sequence: "Alt+L"; enabled: root.opened && root.editing && !root.verticalEdge; context: Qt.WindowShortcut; onActivated: root.moveFocusedPlugin(1) }

    Shortcut { sequence: "Alt+Ctrl+Up"; enabled: root.opened && root.editing && (root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(1, "height") }
    Shortcut { sequence: "Alt+Ctrl+K"; enabled: root.opened && root.editing && (root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(1, "height") }
    Shortcut { sequence: "Alt+Ctrl+Down"; enabled: root.opened && root.editing && (root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(-1, "height") }
    Shortcut { sequence: "Alt+Ctrl+J"; enabled: root.opened && root.editing && (root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(-1, "height") }
    Shortcut { sequence: "Alt+Ctrl+Right"; enabled: root.opened && root.editing && (!root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(1, "width") }
    Shortcut { sequence: "Alt+Ctrl+L"; enabled: root.opened && root.editing && (!root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(1, "width") }
    Shortcut { sequence: "Alt+Ctrl+Left"; enabled: root.opened && root.editing && (!root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(-1, "width") }
    Shortcut { sequence: "Alt+Ctrl+H"; enabled: root.opened && root.editing && (!root.verticalEdge || !root.reservesSpace); context: Qt.WindowShortcut; onActivated: root.resizeFocusedPlugin(-1, "width") }

    Rectangle {
      id: sidePanelBody
      z: 1
      x: root.verticalEdge
        ? (root.effectiveEdge === "left" ? root.sidePanelInsetLeft
          : surface.width - root.sidePanelInsetRight - width)
        : root.sidePanelInsetLeft + root.overlayCrossOffset(root.sidePanelAvailableWidth)
      y: root.verticalEdge
        ? root.sidePanelInsetTop + root.overlayCrossOffset(root.sidePanelAvailableHeight)
        : (root.effectiveEdge === "top" ? root.sidePanelInsetTop
          : surface.height - root.sidePanelInsetBottom - height)
      width: root.verticalEdge
        ? Math.min(root.sidePanelExtent, root.sidePanelAvailableWidth)
        : (root.overlayCrossExtent > 0
          ? Math.min(root.overlayCrossExtent, root.sidePanelAvailableWidth)
          : root.sidePanelAvailableWidth)
      height: root.verticalEdge
        ? (root.overlayCrossExtent > 0
          ? Math.min(root.overlayCrossExtent, root.sidePanelAvailableHeight)
          : root.sidePanelAvailableHeight)
        : Math.min(root.sidePanelExtent, root.sidePanelAvailableHeight)
      transform: Translate {
        x: root.panelRevealOffsetX
        y: root.panelRevealOffsetY
      }
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
          visible: !root.settingsOpen && !root.shortcutsOpen
          anchors.fill: parent
          anchors.margins: Style.space(14)

          Item {
            id: titleRow
            anchors.top: parent.top
            width: parent.width
            height: Math.round(Style.space(28))

            Item {
              id: pageTitleAction
              visible: !root.renamingPage
              anchors.left: parent.left
              anchors.right: root.editing ? removePageButton.left : shortcutsButton.left
              anchors.rightMargin: Style.space(8)
              height: parent.height

              Text {
                id: title
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: titleRenameHint.visible
                  ? Math.min(implicitWidth, Math.max(0, parent.width - titleRenameHint.width - Style.space(6)))
                  : parent.width
                text: root.currentPageRecord() ? String(root.currentPageRecord().title).toUpperCase() : "PLUGINS"
                textFormat: Text.PlainText
                color: root.chromeForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1.1
                elide: Text.ElideRight
              }

              Rectangle {
                id: titleRenameHint
                visible: titleHover.containsMouse
                x: Math.min(title.implicitWidth + Style.space(6), parent.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(Style.space(22))
                height: width
                radius: height / 2
                color: titleRenameMouse.containsMouse
                  ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

                Text {
                  anchors.centerIn: parent
                  text: "\uf044"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: titleRenameMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.beginPageRename()
                }
              }

              MouseArea {
                id: titleHover
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onDoubleClicked: root.beginPageRename()
              }
            }

            TextInput {
              id: pageTitleInput
              visible: root.renamingPage
              anchors.left: parent.left
              anchors.right: root.editing ? removePageButton.left : shortcutsButton.left
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
              readonly property bool expanded: settingsHover.containsMouse
              width: expanded ? Math.round(Style.space(104)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: settingsHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text { text: "\uf013"; color: root.chromeForeground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                Text {
                  visible: settingsButton.expanded
                  text: "Settings"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: settingsHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.shortcutsOpen = false
                  root.settingsOpen = true
                }
              }
            }

            Rectangle {
              id: shortcutsButton
              objectName: "shortcutsButton"
              visible: !root.editing && (titleRowHover.hovered || root.shortcutsOpen)
              anchors.right: settingsButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              readonly property bool expanded: shortcutsHover.containsMouse
              width: expanded ? Math.round(Style.space(112)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: shortcutsHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: "?"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  visible: shortcutsButton.expanded
                  text: "Shortcuts"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: shortcutsHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.settingsOpen = false
                  root.shortcutsOpen = true
                }
              }
            }

            Rectangle {
              id: editButton
              visible: titleRowHover.hovered || root.editing
              anchors.right: root.editing ? parent.right : pinButton.left
              anchors.rightMargin: root.editing ? 0 : Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              readonly property bool expanded: editHover.containsMouse
              width: expanded ? Math.round(Style.space(82)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: root.editing
                ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                : (editHover.containsMouse
                  ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06))

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: root.editing ? "\uf00c" : "\uf044"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  visible: editButton.expanded
                  text: root.editing ? "Done" : "Edit"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
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
              opacity: root.sidePanelItemLimitReached || root.sidePanelPageItemLimitReached ? 0.5 : 1
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
                enabled: !root.sidePanelItemLimitReached && !root.sidePanelPageItemLimitReached
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
              readonly property bool expanded: pinHover.containsMouse
              width: expanded ? Math.round(Style.space(root.pinned ? 86 : 72)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: root.pinned
                ? Style.selectedFillFor(root.chromeForeground, Color.accent)
                : (pinHover.containsMouse
                  ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                  : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06))

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: "\uf08d"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  visible: pinButton.expanded
                  text: root.pinned ? "Unpin" : "Pin"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
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

          Item {
            id: pageListHost
            anchors.top: titleRow.bottom
            anchors.topMargin: Style.space(10)
            anchors.left: parent.left
            width: root.verticalEdge ? parent.width : Math.max(0, pageCarousel.x - Style.space(8))
            height: root.verticalEdge
              ? Math.max(0, pageCarousel.y - y - Style.space(8))
              : Math.max(0, parent.height - y)
            Repeater {
              model: root.sidePanelPages
              delegate: ListView {
                id: pluginList
                required property int index
                required property var modelData
                readonly property int pageIndex: index
                anchors.fill: parent
                visible: pageIndex === root.currentPage
                orientation: root.verticalEdge ? ListView.Vertical : ListView.Horizontal
                clip: true
                // A plugin without its own Flickable must still let its oversized
                // panel scroll in SidePanel's viewport. Nested Flickables consume the
                // wheel first, so their local scrolling is preserved.
                interactive: root.resizingId === "" && root.draggedId === ""
                spacing: Style.space(7)
                model: modelData.items || []
                // Stack mode keeps every embedded panel instantiated; lifecycle is
                // therefore independent of ListView delegate recycling. Do not
                // bind this to contentHeight: that creates a ListView layout loop.
                cacheBuffer: 100000
                displayMarginBeginning: 100000
                displayMarginEnd: 100000
                Component.onCompleted: {
                  if (visible) root.currentPluginList = pluginList
                }
                onVisibleChanged: {
                  if (visible) root.currentPluginList = pluginList
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
              width: root.verticalEdge
                ? (!root.reservesSpace && Number(pluginRow.plugin.width) > 0 ? root.panelWidth(pluginRow.plugin) : pluginList.width)
                : root.panelWidth(pluginRow.plugin)
              height: root.verticalEdge
                ? (root.editing ? header.height : 0) + content.height
                : (root.editing && !root.reservesSpace && Number(pluginRow.plugin.height) > 0
                  ? (root.editing ? header.height : 0) + content.height : pluginList.height)
              z: root.draggedId === pluginId ? 3 : 1

              function focusPanel() {
                if (pageLoader.item && typeof pageLoader.item.sidePanelFocus === "function")
                  root.invokePanelMethod(pageLoader.item, "sidePanelFocus", [], pluginId)
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
                border.width: pluginRow.index === root.keyboardPluginIndex ? 2 : 1
                border.color: pluginRow.index === root.keyboardPluginIndex
                  ? Color.accent
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, pluginRow.expanded ? 0.22 : 0.09)

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

                Rectangle {
                  id: deleteButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property bool expanded: deleteMouse.containsMouse
                  width: expanded ? Math.round(Style.space(96)) : Math.round(Style.space(30))
                  height: Math.round(Style.space(30))
                  radius: height / 2
                  clip: true
                  color: deleteMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                  Behavior on width {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                  }

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(5)
                    Text {
                      text: "\uf1f8"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      visible: deleteButton.expanded
                      text: "Remove"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
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
                  ? (root.verticalEdge || (root.editing && !root.reservesSpace && Number(pluginRow.plugin.height) > 0)
                    ? root.panelHeight(pluginRow.plugin) : pluginList.height - (root.editing ? header.height : 0))
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
                    asynchronous: true
                    active: root.opened
                      && !root.panelLoadFailed(pluginRow.plugin)
                      && (!root.editing || pluginRow.expanded)
                      && root.warmedPanelIds.indexOf(root.resolvedPluginId(pluginRow.plugin)) >= 0
                      && root.panelUrl(pluginRow.plugin) !== ""
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

                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      visible: root.pluginEnabled(pluginRow.plugin)
                        && root.adaptingId !== root.resolvedPluginId(pluginRow.plugin)
                        && (root.panelLoadFailed(pluginRow.plugin)
                          || root.adaptationFailed(pluginRow.plugin)
                          || !root.canAdapt(pluginRow.plugin))
                      width: Math.min(parent.width, Math.round(Style.space(180)))
                      height: Math.round(Style.space(36))
                      radius: height / 2
                      color: fallbackMouse.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                      Text {
                        anchors.centerIn: parent
                        text: "Open native panel"
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }

                      MouseArea {
                        id: fallbackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchFallback(pluginRow.plugin)
                      }
                    }

                  }
                }

                Rectangle {
                  id: resizeHandle
                  visible: root.editing && pluginRow.expanded && (root.verticalEdge || !root.reservesSpace)
                  width: parent.width
                  height: Math.round(Style.space(8))
                  x: 0
                  y: parent.height - height
                  color: resizeMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)

                  MouseArea {
                    id: resizeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeVerCursor
                    onPressed: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.beginResize(pluginRow.plugin, "height", point.y)
                    }
                    onPositionChanged: function(mouse) {
                      var point = resizeHandle.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.updateResize(point.y)
                    }
                    onReleased: root.finishResize()
                    onCanceled: root.cancelResize()
                  }
                }

                Rectangle {
                  visible: root.editing && pluginRow.expanded && (!root.verticalEdge || !root.reservesSpace)
                  width: Math.round(Style.space(8))
                  height: parent.height
                  x: parent.width - width
                  y: 0
                  color: widthResizeMouse.containsMouse
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
                  MouseArea {
                    id: widthResizeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeHorCursor
                    onPressed: function(mouse) {
                      var point = parent.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.beginResize(pluginRow.plugin, "width", point.x)
                    }
                    onPositionChanged: function(mouse) {
                      var point = parent.mapToItem(keyCatcher, mouse.x, mouse.y)
                      root.updateResize(point.x)
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
            }

          }

          Rectangle {
            id: pageCarousel
            objectName: "pageCarousel"
            width: root.verticalEdge
              ? pageDots.width + (root.editing ? pageAdd.width + Style.space(10) : 0)
              : Math.max(pageDotsVertical.width, root.editing ? pageAdd.width : 0)
            height: root.verticalEdge
              ? Math.round(Style.space(24))
              : pageDotsVertical.height + (root.editing ? pageAdd.height + Style.space(10) : 0)
            x: root.verticalEdge ? (parent.width - width) / 2 : parent.width - width
            y: root.verticalEdge ? parent.height - height : (parent.height - height) / 2
            color: "transparent"

            Row {
              id: pageDots
              objectName: "pageDotsHorizontal"
              visible: root.verticalEdge
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

            Column {
              id: pageDotsVertical
              objectName: "pageDotsVertical"
              visible: !root.verticalEdge
              anchors.top: parent.top
              anchors.horizontalCenter: parent.horizontalCenter
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

            Rectangle {
              id: pageAdd
              visible: root.editing
              enabled: root.sidePanelPages.length < SidePanelModel.MAX_PAGES
              opacity: enabled ? 1 : 0.42
              x: root.verticalEdge ? parent.width - width : (parent.width - width) / 2
              y: root.verticalEdge ? (parent.height - height) / 2 : parent.height - height
              readonly property bool expanded: pageAddHover.containsMouse
              width: expanded ? Math.round(Style.space(102)) : Math.round(Style.space(28))
              height: Math.round(Style.space(28))
              radius: height / 2
              clip: true
              color: pageAddHover.containsMouse
                ? Style.hoverFillFor(root.chromeForeground, Color.accent)
                : Qt.rgba(root.chromeForeground.r, root.chromeForeground.g, root.chromeForeground.b, 0.06)

              Behavior on width {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Row {
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: "\uf067"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Text {
                  visible: pageAdd.expanded
                  text: "Add page"
                  color: root.chromeForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea { id: pageAddHover; anchors.fill: parent; enabled: pageAdd.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addPage() }
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

    }

    SidePanelResizeHandles {
      anchors.fill: parent
      body: sidePanelBody
      enabled: root.settingsOpen && root.panelResizeMode
      reservesSpace: root.reservesSpace
      verticalEdge: root.verticalEdge
      edge: root.effectiveEdge
      overlayAlignment: root.overlayAlignment
      foreground: root.chromeForeground
      resizing: root.resizingSidePanel
      resizeAxis: root.sidePanelResizeAxis
      onResizeStarted: function(axis, position) { root.beginSidePanelResize(axis, position) }
      onResizeUpdated: function(position) { root.updateSidePanelResize(position) }
      onResizeFinished: root.finishSidePanelResize()
      onResizeCanceled: root.cancelSidePanelResize()
    }

    SidePanelPluginCatalog {
      id: catalog
      visible: root.catalogOpen
      availablePlugins: root.availablePlugins
      itemCount: root.sidePanelItemCount
      maximumItemCount: SidePanelModel.MAX_TOTAL_ITEMS
      itemLimitReached: root.sidePanelItemLimitReached || root.sidePanelPageItemLimitReached
      limitMessage: root.sidePanelPageItemLimitReached
        ? "This Side Panel page can contain up to " + SidePanelModel.MAX_ITEMS_PER_PAGE + " items."
        : "The Side Panel can contain up to " + SidePanelModel.MAX_TOTAL_ITEMS + " items."
      foreground: root.foreground
      onCloseRequested: root.catalogOpen = false
      onPluginAddRequested: function(pluginId) { root.addPlugin(pluginId) }
    }
    SidePanelSettings {
      id: settingsPage
      anchors.fill: sidePanelBody
      visible: root.settingsOpen
      z: 11
      edge: root.effectiveEdge
      layoutMode: root.effectiveLayoutMode
      verticalEdge: root.verticalEdge
      reservesSpace: root.reservesSpace
      overlayAlignment: root.overlayAlignment
      foreground: root.chromeForeground
      resizeMode: root.panelResizeMode
      edgeRevealEnabled: root.edgeRevealConfigured
      edgeRevealDelayMs: root.edgeRevealDelayMs
      onCloseRequested: root.settingsOpen = false
      onSettingRequested: function(name, value) { root.persistSidePanelSetting(name, value) }
      onResizeModeRequested: function(enabled) {
        root.panelResizeMode = enabled
        if (!enabled) root.cancelSidePanelResize()
      }
    }

    SidePanelShortcuts {
      id: shortcutsPage
      objectName: "shortcutsPage"
      anchors.fill: sidePanelBody
      visible: root.shortcutsOpen
      z: 11
      foreground: root.chromeForeground
      onCloseRequested: root.shortcutsOpen = false
    }
  }
}
