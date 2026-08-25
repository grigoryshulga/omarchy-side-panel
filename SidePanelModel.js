.pragma library

var MAX_STATE_BYTES = 64 * 1024
var MAX_PAGES = 12
var MAX_ITEMS_PER_PAGE = 24
var MAX_TOTAL_ITEMS = 48
var MAX_PAGE_TITLE_LENGTH = 80
var MAX_ITEM_ID_LENGTH = 160
var MAX_ITEM_LABEL_LENGTH = 160
var MAX_ITEM_ICON_LENGTH = 32
var MAX_EDGE_SIZE = 4096
var MAX_ITEM_EXTENT = 4096

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function boundedInteger(value, fallback, minimum, maximum) {
  return Math.round(Math.max(minimum, Math.min(maximum, finiteNumber(value, fallback))))
}

function boundedString(value, maximum) {
  var string = value === undefined || value === null ? "" : String(value)
  return string.length > maximum ? string.slice(0, maximum) : string
}

function normalizedExtent(value, maximum) {
  var extent = finiteNumber(value, 0)
  return extent > 0 ? Math.min(extent, maximum) : 0
}

function normalizedHeight(value) {
  return normalizedExtent(value, MAX_ITEM_EXTENT)
}

function boundedEdgeSize(value, fallback) {
  var edgeSize = normalizedExtent(value, MAX_EDGE_SIZE)
  return edgeSize > 0 ? edgeSize : normalizedExtent(fallback, MAX_EDGE_SIZE)
}

function boundedExtent(value, minimum, maximum) {
  var upper = Math.max(0, Math.min(MAX_EDGE_SIZE, finiteNumber(maximum, MAX_EDGE_SIZE)))
  var lower = Math.max(0, Math.min(upper, finiteNumber(minimum, 0)))
  return Math.max(lower, Math.min(upper, finiteNumber(value, lower)))
}

function normalize(items, resolveId, maximum) {
  var normalized = []
  var seen = ({})
  var source = Array.isArray(items) ? items : []
  var limit = Math.max(0, Math.floor(Math.min(MAX_ITEMS_PER_PAGE, finiteNumber(maximum, MAX_ITEMS_PER_PAGE))))
  for (var i = 0; i < source.length && i < limit; i++) {
    var item = source[i] || ({})
    var id = boundedString(resolveId(item), MAX_ITEM_ID_LENGTH)
    if (id === "" || id === "gshulga.side-panel" || seen[id]) continue
    seen[id] = true
    normalized.push({
      id: id,
      label: boundedString(item.label, MAX_ITEM_LABEL_LENGTH),
      icon: boundedString(item.icon, MAX_ITEM_ICON_LENGTH),
      height: normalizedHeight(item.height),
      width: normalizedHeight(item.width),
      embedding: item.embedding === "standard" ? "standard" : ""
    })
  }
  return normalized
}

function pageTitle(value, index) {
  var title = boundedString(value, MAX_PAGE_TITLE_LENGTH).trim()
  return title === "" ? "Page " + (index + 1) : title
}

function normalizePages(pages, defaults, resolveId) {
  var source = Array.isArray(pages) && pages.length > 0 ? pages : [{ title: "Plugins", items: defaults }]
  var normalized = []
  var usedPlugins = ({})
  var itemCount = 0
  for (var i = 0; i < source.length && i < MAX_PAGES; i++) {
    var page = source[i] || ({})
    var items = normalize(page.items, resolveId, MAX_ITEMS_PER_PAGE)
    var uniqueItems = []
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
      if (itemCount >= MAX_TOTAL_ITEMS) break
      if (usedPlugins[items[itemIndex].id]) continue
      usedPlugins[items[itemIndex].id] = true
      uniqueItems.push(items[itemIndex])
      itemCount += 1
    }
    normalized.push({
      title: pageTitle(page.title || page.label || page.name, i),
      items: uniqueItems
    })
  }
  return normalized
}

function utf8ByteLength(value) {
  try {
    return unescape(encodeURIComponent(String(value))).length
  } catch (error) {
    return MAX_STATE_BYTES + 1
  }
}

function parseState(raw, defaults, resolveId) {
  if (utf8ByteLength(raw) > MAX_STATE_BYTES) return null
  try {
    var state = JSON.parse(String(raw || ""))
    if (!state || state.version !== 1 || !Array.isArray(state.pages)) return null
    var pages = normalizePages(state.pages, defaults, resolveId)
    var normalized = {
      version: 1,
      pages: pages,
      currentPage: Math.max(0, Math.min(pages.length - 1, Math.floor(finiteNumber(state.currentPage, 0))))
    }
    if (["left", "right", "top", "bottom"].indexOf(state.edge) >= 0) normalized.edge = state.edge
    if (["overlay", "reserve"].indexOf(state.layoutMode) >= 0) normalized.layoutMode = state.layoutMode
    if (["left", "center", "right", "top", "bottom"].indexOf(state.overlayAlignment) >= 0)
      normalized.overlayAlignment = state.overlayAlignment
    var edgeSize = normalizedExtent(state.edgeSize, MAX_EDGE_SIZE)
    if (edgeSize > 0) normalized.edgeSize = edgeSize
    var overlayCrossSize = normalizedExtent(state.overlayCrossSize, MAX_EDGE_SIZE)
    if (overlayCrossSize > 0) normalized.overlayCrossSize = overlayCrossSize
    return normalized
  } catch (error) {
    return null
  }
}

function pagesFromSettings(settings, defaults, resolveId) {
  if (settings && Array.isArray(settings.pages) && settings.pages.length > 0)
    return normalizePages(settings.pages, defaults, resolveId)
  if (settings && Array.isArray(settings.plugins))
    return normalizePages([{ title: "Plugins", items: settings.plugins }], defaults, resolveId)
  return normalizePages([], defaults, resolveId)
}

function copy(items) {
  var result = []
  var source = Array.isArray(items) ? items : []
  for (var i = 0; i < source.length && i < MAX_ITEMS_PER_PAGE; i++) {
    result.push({
      id: boundedString(source[i].id, MAX_ITEM_ID_LENGTH),
      label: boundedString(source[i].label, MAX_ITEM_LABEL_LENGTH),
      icon: boundedString(source[i].icon, MAX_ITEM_ICON_LENGTH),
      height: normalizedHeight(source[i].height),
      width: normalizedHeight(source[i].width),
      embedding: source[i].embedding === "standard" ? "standard" : ""
    })
  }
  return result
}

function resizeHeight(startHeight, startY, currentY, minimum, step) {
  var raw = Math.min(MAX_ITEM_EXTENT, Math.max(minimum, finiteNumber(startHeight + currentY - startY, minimum)))
  // MAX_ITEM_EXTENT is not necessarily aligned to the resize step. Preserve
  // the configured upper bound instead of rounding it down to the last step.
  if (raw === MAX_ITEM_EXTENT) return MAX_ITEM_EXTENT
  return Math.min(MAX_ITEM_EXTENT, Math.max(minimum, Math.round(raw / step) * step))
}

function move(items, sourceId, targetId, after) {
  if (sourceId === "" || sourceId === targetId) return copy(items)
  var result = copy(items)
  var sourceIndex = -1
  var targetIndex = -1
  for (var i = 0; i < result.length; i++) {
    if (result[i].id === sourceId) sourceIndex = i
    if (result[i].id === targetId) targetIndex = i
  }
  if (sourceIndex < 0 || targetIndex < 0) return result
  var item = result.splice(sourceIndex, 1)[0]
  for (var j = 0; j < result.length; j++) {
    if (result[j].id === targetId) {
      targetIndex = j
      break
    }
  }
  result.splice(after ? targetIndex + 1 : targetIndex, 0, item)
  return result
}

function copyPages(pages) {
  var result = []
  var source = Array.isArray(pages) ? pages : []
  for (var i = 0; i < source.length && i < MAX_PAGES; i++) {
    result.push({ title: pageTitle(source[i].title, i), items: copy(source[i].items || []) })
  }
  return result
}

function persistedEntry(settings, pages) {
  var entry = ({ id: "gshulga.side-panel" })
  for (var key in settings || ({})) {
    if (key === "id" || key === "pages" || key === "plugins" || key === "transparentBackground") continue
    if (key === "edgeSize" || key === "overlayCrossSize") {
      var edgeSize = normalizedExtent(settings[key], MAX_EDGE_SIZE)
      if (edgeSize > 0) entry[key] = edgeSize
    } else {
      entry[key] = settings[key]
    }
  }
  entry.pages = copyPages(pages)
  return entry
}
