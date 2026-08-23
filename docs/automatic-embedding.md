# Automatic Standard-Panel Embedding

## Goal

Embed the large family of ordinary Omarchy bar panels in Drawer without
modifying their installed source or asking every plugin author to rewrite a
panel.

## Supported Source Shapes

The adapter accepts a discovered plugin only when its source uses Omarchy's
standard `KeyboardPanel` component. It supports either:

1. the manifest's `barWidget` entry point directly contains `KeyboardPanel`;
2. that entry point is a small bar widget and the plugin has a sibling
   `Panel.qml` containing `KeyboardPanel`.

This covers the usual first-party panel layout, including direct panels such as
Bluetooth and the bar-widget-plus-panel layout used by Weather and Clock.

## Transformation

`bin/omarchy-drawer-adapt` copies the complete source directory to
`$XDG_CACHE_HOME/omarchy-drawer/<plugin-id>/`. Only the copied panel source is
rewritten:

1. `KeyboardPanel` becomes the local `DrawerPanelHost` component.
2. Its new host fills Drawer rather than mapping a `PanelWindow`.
3. A `drawerHost` property is added to the root `Panel`.
4. `root.controller.hide()` closes Drawer, retaining any cleanup that precedes
   it in the original `close()` method. A generated `drawerDeactivate()` method
   lets Drawer stop the original panel controller on any other Drawer close.
5. The copy's textual `IpcHandler` instances become inert local shims, and the
   inherited `Panel` IPC handler is disabled.

The original QML, user configuration, and `/usr/share/omarchy` remain read-only.
The generated copy is disposable cache data.

## Runtime Contract

Drawer injects the active Omarchy bar, selected plugin item, service singleton,
and its own host reference into the loaded copied panel. It then calls the
panel's existing `open()` method. Existing model code, controls, timers, and
cleanup logic continue to run from the copied panel.

The source panel's bar button remains live in the actual Omarchy bar. Its panel
is not opened by Drawer, and copied IPC endpoints become inert shims so
duplicate handlers cannot race for the same target.

## Non-goals

This is source adaptation, not arbitrary window embedding. A plugin that makes
its own `PanelWindow`, `PopupWindow`, overlay, or custom window role remains a
separate Wayland surface. Wayland does not permit taking that mapped surface and
placing it under Drawer. Such plugins must use native fallback or publish an
explicit `drawerPage`.

## Verification

Run the project-local smoke test:

```bash
bash tests/adapter-smoke.sh
```

It adapts first-party Bluetooth and Weather source trees in temporary
directories, asserting that the standard host, IPC routes, and bar buttons are
rewritten only in generated copies.
