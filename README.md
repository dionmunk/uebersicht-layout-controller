# Layout Controller

Move [Übersicht](http://tracesof.net/uebersicht) widgets around the desktop like
windows, and keep them where you put them.

![Layout Controller](screenshot.png)

Übersicht positions every widget absolutely from its own CSS, so rearranging your
desktop normally means editing files and reloading. This widget makes it direct: move
your pointer to the **bottom-right corner of the screen**, click **Move**, and drag
widgets where you want them. Positions persist across reloads, restarts and
refreshes, per screen.

It manages **any** widget, including third-party ones, with no changes on their part.
Widgets are found by Übersicht's own `.widget` class and keyed by DOM id, so
`index.coffee`, `index.jsx`, `index.js` and loose-file widgets all work.

## Install

Drop `layout-controller.widget` into your Übersicht widgets folder. There is nothing
to build and nothing to configure.

Saving positions uses `jq`, which ships with macOS. Without it the widget still drags
and packs, it just cannot persist; nothing is corrupted.

## Finding the Move button

**Move your pointer to the bottom-right corner of the screen.** That is the entire
interface when the desktop is locked: one small pill, 10px in from the bottom and
right edges.

![The Move button in the bottom-right corner](screenshots/move-button.png)

It is invisible until your pointer gets close, deliberately, so it does not sit on
your wallpaper all day. There is a generous approach zone around it, so you do not
have to hit it precisely, just move into the corner and it fades in. Click it and the
move window below opens.

If you have a widget of your own parked in that corner, the pill sits above it at
`z-index: 9999`.

## Using it

| Control | What it does |
|---|---|
| **Move** | Bottom-right corner of the screen. Unlocks the desktop and opens the move window. The corner pill hides while unlocked, so there is only ever one place to click Done |
| **Drag** | Moves a widget |
| **⌥ Drag** | Borrows the other placement mode for that one drag |
| **Pack** | Re-stacks every column from the top down, closing uneven gaps |
| **Reset** | Returns every widget to the position set in its own file, undoing everything |
| **Done** | Locks the desktop again |

The move window itself is draggable by its title bar, so it can be pushed out of the
way of whatever you are arranging.

### Placement modes

| Mode | Behaviour |
|---|---|
| **Snap to grid** (default) | A drop snaps to the nearest column and re-packs that column top to bottom with even gaps |
| **Freeform** | The widget stays exactly where you let go, and nothing else moves |

The choice is remembered per screen, and holding **Option** during a drag borrows the
other mode just for that drop.

Horizontal snapping is exact, because widget widths are fixed: columns sit on a
330px pitch from a 10px origin. Vertically nothing snaps to a lattice. The column is
re-packed from each widget's *real measured height* plus a 10px gap, because a row
lattice cannot express a real desktop: top-lists render about 122px and a
contributions graph about 102px, neither a multiple of the 80px base unit.

## The grid

The default grid matches the one this widget's companion collection uses:

| Token | Value | Meaning |
|-------|-------|---------|
| `EDGE` | `10px` | Gap from the screen's top and left edges |
| `GAP` | `10px` | Gap between neighbours |
| `COL` | `320px` | Width of one column |
| `UNIT` | `80px` | Minimum widget height, one row |

Column left positions are `EDGE + col · (COL + GAP)`, so 10 / 340 / 670 / 1000 and so
on. Vertical placement is `top(row) = EDGE + Σ (max(UNIT, realHeight) + GAP)` for
every row above. Retune all of it in the `grid` option at the top of `index.coffee`.

## For other widget authors

The contract is entirely optional and goes in both directions. Any widget is managed
automatically without it.

### Telling the controller about your widget

Attributes on your widget's root element:

| Attribute | Meaning |
|---|---|
| `data-layout-manual` | Never manage me. This is how a widget declares that it positions itself, pinned to a corner or centred |
| `data-layout-span="2"` | I occupy 2 columns. Only needed when the footprint is wider than what gets painted, or when the widget is still empty the first time it is measured. Otherwise the span is derived from the measured width |

Set them in `afterRender`:

```coffee
afterRender: (domEl) ->
  domEl.setAttribute('data-layout-manual', '')
```

### Reading the grid from your widget

The controller publishes these on `:root`. Always use a fallback so your widget still
works when the controller is not installed:

| Custom property | Default |
|---|---|
| `--grid-origin` | `10px` |
| `--grid-gap` | `10px` |
| `--grid-unit` | `80px` |
| `--grid-col` | `320px` |
| `--grid-col-pitch` | `330px` |
| `--grid-columns` | whole columns that fit this screen |

So instead of hardcoding sizes:

```coffee
width: var(--grid-col, 320px)
min-height: calc(var(--grid-unit, 80px) * 2 + var(--grid-gap, 10px))
```

A canvas widget cannot inherit custom properties, so it has to resolve them in JS with
`getComputedStyle(document.documentElement).getPropertyValue('--grid-col')`.

## How it works

**Positions are published as a document-level `<style>` block, not as inline styles.**
Übersicht re-applies each widget's own compiled style on every refresh, which wipes
inline `top`/`left` within seconds for anything that refreshes quickly. A rule in
`document.head` keyed by the widget's DOM id survives that, and because CSS is
declarative it applies whenever the widget renders, so widget load order does not
matter.

**State lives at `~/.config/ubersicht/layout.json`, deliberately outside the widget
folder.** Übersicht watches its widgets folder, so writing state there would reload
every widget on every drag, and any loose `.coffee` file inside it loads as a
duplicate widget.

**That state is per screen:**

```json
{ "version": 2, "screens": { "3": { "positions": {}, "seen": [] } } }
```

Übersicht serves one page per screen at `/<screenId>/` and runs a separate copy of
every widget in each, so each copy of the controller owns one slice, keyed by the id
in its own URL. Screens differ in size and therefore in column count, and a widget
shown on two screens usually wants a different spot on each. Saves are a `jq`
read-modify-write of just that one slice, behind a lock, so two screens cannot erase
each other. Version 1 files, a single flat position map, are migrated on read.

## Options

At the top of [`index.coffee`](layout-controller.widget/index.coffee):

| Option | Default | Meaning |
|---|---|---|
| `widgetEnabled` | `true` | Turn the whole widget off |
| `grid` | `{ origin: 10, colPitch: 330, gap: 10, unit: 80 }` | The desktop grid |
| `snap` | `'column'` | Starting placement mode for a screen that has never been set. The window's toggle owns it after that |
| `offGrid` | `['music', 'theme-controller', 'layout-controller']` | Widgets that place themselves and must never be packed. Matched as id prefixes. Prefer `data-layout-manual` on the widget itself; this list is for widgets you cannot edit |

## Companion widgets

Part of a collection of Übersicht widgets that share this grid and a common panel
treatment:

- [Music](https://github.com/dionmunk/uebersicht-music)
- [Visualizer](https://github.com/dionmunk/uebersicht-visualizer)
- [Theme Controller](https://github.com/dionmunk/uebersicht-theme-controller)
- [Weather](https://github.com/dionmunk/uebersicht-weather)
- [News](https://github.com/dionmunk/uebersicht-news)
- [CPU](https://github.com/dionmunk/uebersicht-cpu-usage) ·
  [Memory](https://github.com/dionmunk/uebersicht-memory-usage) ·
  [Storage](https://github.com/dionmunk/uebersicht-storage-usage) ·
  [Network](https://github.com/dionmunk/uebersicht-network-throughput)
- [GitHub Contributions](https://github.com/dionmunk/uebersicht-github-contributions)

## License

[CC BY-NC 4.0](LICENSE)
