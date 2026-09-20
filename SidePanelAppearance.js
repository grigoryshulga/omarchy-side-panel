.pragma library

// Mirrors the Dashboard's appearance vocabulary (qml/appearance/DashboardAppearance.js)
// so both plugins answer the same two modes. Side Panel adds `auto`, which keeps
// the historical behaviour: the panel turns glassy only while it reserves screen
// space for a transparent bar.
var AUTO = "auto"
var FRAMED = "framed"
var GLASS = "glass"

function surfaceMode(value) {
  var normalized = String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "").toLowerCase()
  if (normalized === AUTO || normalized === FRAMED || normalized === GLASS) return normalized
  return AUTO
}

function usesGlass(value, autoGlass) {
  var mode = surfaceMode(value)
  if (mode === GLASS) return true
  if (mode === FRAMED) return false
  return autoGlass === true
}
