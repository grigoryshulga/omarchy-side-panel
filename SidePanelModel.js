.pragma library

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function normalizedHeight(value) {
  var height = finiteNumber(value, 0)
  return height > 0 ? height : 0
}

function normalize(items, resolveId) {
  var normalized = []
  var seen = ({})
  for (var i = 0; i < (items || []).length; i++) {
    var item = items[i] || ({})
    var id = String(resolveId(item) || "")
    if (id === "" || id === "gshulga.side-panel" || seen[id]) continue
    seen[id] = true
    normalized.push({
      id: id,
      label: String(item.label || ""),
      icon: String(item.icon || ""),
      height: normalizedHeight(item.height),
      embedding: item.embedding === "standard" ? "standard" : ""
    })
  }
  return normalized
}

function pageTitle(value, index) {
  var title = String(value || "").trim()
  return title === "" ? "Page " + (index + 1) : title
}

function normalizePages(pages, defaults, resolveId) {
  var source = Array.isArray(pages) && pages.length > 0 ? pages : [{ title: "Plugins", items: defaults }]
  var normalized = []
  var usedPlugins = ({})
  for (var i = 0; i < source.length; i++) {
    var page = source[i] || ({})
    var items = normalize(page.items, resolveId)
    var uniqueItems = []
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
      if (usedPlugins[items[itemIndex].id]) continue
      usedPlugins[items[itemIndex].id] = true
      uniqueItems.push(items[itemIndex])
    }
    normalized.push({
      title: pageTitle(page.title || page.label || page.name, i),
      items: uniqueItems
    })
  }
  return normalized
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
  for (var i = 0; i < items.length; i++) {
    result.push({
      id: items[i].id,
      label: items[i].label,
      icon: items[i].icon,
      height: normalizedHeight(items[i].height),
      embedding: items[i].embedding === "standard" ? "standard" : ""
    })
  }
  return result
}

function resizeHeight(startHeight, startY, currentY, minimum, step) {
  var raw = Math.max(minimum, finiteNumber(startHeight + currentY - startY, minimum))
  return Math.max(minimum, Math.round(raw / step) * step)
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
  for (var i = 0; i < pages.length; i++) {
    result.push({ title: pageTitle(pages[i].title, i), items: copy(pages[i].items || []) })
  }
  return result
}

function persistedEntry(settings, pages) {
  var entry = ({ id: "gshulga.side-panel" })
  for (var key in settings || ({})) {
    if (key !== "id" && key !== "pages" && key !== "plugins" && key !== "transparentBackground") entry[key] = settings[key]
  }
  entry.pages = copyPages(pages)
  return entry
}
