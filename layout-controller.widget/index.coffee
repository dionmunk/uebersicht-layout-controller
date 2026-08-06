# layout-controller.widget
#
# Move widgets around the desktop like windows, and keep them where you put them.
# Renders one small control pill, bottom right. Everything else it does is a side
# effect on the document.
#
# Positions are published as a document-level <style> block, NOT as inline styles.
# Übersicht re-applies each widget's own compiled style on every refresh, which
# wipes inline top/left within seconds (cpu-usage refreshes every second). A rule in
# document.head keyed by the widget's DOM id survives that, and because CSS is
# declarative it applies whenever the widget renders, so widget load order does not
# matter here.
#
# The grid is the one described in LAYOUT.md:
#   - Horizontally a drop snaps to the nearest column (330px pitch from a 10px
#     origin). Widget widths are fixed, so this is exact.
#   - Vertically nothing snaps to a lattice. The column is re-packed top to bottom
#     from each widget's real measured height plus a 10px gap, which is LAYOUT.md's
#     actual vertical model. A row lattice cannot express this layout: the top-lists
#     render ~122px and github ~102px, neither a multiple of UNIT, which is why
#     five of column 1's nine widgets sit off the 90px pitch.
#
# State lives at ~/.config/ubersicht/layout.json, deliberately OUTSIDE the widget
# folder. Übersicht watches that folder, so writing there would reload every widget
# on every drag, and any loose .coffee file inside it loads as a duplicate widget.
#
# That state is per screen:
#
#   { "version": 2, "screens": { "3": { "positions": {...}, "seen": [...] }, ... } }
#
# Übersicht serves one page per screen at /<screenId>/ and runs a separate copy of every
# widget in each, so each copy of this controller owns one slice, keyed by the id in its
# own URL. Screens differ in size and therefore in column count, and a widget shown on
# two screens usually wants a different spot on each. Saves are a jq read-modify-write of
# just that one slice, behind a lock, so two screens cannot erase each other. Version 1
# files (a single flat position map) are migrated on read.
#
# Requires jq for saving, which ships with macOS. Without it the widget still drags and
# packs, it just cannot persist; nothing is corrupted.
#
# ---------------------------------------------------------------------------------
# For other widget authors
# ---------------------------------------------------------------------------------
# Any widget is managed automatically, including third-party ones, with no changes on
# their part: widgets are found by Übersicht's own `.widget` class and keyed by DOM id,
# so index.coffee, index.jsx, index.js and loose-file widgets all work. The contract
# below is entirely optional, and goes in both directions.
#
# A widget can TELL this controller about itself, via attributes on its root element:
#
#   data-layout-manual        Never manage me. This is how a widget declares that it
#                             positions itself (pinned to a corner, centred, and so
#                             on). Equivalent to being listed in `offGrid` below.
#   data-layout-span="2"      I occupy 2 columns. Only needed when the footprint is
#                             wider than what gets painted, or when the widget is
#                             still empty the first time it is measured; otherwise the
#                             span is derived from the measured width.
#
# A widget can READ the grid, via CSS custom properties this controller publishes on
# :root (see publishTokens). Always with a fallback, so the widget still works if this
# controller is not installed:
#
#   --grid-origin     10px    gap from the screen's top and left edges
#   --grid-gap        10px    gap between neighbours
#   --grid-unit       80px    minimum widget height, one row
#   --grid-col        320px   width of one column
#   --grid-col-pitch  330px   column width + gap
#   --grid-columns    7       whole columns that fit on this screen
#
# So a widget sizes itself to the grid with `width: var(--grid-col, 320px)` and gets a
# double-height panel with
# `min-height: calc(var(--grid-unit, 80px) * 2 + var(--grid-gap, 10px))`, instead of
# hardcoding 320px and 170px the way the widgets in this collection currently do.

command: "mkdir -p \"$HOME/.config/ubersicht\"; cat \"$HOME/.config/ubersicht/layout.json\" 2>/dev/null || echo '{}'"

# Enable or disable this widget.
widgetEnabled: true   # true | false

# This widget owns its own state in the page and writes the file itself, so there is
# nothing to poll for. It re-reads on an Übersicht refresh, which is the one moment
# the injected stylesheet is lost and has to be rebuilt.
refreshFrequency: 3600000   # 1 hour

# The desktop grid. Mirrors the tokens in LAYOUT.md; keep the two in step.
grid:
  origin:   10    # EDGE: gap from the screen's top and left edges
  colPitch: 330   # COL (320) + GAP (10)
  gap:      10    # GAP between vertically stacked widgets
  unit:     80    # UNIT: the minimum widget height

# Starting placement mode, for a screen that has never been set:
#   'column' : snap to the nearest column and re-pack it, keeping the gaps exact
#   'free'   : leave the widget exactly where it was dropped, neighbours untouched
# After that the Placement toggle in the move window owns it, remembered per screen.
# Holding Option during a drag still borrows the other mode for that one drop.
snap: 'column'   # 'column' | 'free'

# Widgets that place themselves and must never be packed. Prefer `data-layout-manual`
# on the widget's own root element (see the header); this list is for widgets that
# cannot be edited. Entries are matched as id prefixes, so music.widget is 'music'.
# music is pinned bottom-left by its own CSS; theme-controller renders nothing; this
# widget is its own pill in the corner.
offGrid: ['music', 'theme-controller', 'layout-controller']

style: """
  bottom 10px
  right 10px
  z-index: 9999

  color var(--text, #fff)
  text-shadow: 0 1px 1px rgba(20, 1, 1, 0.2)
  font-family -apple-system, BlinkMacSystemFont, system-ui, sans-serif

  .lc-bar
    display: flex
    gap: 6px
    align-items: center

    // Hidden until the pointer finds it. opacity, not visibility: a hidden element
    // stops hit-testing, so :hover would never fire and it could never come back.
    // (Plain numbers only here. nib overrides `opacity` with a mixin that computes
    // n * 100, which throws on a var() and silently kills the whole widget.)
    opacity: 0
    transition: opacity .18s ease

    // Invisible approach zone. The widget is anchored bottom right, so padding grows
    // the box up and to the left while the buttons stay put in the corner, giving the
    // pointer something to find without moving anything visible.
    padding: 34px 0 0 34px

  .lc-bar:hover
    opacity: 1

  // While unlocked the corner pill goes away entirely: the window below is the whole
  // control surface, and two places to click Done would just be confusing.
  .lc-root.is-unlocked .lc-bar
    display: none

  // The pills borrow the news widget's tab treatment outright, down to the metrics,
  // so they read as the same component: the primary action takes the highlighted-tab
  // colouring and the rest take the resting-tab colouring and its hover.
  // No backdrop blur here, matching those tabs.
  .lc-btn
    flex: none
    white-space: nowrap
    font-size: 9px
    text-transform: uppercase
    font-weight: bold
    letter-spacing: .3px
    border-radius: 7px
    padding: 3px 9px
    cursor: pointer
    user-select: none
    box-shadow: 0 1px 1px rgba(20, 1, 1, .10)
    transition: color .18s ease, background .18s ease

  // Highlighted tab: primary fill, full-strength label.
  .lc-primary
    color: var(--text, #fff)
    background: var(--primary, #FF2D55)

  // Resting tab.
  .lc-secondary
    color: var(--text-secondary, rgba(#fff, .5))
    background: rgba(127, 127, 137, .22)

  .lc-secondary:hover
    color: var(--text, #fff)
    background: rgba(127, 127, 137, .45)

  // --- the move-mode window --------------------------------------------------
  //
  // position:fixed so it escapes this widget's bottom-right anchor and can sit
  // anywhere on screen. left/top are set in JS rather than with a translate-based
  // centring, because the window is draggable and a transform would fight that.
  .lc-window
    display: none
    position: fixed
    width: 380px
    box-sizing: border-box
    // Deliberately stronger than --panel-bg. This is a transient control surface, not
    // an ambient widget: the help text is 11px at weight 300 and has to stay legible
    // over whatever wallpaper or widget it happens to land on. Still a token, so a
    // theme can take it over.
    background: var(--panel-bg-strong, rgba(20, 20, 22, .82))

    // A light hairline, so the window still has a visible edge when it lands on a dark
    // wallpaper or on top of a dark widget. box-sizing is border-box above, so this
    // does not change the 380px width.
    border: 1px solid var(--hairline, rgba(#fff, .125))
    -webkit-backdrop-filter: blur(var(--panel-blur, 48px))
    backdrop-filter: blur(var(--panel-blur, 48px))
    border-radius: 10px
    padding-bottom: 10px

    // Three layers, the way a real window's shadow works: a tight contact shadow that
    // defines the edge, a mid one for the lift, and a broad ambient one that sells the
    // height. A single 22px shadow at .20 read as flat against the desktop.
    // Hardcoded rather than tokenised, matching how every other widget here treats
    // shadows.
    box-shadow: 0 1px 2px rgba(0, 0, 0, .22),
                0 10px 26px rgba(0, 0, 0, .30),
                0 28px 70px rgba(0, 0, 0, .26)

  .lc-root.is-unlocked .lc-window
    display: block

  // The title bar doubles as the drag handle, the way a window's does. Dragging only
  // from here leaves the rest of the window safe to click.
  .lc-win-head
    display: flex
    align-items: baseline
    justify-content: space-between
    gap: 10px
    padding: 9px 10px 8px
    cursor: move
    user-select: none

    // Lifted a shade off the window body so it reads as a title bar rather than just
    // the first line of content. A white scrim rather than a fixed colour, so it
    // lightens whatever the body happens to be under a different theme.
    background: var(--panel-head-bg, rgba(255, 255, 255, .07))
    border-bottom: 1px solid var(--hairline, rgba(#fff, .125))
    // 9px, not 10: the window's 10px radius minus its 1px border is the curve of the
    // inner edge, and matching it stops a sliver of window background showing at the
    // top corners.
    border-radius: 9px 9px 0 0

  .lc-win-title
    font-size: 10px
    text-transform: uppercase
    font-weight: bold

  .lc-win-hint
    font-size: 9px
    font-weight: 300
    color: var(--text-secondary, rgba(#fff, .5))

  // Placement mode, as a segmented control. The active segment takes the primary pill
  // colouring and the other the resting one, so it reads the way the news tabs do.
  .lc-mode
    display: flex
    align-items: center
    gap: 9px
    padding: 10px 10px 0

  // Same width as .lc-key, so the label lines up with the help gutter below it.
  .lc-mode-label
    flex: none
    width: 76px
    font-size: 9px
    text-transform: uppercase
    font-weight: bold
    letter-spacing: .3px
    color: var(--text-secondary, rgba(#fff, .5))

  .lc-seg
    display: flex
    gap: 6px

  .lc-help
    // Top padding gives the first row air below the control above it.
    padding: 10px 10px 0
    display: flex
    flex-direction: column
    gap: 7px

  .lc-help-row
    display: flex
    align-items: baseline
    gap: 9px
    font-size: 11px
    font-weight: 300
    line-height: 1.35

  // Fixed-width gutter so every description starts on the same left edge.
  .lc-key
    flex: none
    width: 76px
    font-size: 9px
    text-transform: uppercase
    font-weight: bold
    letter-spacing: .3px
    color: var(--text-secondary, rgba(#fff, .5))

  // The divider spans the full inner width, matching the title bar's, so the buttons
  // are inset with padding rather than the row being inset with a margin.
  .lc-actions
    display: flex
    gap: 6px
    align-items: center
    margin-top: 10px
    padding: 10px 10px 0
    border-top: 1px solid var(--hairline, rgba(#fff, .125))

  // Done sits apart from the two destructive-ish actions.
  .lc-spacer
    flex: 1
"""

render: -> """
  <div class="lc-root">
    <div class="lc-bar">
      <div class="lc-btn lc-primary lc-toggle">Move</div>
    </div>
    <div class="lc-window">
      <div class="lc-win-head">
        <span class="lc-win-title">Move Widgets</span>
        <span class="lc-win-hint">drag this bar to move this window</span>
      </div>
      <div class="lc-mode">
        <span class="lc-mode-label">Placement</span>
        <div class="lc-seg">
          <div class="lc-btn lc-seg-btn" data-mode="column">Snap to grid</div>
          <div class="lc-btn lc-seg-btn" data-mode="free">Freeform</div>
        </div>
      </div>
      <div class="lc-help">
        <div class="lc-help-row">
          <span class="lc-key">Drag</span>
          <span>Moves a widget. Snap to grid drops it into the nearest column and re-stacks that column with even gaps. Freeform leaves it exactly where you let go.</span>
        </div>
        <div class="lc-help-row">
          <span class="lc-key">⌥ Drag</span>
          <span>Holding Option borrows the other placement mode, just for that one drag.</span>
        </div>
        <div class="lc-help-row">
          <span class="lc-key">Pack</span>
          <span>Re-stacks every column from the top down, closing any uneven gaps.</span>
        </div>
        <div class="lc-help-row">
          <span class="lc-key">Reset</span>
          <span>Returns every widget to the position set in its own file. Undoes everything here.</span>
        </div>
      </div>
      <div class="lc-actions">
        <div class="lc-btn lc-secondary lc-pack">Pack</div>
        <div class="lc-btn lc-secondary lc-reset">Reset</div>
        <div class="lc-spacer"></div>
        <div class="lc-btn lc-primary lc-done">Done</div>
      </div>
    </div>
  </div>
"""

# --- grid helpers ------------------------------------------------------------

# Positions are keyed by the raw DOM id, the only identifier that is stable across
# every widget type. Übersicht builds it from the widget's file path, so
# cpu-usage.widget/index.coffee becomes cpu-usage-widget-index-coffee, and a JSX
# widget becomes foo-widget-index-jsx.
keyOf: (el) -> el.id

# Widgets that place themselves and are never managed.
#
# The supported way for a widget to opt out is `data-layout-manual` on its root
# element, which any widget author can add without this controller knowing about it.
# The `offGrid` list is the fallback for widgets that cannot be edited to declare it.
# Entries there are matched as id prefixes, so use the fullest unambiguous one:
# 'music' would also claim a hypothetical music-visualizer.
isOffGrid: (el) ->
  return true if el.hasAttribute? 'data-layout-manual'
  for name in @offGrid
    return true if el.id is name or el.id.indexOf("#{name}-") is 0
  false

# How many columns a widget occupies. Derived from its measured width so nothing has
# to be declared: 320px is one column, 650px is two. `data-layout-span` on the root
# element wins when present, for a widget whose footprint is wider than what it
# paints, or one that is still empty when first measured.
spanOf: (width, el = null) ->
  declared = parseInt el?.getAttribute?('data-layout-span'), 10
  return Math.max 1, declared if declared > 0
  Math.max 1, Math.round((width + @grid.gap) / @grid.colPitch)

# Nearest column for an x position, and that column's left edge.
columnOf: (x) -> Math.max 0, Math.round((x - @grid.origin) / @grid.colPitch)
leftOf: (col) -> @grid.origin + col * @grid.colPitch

# How many whole columns fit on this screen: origin + n·colPitch - gap ≤ width - origin.
columnCount: ->
  Math.max 1, Math.floor((window.innerWidth - 2 * @grid.origin + @grid.gap) / @grid.colPitch)

# Every widget this controller manages.
#
# Found by Übersicht's own `.widget` class, NOT by an id pattern. The id is the file
# path, so matching on it would only ever catch widgets that happen to use
# index.coffee and would silently ignore any third-party widget written as index.jsx
# (the modern format), index.js, or a loose .coffee/.js file. The class is applied to
# every widget container regardless of type.
widgetEls: ->
  els = []
  for el in document.querySelectorAll('#uebersicht .widget')
    continue unless el.id                # nothing to key a position on
    continue if @isOffGrid el
    continue if el.offsetHeight is 0     # disabled or empty: occupies no slot
    els.push el
  els

# Measure the current layout. Heights come from the DOM rather than LAYOUT.md's
# hand-measured figures, so a content change can never leave the packing stale.
boxes: ->
  out = []
  for el in @widgetEls()
    r = el.getBoundingClientRect()
    out.push
      key:    @keyOf(el)
      col:    @columnOf(r.left)
      span:   @spanOf(r.width, el)
      top:    r.top
      height: r.height
  out

# Re-stack top to bottom, every widget sitting GAP below the one above it. This is
# LAYOUT.md's formula, top = EDGE + Σ (max(UNIT, realHeight) + GAP), which is why gaps
# stay exact no matter what a widget's content does to its height.
#
# Greedy, in current top order, tracking the next free y per column. A widget spanning
# more than one column has to clear every column it covers and then advance all of
# them: otherwise github on its two-column `year` span and a single-column widget
# would both be placed into the same space.
pack: (boxes) ->
  out = {}
  nextY = {}
  freeAt = (c) => nextY[c] ? @grid.origin
  ordered = boxes.slice().sort (a, b) -> (a.top - b.top) or (a.col - b.col)
  for b in ordered
    span = Math.max 1, (b.span ? 1)
    top = @grid.origin
    for c in [b.col...(b.col + span)]
      top = Math.max top, freeAt(c)
    out[b.key] =
      left: @leftOf(b.col)
      top:  top
    # Round the height before accumulating. The top-lists measure 122.23px, and left
    # raw that fraction compounds down the column (0.23 → 0.47 → 0.70), so a pack
    # would nudge widgets a pixel even when nothing had actually moved. Rounding
    # first makes packing an exact no-op on an already-tidy column.
    advance = top + Math.max(@grid.unit, Math.round(b.height)) + @grid.gap
    nextY[c] = advance for c in [b.col...(b.col + span)]
  out

# --- the override stylesheet -------------------------------------------------

styleEl: ->
  el = document.getElementById('layout-controller-rules')
  unless el
    el = document.createElement 'style'
    el.id = 'layout-controller-rules'
    document.head.appendChild el
  el

# Publish positions. `floating` is the widget under the cursor mid-drag: it lifts
# above the others and drops its transition so it tracks the pointer exactly.
writeRules: (positions, floating = null) ->
  rules = []
  for key, p of (positions ? {})
    parts = ["left: #{Math.round(p.left)}px !important",
             "top: #{Math.round(p.top)}px !important",
             # Neutralise the other two anchors. A widget that positions itself with
             # bottom/right (music does, and plenty of third-party widgets do) would
             # otherwise end up with all four set at once, which stretches an
             # auto-sized absolute box instead of moving it.
             'right: auto !important',
             'bottom: auto !important']
    if key is floating
      parts.push 'z-index: 9998 !important'
      parts.push 'transition: none !important'
      # The hand stays closed for as long as the widget is held.
      parts.push 'cursor: grabbing !important'
    rules.push "##{CSS.escape(key)} { #{parts.join('; ')} }"
  if @unlocked
    ring = 'var(--primary, #FF2D55)'
    for el in @widgetEls()
      sel = "##{CSS.escape(el.id)}"
      # Drag the widget as a whole, and stop clicks reaching what is inside it: news
      # headlines and the weather advisory are clickable and would fire mid-drag.
      # The radius goes on the container, which is transparent and carries none of its
      # own, so the hover ring below follows the panel's rounded corners rather than
      # boxing it into a rectangle. It is set for the whole time move mode is unlocked,
      # not just on :hover — the shadow fades out over .15s, so a radius that belonged
      # to the hover state would snap back to square while the ring was still visible.
      rules.push "#{sel} { cursor: grab !important; border-radius: 10px !important }"
      rules.push "#{sel} > * { pointer-events: none !important }"
      # Hover affordance, so it is obvious which widget the grab cursor will pick up: a
      # ring in the theme accent, plus a lift.
      rules.push "#{sel}:hover { box-shadow: 0 0 0 2px #{ring}, 0 10px 26px rgba(0, 0, 0, .28) !important }"
      rules.push "#{sel} { transition: top .12s ease, left .12s ease, box-shadow .15s ease }" unless el.id is floating
  @styleEl().textContent = rules.join('\n')

# --- column guides -----------------------------------------------------------

# A full-screen overlay marking the columns, so the drop target is visible while
# dragging. It hangs off document.body because this widget is a pill in the corner
# and cannot contain a full-screen layer.
guidesEl: ->
  el = document.getElementById('layout-controller-guides')
  unless el
    el = document.createElement 'div'
    el.id = 'layout-controller-guides'
    el.style.display = 'none'
  # Set every time, not just on create: an element left over from a previous version
  # of this widget keeps its old inline styles, since Übersicht reloads the code but
  # not the document.
  el.style.position = 'fixed'
  el.style.inset = '0'
  el.style.pointerEvents = 'none'
  # Deliberately auto, not a number. Every widget is position:absolute with
  # z-index:auto in the same stacking context, and positioned elements with auto
  # paint in tree order, so being the container's first child puts the guides
  # *behind* the widgets. Given a z-index above them, the layer tints the desktop.
  el.style.zIndex = ''
  # Übersicht appends widgets as it loads them, so the layer has to be re-seated as
  # the first child rather than just appended once.
  host = document.getElementById('uebersicht') or document.body
  unless el.parentElement is host and el is host.firstChild
    host.insertBefore el, host.firstChild
  el

drawGuides: ->
  el = @guidesEl()
  # Hidden in freeform: nothing snaps to the columns, so drawing them would imply a
  # constraint that is not there.
  unless @unlocked and @placement() is 'column'
    el.style.display = 'none'
    return
  # Drawn in the theme accent, not white: a white guide at low opacity is invisible
  # against a light desktop, which is exactly what happened the first time. Pink
  # reads on either, and the whole layer is dimmed with opacity on the container.
  # Edges only, no fill. This layer sits above the widgets, so a filled band tints
  # everything under it and washes the whole desktop out.
  w = @grid.colPitch - @grid.gap
  edge = 'var(--primary, #FF2D55)'
  html = ''
  for c in [0...@columnCount()]
    html += "<div style=\"position:absolute;top:0;bottom:0;left:#{@leftOf(c)}px;width:#{w}px;box-sizing:border-box;border-left:1px dashed #{edge};border-right:1px dashed #{edge}\"></div>"
  el.innerHTML = html
  el.style.opacity = '.5'
  el.style.display = 'block'

# --- the grid contract for other widgets -------------------------------------

# Publish the grid as CSS custom properties on :root, exactly the way
# theme-controller publishes theme tokens. Any widget can then size itself to the grid
# with `width: var(--grid-col, 320px)` rather than hardcoding 320px, and there is one
# source of truth for the numbers instead of every widget carrying its own copy.
#
# Every token has to be consumed with a fallback, so a widget still works on a desktop
# where this controller is not installed. That is the same rule the rest of the
# collection follows for theme tokens.
publishTokens: ->
  root = document.documentElement
  root.style.setProperty '--grid-origin', "#{@grid.origin}px"
  root.style.setProperty '--grid-gap', "#{@grid.gap}px"
  root.style.setProperty '--grid-unit', "#{@grid.unit}px"
  root.style.setProperty '--grid-col-pitch', "#{@grid.colPitch}px"
  root.style.setProperty '--grid-col', "#{@grid.colPitch - @grid.gap}px"
  root.style.setProperty '--grid-columns', "#{@columnCount()}"

# --- persistence -------------------------------------------------------------

# Which screen this page is rendering.
#
# Übersicht serves one page per screen at /<screenId>/, and runs a separate copy of
# every widget in each, so this is the only identifier available: nothing on the
# document says which screen it is, and window.screen reports the same values in all of
# them. The viewport-size fallback covers an unexpected route; two screens of identical
# size would collide there, which is why the URL is preferred.
screenId: ->
  m = location.pathname.match /(\d+)/
  return m[1] if m
  "w#{window.innerWidth}x#{window.innerHeight}"

# Positions and `seen` are per screen, keyed by screenId. Screens differ in size, so
# they differ in column count, and a widget shown on two screens usually wants a
# different spot on each.
# This screen's state, as written to disk.
slice: ->
  positions: @saved ? {}
  # Which widgets this screen has already met. Without it there is no way to tell a
  # brand new widget from one that simply has no saved position yet.
  seen:      @seen ? []
  # Where the move-mode window was last left on this screen.
  panel:     @panel ? null
  # Placement mode chosen on this screen, via the window's toggle.
  mode:      @placement()

persist: ->
  # Debounced, since several saves can land in the same tick, e.g. a burst of mutations
  # while widgets are still loading.
  #
  # The payload is built when the timer FIRES, not now. Capturing it here meant a save
  # queued just before a Reset would fire afterwards and write back the very state the
  # reset had just cleared.
  clearTimeout @_persistTimer
  @_persistTimer = setTimeout (=> @writeState @slice()), 250

# Merge this screen's slice into the shared state file.
#
# Three separate hazards here, all of them real:
#
#  1. Two screens must not clobber each other. Each one only knows its own slice, so
#     writing the whole file from one screen would erase the other's. jq does a
#     read-modify-write of just `.screens[<id>]`.
#  2. Two writers must not interleave. An earlier version redirected straight into the
#     file and produced a valid JSON document followed by the tail of a longer one.
#     Everything now goes to a per-process temp and is renamed, which is atomic.
#  3. Two screens can genuinely write at the same moment, e.g. an all-screens widget
#     appears and both screens centre it at once. Without a lock that is a lost update,
#     since both read the file before either writes. The mkdir mutex is crude but
#     atomic, and it gives up rather than hanging if a stale lock is left behind.
writeState: (slice) ->
  b64 = btoa unescape encodeURIComponent JSON.stringify(slice)
  id  = @screenId()
  fetch '/run/',
    method: 'POST'
    body: """
      DIR="$HOME/.config/ubersicht"; F="$DIR/layout.json"; L="$DIR/layout.lock"
      command -v jq >/dev/null 2>&1 || exit 0
      mkdir -p "$DIR"
      i=0; while [ $i -lt 20 ]; do mkdir "$L" 2>/dev/null && break; i=$((i+1)); sleep 0.1; done
      [ -f "$F" ] || echo '{"version":2,"screens":{}}' > "$F"
      jq -e . "$F" >/dev/null 2>&1 || echo '{"version":2,"screens":{}}' > "$F"
      cp "$F" "$F.bak" 2>/dev/null
      echo '#{b64}' | base64 --decode > "$DIR/slice.$$.json"
      jq --arg id '#{id}' --slurpfile s "$DIR/slice.$$.json" \
         '.version = 2 | .screens[$id] = $s[0] | del(.positions, .seen)' "$F" > "$F.$$.tmp" \
         && mv "$F.$$.tmp" "$F"
      rm -f "$DIR/slice.$$.json" "$F.$$.tmp"
      rmdir "$L" 2>/dev/null
    """

# Drop just this screen's slice, leaving other screens alone. Every widget here falls
# back to the position compiled into its own source, and nothing had to be edited to get
# there, so this stays the first level of rollback.
reset: ->
  # Cancel any queued save before clearing: otherwise it fires a moment later and puts
  # the slice straight back.
  clearTimeout @_persistTimer
  @_persistTimer = null
  @saved = {}
  @seen = []
  @panel = null
  # The slice is deleted below, mode included, so drop it here too rather than leaving
  # memory claiming a mode that is no longer on disk.
  @mode = @snap
  @paintMode @_domEl
  @writeRules {}
  @drawGuides()
  id = @screenId()
  fetch '/run/',
    method: 'POST'
    body: """
      DIR="$HOME/.config/ubersicht"; F="$DIR/layout.json"; L="$DIR/layout.lock"
      command -v jq >/dev/null 2>&1 || exit 0
      [ -f "$F" ] || exit 0
      i=0; while [ $i -lt 20 ]; do mkdir "$L" 2>/dev/null && break; i=$((i+1)); sleep 0.1; done
      cp "$F" "$F.bak" 2>/dev/null
      jq --arg id '#{id}' 'del(.screens[$id])' "$F" > "$F.$$.tmp" && mv "$F.$$.tmp" "$F"
      rm -f "$F.$$.tmp"
      rmdir "$L" 2>/dev/null
    """

# Tidy every column from measured heights, without moving anything between columns.
# This is the fix for drift, e.g. after a content change alters a widget's height.
packAll: ->
  @saved = @pack @boxes()
  @writeRules @saved
  @persist()

# --- new widgets -------------------------------------------------------------

# Where a brand new widget lands: the middle of the screen, offset by its own size so
# it is genuinely centred, with a cascade so several arriving at once do not stack
# exactly on top of each other.
centreFor: (el, index = 0) ->
  r = el.getBoundingClientRect()
  step = 24 * index
  left: Math.max 0, Math.round((window.innerWidth - r.width) / 2 + step)
  top:  Math.max 0, Math.round((window.innerHeight - r.height) / 2 + step)

# Every widget with an id, including ones that render nothing. Deliberately broader
# than widgetEls: a disabled widget still counts as seen, so flipping widgetEnabled
# back on later does not make it look new and fling it to the centre.
allWidgetIds: ->
  (el.id for el in document.querySelectorAll('#uebersicht .widget') when el.id)

# Put widgets this controller has never met before at centre screen, so a newly
# installed widget announces itself instead of appearing wherever its own source
# happens to place it, which is usually underneath something already there.
#
# The `seen` list is what makes this safe. On the very first run there is no list, so
# everything currently on the desktop is recorded and nothing moves: installing this
# controller must never rearrange a desktop that already works.
# Whether this screen has anything to manage at all.
#
# Übersicht renders every widget once per screen, and each widget can be set to appear
# on some screens and not others. This controller defaults to all screens, while the
# widgets it manages are main-screen only, so on a secondary screen it sees an empty
# desktop.
#
# Without this guard that is destructive, not merely useless: the secondary screen
# would take the first-run branch, record "I have seen one widget" (itself), and write
# it. The main screen would then read a non-empty `seen`, skip its own first-run guard,
# conclude that all sixteen real widgets are brand new, and centre the lot in a
# cascade. So a screen with nothing to manage does nothing and writes nothing.
manages: -> @widgetEls().length > 0

# Hide the control pill on a screen with nothing to manage, so a second monitor does
# not carry a Move button that has nothing to move.
syncVisibility: (domEl) ->
  return unless domEl
  $(domEl).css 'display', (if @manages() then '' else 'none')

placeNewWidgets: ->
  return unless @manages()
  ids = @allWidgetIds()
  return if ids.length is 0
  unless @seen?.length
    @seen = ids
    @persist()          # remember them, but move nothing
    return
  fresh = (el for el in @widgetEls() when el.id not in @seen)
  @seen = @seen.concat (id for id in ids when id not in @seen)
  return if fresh.length is 0
  @saved ?= {}
  # Centred unsnapped whatever `snap` is set to: the point is to be noticed, not to be
  # tidy. Dragging it afterwards applies whichever mode is in force.
  @saved[el.id] = @centreFor(el, i) for el, i in fresh
  @writeRules @saved
  @persist()

# Übersicht adds a widget's element as soon as its folder appears, which can be long
# after this controller's own update() has run, so watch for it. childList only and no
# subtree: widgets arrive as wrappers directly under #uebersicht, whereas watching the
# subtree would fire on every content refresh instead (cpu-usage ticks every second).
watchForNewWidgets: ->
  return if @_observer
  host = document.getElementById('uebersicht')
  return unless host
  @_observer = new MutationObserver =>
    clearTimeout @_newTimer
    # Debounced: the wrapper and the widget's first paint arrive as separate
    # mutations, and its size only means anything once it has painted.
    @_newTimer = setTimeout (=>
      @placeNewWidgets()
      @syncVisibility @_domEl
    ), 800
  @_observer.observe host, childList: true

# --- controls ----------------------------------------------------------------

setUnlocked: (state, domEl) ->
  @unlocked = state
  $(domEl).find('.lc-root').toggleClass 'is-unlocked', state
  @positionWindow domEl if state
  @drawGuides()
  @writeRules @saved

# Place the move-mode window. Centred horizontally and 20% down the screen the first
# time; after that, wherever it was last left. Measured rather than calculated from the
# CSS width, so the padding and content can change without this drifting.
positionWindow: (domEl) ->
  win = $(domEl).find('.lc-window')[0]
  return unless win
  r = win.getBoundingClientRect()
  if @panel?.left? and @panel?.top?
    left = @panel.left
    top  = @panel.top
  else
    left = (window.innerWidth - r.width) / 2
    top  = window.innerHeight * 0.2
  # Keep it on screen even if the saved spot came from a larger display.
  left = Math.min left, window.innerWidth - r.width
  top  = Math.min top, window.innerHeight - 40
  win.style.left = "#{Math.round Math.max(0, left)}px"
  win.style.top  = "#{Math.round Math.max(0, top)}px"

# Light up whichever segment matches the current mode.
paintMode: (domEl) ->
  current = @placement()
  $(domEl).find('.lc-seg-btn').each (i, el) ->
    active = $(el).attr('data-mode') is current
    $(el).toggleClass('lc-primary', active).toggleClass('lc-secondary', not active)

# Switch placement mode. Persisted, so a screen keeps whichever mode you last chose.
setMode: (mode, domEl) ->
  @mode = if mode is 'free' then 'free' else 'column'
  @paintMode domEl
  # The column guides only mean something when drops actually snap to them.
  @drawGuides()
  @persist()

bindControls: (domEl) ->
  return if @_controlsBound
  @_controlsBound = true
  self = this
  $(domEl).find('.lc-toggle').on 'click', -> self.setUnlocked true, domEl
  $(domEl).find('.lc-done').on 'click', -> self.setUnlocked false, domEl
  $(domEl).find('.lc-pack').on 'click', -> self.packAll()
  $(domEl).find('.lc-reset').on 'click', -> self.reset()
  $(domEl).find('.lc-seg-btn').on 'click', -> self.setMode $(this).attr('data-mode'), domEl
  # Paint the toggle's initial state without saving: nothing has changed yet.
  @mode = @placement()
  @paintMode domEl
  @setUnlocked false, domEl

# --- dragging ----------------------------------------------------------------

# Bound on document, once: a fast drag can outrun the element under the pointer, and
# native mouse events on the widget itself would be lost as soon as that happens.
bindDrag: ->
  return if @_dragBound
  @_dragBound = true
  document.addEventListener 'mousedown', (ev) => @onDown ev
  document.addEventListener 'mousemove', (ev) => @onMove ev
  document.addEventListener 'mouseup', (ev) => @onUp ev

# The managed widget an event landed in, if any. Matched by Übersicht's `.widget`
# class so it works for every widget type, not just index.coffee ones.
widgetFrom: (target) ->
  node = target
  while node and node isnt document.body
    if node.classList?.contains('widget') and node.id
      return null if @isOffGrid node
      return node
    node = node.parentNode
  null

# The placement mode in force. The Placement toggle owns this; `snap` is only the
# starting value for a screen that has never set one.
placement: -> if (@mode ? @snap) is 'free' then 'free' else 'column'

# Whether this particular drop should be placed freely. Option inverts the current
# mode for one drag, so the other behaviour is always reachable without flipping the
# toggle back and forth.
isFree: (ev) ->
  free = @placement() is 'free'
  free = not free if ev.altKey
  free

# Looked up fresh every time rather than cached, since Übersicht replaces the widget's
# DOM whenever it re-renders.
windowEl: -> $(@_domEl).find('.lc-window')[0]

# The move-mode window's title bar, if the event landed on it.
windowHandleFrom: (target) ->
  node = target
  while node and node isnt document.body
    return node if node.classList?.contains 'lc-win-head'
    node = node.parentNode
  null

onDown: (ev) ->
  return unless @unlocked
  # The window's own drag takes priority. It is not a managed widget, so widgetFrom
  # would return null for it anyway, but this has to run before that check to claim
  # the event.
  if @windowHandleFrom ev.target
    win = @windowEl()
    return unless win
    r = win.getBoundingClientRect()
    ev.preventDefault()
    # Only the offsets are kept, not the element. A widget re-render mid-drag replaces
    # the DOM, and a cached node would go stale: it still takes the style writes, so the
    # drag looks fine, but it measures 0x0 at the end and saves a nonsense position.
    @winDrag =
      dx: ev.clientX - r.left
      dy: ev.clientY - r.top
    return
  el = @widgetFrom ev.target
  return unless el
  ev.preventDefault()
  r = el.getBoundingClientRect()
  @drag =
    key:    @keyOf(el)
    dx:     ev.clientX - r.left
    dy:     ev.clientY - r.top
    left:   r.left
    top:    r.top
    span:   @spanOf(r.width, el)
    height: r.height
  # Measured once at mousedown: the others' pre-drag tops are what decide where the
  # dragged widget inserts into a column.
  @others = (b for b in @boxes() when b.key isnt @drag.key)

onMove: (ev) ->
  if @winDrag
    win = @windowEl()
    return unless win
    left = Math.max 0, ev.clientX - @winDrag.dx
    top  = Math.max 0, ev.clientY - @winDrag.dy
    win.style.left = "#{Math.round left}px"
    win.style.top  = "#{Math.round top}px"
    return
  return unless @drag
  d = @drag
  d.left = Math.max 0, ev.clientX - d.dx
  d.top  = Math.max 0, ev.clientY - d.dy
  if @isFree ev
    # Free placement: nothing else moves, so only the dragged widget's rule changes.
    positions = {}
    positions[k] = v for k, v of (@saved ? {})
  else
    # Grid placement: pack the others around where this one would land.
    positions = @pack @others.concat [@projected()]
  # Either way the dragged widget stays unsnapped so it never jumps out from under
  # the pointer; the snap happens on drop.
  positions[d.key] =
    left: d.left
    top:  d.top
  @writeRules positions, d.key

onUp: (ev) ->
  if @winDrag
    @winDrag = null
    win = @windowEl()
    r = win?.getBoundingClientRect()
    # A zero-size rect means the window is gone or detached (a re-render landed
    # mid-drag), and saving 0,0 would park it in the corner next time. Drop the save.
    return unless r?.width
    # Remember where it was left, so it reopens there.
    @panel =
      left: Math.round r.left
      top:  Math.round r.top
    @persist()
    return
  return unless @drag
  d = @drag
  free = @isFree ev
  projected = @projected()
  @drag = null
  if free
    # Drop it exactly where the pointer left it and leave every other widget alone.
    next = {}
    next[k] = v for k, v of (@saved ? {})
    next[d.key] =
      left: Math.round d.left
      top:  Math.round d.top
    @saved = next
  else
    # Snap to the column and re-pack around it.
    @saved = @pack @others.concat [projected]
  @writeRules @saved
  @persist()

# The dragged widget as a box, at the column, span and height it would land with.
projected: ->
  key:    @drag.key
  col:    @columnOf @drag.left
  span:   @drag.span
  top:    @drag.top
  height: @drag.height

# --- lifecycle ---------------------------------------------------------------

update: (output, domEl) ->
  if not @widgetEnabled
    $(domEl).css 'display', 'none'
    return
  $(domEl).css 'display', ''
  try
    parsed = JSON.parse((output or '').trim() or '{}')
  catch e
    parsed = {}
  parsed = {} unless parsed and typeof parsed is 'object'
  if parsed.version >= 2
    # Per-screen state. A screen with no slice yet starts empty, which puts it into the
    # first-run branch: it records what is there and moves nothing.
    slice  = parsed.screens?[@screenId()] ? {}
    @saved = slice.positions ? {}
    @seen  = slice.seen ? []
    @panel = slice.panel ? null
    @mode  = slice.mode ? @snap
  else
    # A single-screen file (version 1, or older still with no version at all). Adopt its
    # positions as this screen's, since only a screen with widgets to manage ever wrote
    # one. `seen` is deliberately dropped so the first-run guard re-records the current
    # desktop rather than trusting a list that predates per-screen tracking.
    @saved = parsed.positions ? parsed
    @seen  = []
  @publishTokens()
  # Set before bindControls, since the window drag reads it to find the window.
  @_domEl = domEl
  # Saved positions are applied verbatim, never re-packed on load: packing needs
  # measured heights, and at load time widgets may not have rendered yet.
  @writeRules @saved
  @bindControls domEl
  @bindDrag()
  @watchForNewWidgets()
  # Deferred: other widgets may well not have rendered when this controller updates,
  # so both the new-widget scan and the has-anything-to-manage check have to wait.
  @_domEl = domEl
  clearTimeout @_initialScan
  @_initialScan = setTimeout (=>
    @placeNewWidgets()
    @syncVisibility @_domEl
  ), 1500
