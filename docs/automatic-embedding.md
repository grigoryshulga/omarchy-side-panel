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

`bin/omarchy-drawer-adapt` copies the complete source directory to an immutable
fingerprinted path below `$XDG_CACHE_HOME/omarchy-drawer/`. It never removes or
reuses a caller-selected output directory. Only the copied panel source is
rewritten:

1. `KeyboardPanel` becomes the local `DrawerPanelHost` component.
2. Its new host fills Drawer rather than mapping a `PanelWindow`.
3. A `drawerHost` property is added to the root `Panel`.
4. The original `close()` implementation is not rewritten. On a panel-originated
   close, `DrawerPanelHost` notifies Drawer after the original cleanup runs. On
   a Drawer-originated close, Drawer invokes that original `close()` exactly
   once.
5. Syntactically identified `IpcHandler` and bar-button instances become inert
   local shims, and the inherited `Panel` IPC handler is disabled.

The original QML, user configuration, and `/usr/share/omarchy` remain read-only.
The generated copy is disposable cache data. The adapter rejects symlinks,
special files, ambiguous panel shapes, multiple standard hosts, and mapped
window types rather than applying a best-effort transformation.

## Runtime Contract

Drawer injects the active Omarchy bar, the plugin's native settings when they
can be resolved from its live widget, service singleton, and its own host
reference into the loaded copied panel. It then calls the panel's existing
`open()` method. Existing model code, controls, timers, and cleanup logic
continue to run from the copied panel.

The source panel's bar button remains live in the actual Omarchy bar. The copied
button and copied IPC endpoints become inert shims so duplicate handlers cannot
race for the same target. Copied panel models and timers are still independent;
plugin authors should prefer an explicit `drawerPage` for expensive or shared
background work.

## Non-goals

This is source adaptation, not arbitrary window embedding. A plugin that makes
its own `PanelWindow`, `PopupWindow`, overlay, or custom window role remains a
separate Wayland surface. Wayland does not permit taking that mapped surface and
placing it under Drawer. Such plugins must use native fallback or publish an
explicit `drawerPage`.

## Verification

Run the project-local checks:

```bash
bash tests/adapter-smoke.sh
python3 -m unittest tests/test_adapter.py
qmltestrunner -input tests/qml -import .
```

The smoke test adapts first-party Bluetooth and Weather source trees in a
temporary cache and parses the generated QML. The Python suite uses hermetic
fixtures for source-shape and filesystem-safety regressions.
