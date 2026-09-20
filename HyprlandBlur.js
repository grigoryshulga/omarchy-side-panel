.pragma library

// Same layer-rule technique as the Dashboard (qml/appearance/HyprlandBlur.js),
// namespaced to the Side Panel's layer surface.
var HANDLE = "gshulga_side_panel_blur_rule"
var VERSION_HANDLE = "gshulga_side_panel_blur_rule_version"
var RULE_VERSION = 1
var RULE_NAME = "gshulga-side-panel-blur"
var NAMESPACE = "gshulga-side-panel"

function ruleExpression(enabled) {
  var state = enabled === true ? "true" : "false"
  return "if " + HANDLE + " ~= nil and " + VERSION_HANDLE + " ~= " + RULE_VERSION + " then\n"
    + "  " + HANDLE + ":set_enabled(false)\n"
    + "end\n"
    + "if " + HANDLE + " == nil or " + VERSION_HANDLE + " ~= " + RULE_VERSION + " then\n"
    + "  " + HANDLE + " = hl.layer_rule({\n"
    + "    name = \"" + RULE_NAME + "\",\n"
    + "    match = { namespace = \"" + NAMESPACE + "\" },\n"
    + "    blur = true,\n"
    + "    xray = true,\n"
    + "  })\n"
    + "  " + VERSION_HANDLE + " = " + RULE_VERSION + "\n"
    + "end\n"
    + HANDLE + ":set_enabled(" + state + ")"
}
