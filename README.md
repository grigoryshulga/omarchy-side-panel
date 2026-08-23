# Omarchy Drawer

`omarchy-drawer` is an edge drawer for secondary Omarchy plugins. It keeps one
bar icon and exposes one or more pages of plugin shortcuts from the configured
left, right, top, or bottom screen edge.

## Compatibility

An existing Omarchy `bar-widget` cannot be embedded safely just by loading its
entry-point QML. Most widgets own a `KeyboardPanel` anchored to their own bar
button, assume bar-managed lifecycle, and may be instantiated once per output.
Forcing that QML into another container breaks those assumptions.

Drawer therefore has three explicit modes:

- **Automatic standard-panel embedding:** when a plugin uses Omarchy's standard
  `KeyboardPanel`, Drawer copies the plugin into
  `$XDG_CACHE_HOME/omarchy-drawer/`, replaces that one host with
  `DrawerPanelHost`, replaces copied IPC handlers with inert local shims, and
  routes close lifecycle to Drawer. The installed plugin and Omarchy files are
  never changed.
- **Explicit embedded page:** a plugin may opt in with `entryPoints.drawerPage`.
  Drawer loads that component directly and supplies optional `drawer`, `bar`,
  `settings`, `pluginId`, and `service` properties.
- **Native fallback:** any listed plugin without `drawerPage` remains usable.
  Drawer shows an `Open native panel` action and calls Omarchy's normal
  `shell.summon(id)` route. The target plugin must remain enabled.

Standard panels are embedded without source changes. The explicit page route
remains the stable option for plugin authors, while the native fallback covers
custom windows that cannot be reparented under Wayland.

## Install

```bash
omarchy plugin add file:///home/gshulga/projects/personal/omarchy-drawer --enable
```

Omarchy discovers the plugin as `gshulga.drawer`. Add it to the bar as usual if
the installer did not place it automatically.

## Configuration

The edge is available in the Omarchy plugin settings. Pages are intentionally
kept as plain data in the Drawer layout entry in
`~/.config/omarchy/shell.json`:

```json
{
  "id": "gshulga.drawer",
  "edge": "left",
  "pages": [
    {
      "title": "Work",
      "items": [
        { "id": "gshulga.jira", "label": "Jira", "icon": "\\ue75c" },
        { "id": "io.github.sotoaugusto.ticktick", "label": "Tasks", "icon": "\\uf0ae" }
      ]
    },
    {
      "title": "System",
      "items": [
        { "id": "omarchy.network", "label": "Network", "icon": "\\uf1eb" },
        { "id": "omarchy.bluetooth", "label": "Bluetooth", "icon": "\\uf293" }
      ]
    }
  ]
}
```

When `pages` is omitted, Drawer starts with a small local default page.

## Embedded Page Contract

To expose a plugin page inside Drawer, add this entry point to its manifest:

```json
"entryPoints": {
  "barWidget": "BarWidget.qml",
  "drawerPage": "DrawerPage.qml"
}
```

`DrawerPage.qml` must be an ordinary `Item` or control that sizes to its parent.
It must not create a `PanelWindow`, manage an overlay, or depend on a bar-icon
anchor. The drawer injects these optional properties when they exist:

- `drawer`: the Drawer host, including `close()`.
- `bar`: the active Omarchy bar object.
- `settings`: the selected page item object.
- `pluginId`: the selected plugin id.
- `service`: the plugin's singleton service, if it has one.

Example:

```qml
import QtQuick

Item {
  property var drawer: null
  property var service: null

  Text {
    anchors.centerIn: parent
    text: "My embedded plugin page"
  }
}
```

## Keyboard Controls

- `Escape`: close the drawer.
- Left/Right: select a page.
- Up/Down: select a plugin.
- Enter: open a non-embedded plugin in its native panel.

## Automatic Embedding

Press `Embed in Drawer` for a listed plugin. Drawer tries the standard adapter
before it offers native fallback. It supports both conventional Omarchy shapes:

- a `barWidget` entry point whose QML contains `KeyboardPanel`;
- a `barWidget` entry point that loads a sibling `Panel.qml` containing
  `KeyboardPanel`.

The adapter uses a generated copy solely for the current shell session. The
next shell session regenerates that copy from the installed plugin, so a plugin
update is picked up automatically. It cannot embed a plugin that creates its own `PanelWindow`,
overlay, or non-standard popup host: Wayland windows cannot be reparented into
another QML item after creation. Those plugins retain the native fallback.

See `docs/automatic-embedding.md` for the transformation contract and safety
boundaries.
