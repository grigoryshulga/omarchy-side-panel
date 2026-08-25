# Omarchy Side Panel

<p align="center">
  <img src="assets/banner.png" alt="Omarchy Side Panel" width="100%">
</p>

Omarchy Side Panel keeps selected plugin panels one click away without leaving
them on screen all the time. Open it from the bar, put it on any screen edge,
and group plugins into named Side Panel pages.

## Install

```bash
omarchy plugin add https://github.com/grigoryshulga/omarchy-side-panel.git --enable
```

The plugin id is `gshulga.side-panel`. If Side Panel does not appear on the bar
after installation, add it from Omarchy's bar-plugin settings.

To remove it later:

```bash
omarchy plugin remove gshulga.side-panel
```

## First use

1. Click the Side Panel icon in the bar to open it.
2. Hover the title and select the edit button.
3. Select **Add Plugin**, choose an installed plugin, and add it to the current
   Side Panel page. Side Panel enables the plugin when necessary.
4. Select the edit button again to leave edit mode and use the embedded panels.

Use the `+` beside the page dots to create another page. Double-click a page
title in edit mode to rename it. The delete-page control is available once
there is more than one page.

## Everyday controls

- Hover the title to reveal the pin, edit, and settings controls.
- Pinning keeps the Side Panel open while another bar popout is active. It is
  cleared when the Side Panel closes.
- In edit mode, drag a plugin header to reorder items, use its delete button to
  remove it, and use the item grip to resize it.
- Drag the visible grip on the outer edge to resize the whole Side Panel.
- Open the settings control to choose the Edge and Display mode:
  - **Overlay** floats above existing windows.
  - **Push screen** reserves edge space, so Hyprland lays out windows in the
    remaining area.
- In Omarchy's plugin settings, **Reveal at screen edge** controls pointer
  reveal. **Edge reveal delay** defaults to 250 ms and can be set from 0 to
  2000 ms.

## Keyboard

- `Escape`: close the Side Panel, or close the add-plugin catalog/settings
  first.
- `Alt+1` through `Alt+9`: open a Side Panel page by number.
- `Alt+Left` / `Alt+Right`: previous / next Side Panel page.
- `Ctrl+Tab` / `Ctrl+Shift+Tab`: move keyboard focus between embedded panels.

Once an embedded panel has focus, its own keyboard controls receive input.

## What can be shown in Side Panel?

Side Panel chooses the safest available integration for each selected plugin:

1. A plugin that provides an explicit `sidePanelPage` is loaded directly.
2. A conventional Omarchy `KeyboardPanel` is automatically copied to a
   disposable cache and adapted for the Side Panel.
3. A plugin that cannot be embedded remains available through its native panel,
   provided it is enabled.

The automatic copy is stored under `$XDG_CACHE_HOME/omarchy-side-panel/`; it
never modifies the installed plugin. The cache can be deleted after uninstalling
Side Panel or whenever disk space is needed.

## Preview

| Left edge | Top edge |
| --- | --- |
| ![Left Side Panel showing agent controls](assets/screenshots/left-agents.png) | ![Top Side Panel showing compact plugin panels](assets/screenshots/top-agents.png) |

| Overlay mode | Transparent background |
| --- | --- |
| ![Side Panel floating over windows](assets/screenshots/overlay-example.png) | ![Side Panel with a transparent background](assets/screenshots/transparent-example.png) |

## For plugin authors

An explicit embedded page is the preferred integration. Add a `sidePanelPage`
entry point alongside the existing bar widget:

```json
"entryPoints": {
  "barWidget": "BarWidget.qml",
  "sidePanelPage": "SidePanelPage.qml"
}
```

`SidePanelPage.qml` must be an ordinary `Item` or control that fills its parent.
It must not create a `PanelWindow`, manage an overlay, or depend on a bar-icon
anchor. Side Panel supplies `sidePanel`, `sidePanelItem`, `bar`, `settings`,
`pluginId`, and `service` when matching writable properties exist. Alternatively,
provide `initializeSidePanel(context)` to receive those values at once.

```qml
import QtQuick

Item {
  property var service: null

  function initializeSidePanel(context) {
    service = context.service
  }
}
```

For the supported automatic-embedding shapes, transformation rules, and safety
boundaries, see [Automatic embedding](docs/automatic-embedding.md).

## Requirements and data

- Omarchy with plugin support and a running Omarchy shell.
- Python 3 for automatic standard-panel embedding. No third-party Python
  packages are required.

Side Panel is an unsandboxed plugin and runs with the current user's
permissions. Add only plugins you trust. Its configuration is maintained by
Omarchy; its bounded saved state is stored in the XDG state directory.

## Development

Run these checks from the repository root:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p 'test_*.py'
bash tests/adapter-smoke.sh
qmltestrunner -input tests/qml -import .
```

The QML suite requires Omarchy's QML imports and a graphical session.

## License

[MIT](LICENSE)
