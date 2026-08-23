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
    if (id === "" || id === "gshulga.drawer" || seen[id]) continue
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

function itemsFromSettings(settings, defaults, resolveId) {
  var configured = settings ? settings.plugins : undefined
  if (Array.isArray(configured)) return normalize(configured, resolveId)

  var pages = settings ? settings.pages : undefined
  if (Array.isArray(pages) && pages.length > 0) {
    var flattened = []
    for (var i = 0; i < pages.length; i++) {
      if (pages[i] && Array.isArray(pages[i].items)) flattened = flattened.concat(pages[i].items)
    }
    return normalize(flattened, resolveId)
  }
  return normalize(defaults, resolveId)
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

function clampHeight(value, minimum, maximum) {
  return Math.round(Math.max(minimum, Math.min(maximum, finiteNumber(value, minimum))))
}

function resizeHeight(startHeight, startY, currentY, minimum, maximum, step) {
  var raw = clampHeight(startHeight + currentY - startY, minimum, maximum)
  return Math.round(raw / step) * step
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

function persistedEntry(settings, items) {
  var entry = ({ id: "gshulga.drawer" })
  for (var key in settings || ({})) {
    if (key !== "id" && key !== "pages" && key !== "plugins") entry[key] = settings[key]
  }
  entry.plugins = copy(items)
  return entry
}
