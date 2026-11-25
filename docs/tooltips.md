# Tooltips — Ka0s Combat Trail

Where every tooltip this addon draws opens, by WowAddonStandards standalone-windows, *Tooltip
placement* (LibKa0s#92, item AD-92-CT). The hub's summary is ARCHITECTURE.md, *Tooltip placement*.

Every tooltip this addon places itself goes through one seam in `modules/Style.lua` onto the
library's `LibKa0s-Tooltip-1.0` (LibKa0s#92, item AD-92-CT). The tooltip is owned at `ANCHOR_NONE`
(`Style.OwnTip`), filled, shown, and then placed by its element's kind. No tooltip follows the
cursor, and none is offset from a corner of its control.

- **Body elements** (`Style.PlaceBody`, the library's `PlaceBeside`) open beside the window group,
  outside its outer edge. They go on the right when the tooltip fits there and on the left otherwise,
  2 px (`TIP_GAP`) off, with the tooltip's top level with the hovered element's top. Body elements
  are:
  - on the DPS HUD: the clock, the KPI boxes, the chips, the pace bar, the chart and its cast icons
    and cooldown marks, and the spell breakdown rows;
  - on the Combat Sequence (CSEQ-4, the audit in the Combat Sequence spec's section 12): every row
    with a spell, in all three homes; in the HUD's drawer, its heading marks (the filter eye, the
    detach arrow), its Resume and its chips; in the Results fight detail's section, its chips and
    its heading's fold arrow;
  - on the cast lanes: each cast icon (the lane's group: the lane alone, or both lanes while one is
    docked on the other);
  - on the Race window (Retail): every body's chips, cards, labels, captions and buttons, the lengths,
    Custom and Arm Race among them;
  - on the Results window: the fight list's rows and column headers (the row reads which cell the
    cursor is over to pick the words; the place is always beside the window), the fight detail's
    KPI cards and hover lines, the section headings' fold arrows, the action row at the bottom of the
    detail (*Timeline*, *Compare*, *Share*, *Add Note*, *Delete*: it is neither a toolbar between the
    title bar and the body nor the window's footer, `W.Footer`, which sits under it), the Gear and Talents item cells and
    buttons, the Usage rows and buttons, and the Insights charts' marks and board tabs (through
    LibKa0s-Charts-1.0's `ctx:PlaceTip`, `core/ChartsSetup.lua`);
  - on the compare: the spell rows, the *Different loadout* chip and the used-item lines;
  - on the gear view: each slot;
  - on the ability timeline: the cast icons, the tick marks, the ability names, the controls on the
    Casts heading line (`?`, scroll, zoom) and the *Ticks* / *Icons* words (a section heading's
    controls are body elements).
- **Chrome elements** (`Style.PlaceChrome`, the library's `PlaceAttached`) are centered on the
  control, 2 px above it, and below it only when the screen has no room above. Chrome elements are:
  the fight list's and the Insights tab's filter-bar buttons (*Save*, *Reset*, *Clear*, the view
  buttons); the fight detail's top toolbar, *Back* above the scrolled detail; and the compare's *Clear pick*
  on its fixed legend band under the title bar; and the detached Combat Sequence window's *Resume*
  and chips, on the band between its title bar and its table, its filter bar (CSEQ-4). The title-bar marks (`W.HeaderButtons`) and the test
  and sim strips are the library's, attached above by the library.
- **The window group** (`Style.TipGroup`) is the hovered element's top-level window. The one
  exception is the DPS HUD with the Race window attached to it: the two are one group, the HUD its
  main frame, with the library's sim window added while it is docked to either. A HUD row's tooltip
  opens outside both. A Race window row's tooltip prefers the Race window's side away from the HUD.
  Detached, each window is its own group. The cast lanes are the second exception: while one lane
  is docked on the other (LaneAnchor mode `dock`, the Pet lane's default under the Player lane) it
  moves with its host, so both shown lanes are one group, the host lane its main frame
  (`LaneAnchor.TipGroup`). A cast icon's tooltip then opens outside both lanes, so it never covers
  the docked lane, side by side or wider. A free lane, or one on a unit frame (the client's frame,
  never in the group), is its own group. The compare, the gear view and the timeline stand on their
  own, so each is its own group.
- **The fallback**, used with no library or with geometry the library cannot read (a secret
  included), attaches the tooltip centered 2 px above the element. It never uses the cursor.
- **Verification**: `tests/test_tooltip_place.lua` covers the seam on the kit's fake screen
  (`mock_screen.lua`), with right-fits and left-fallback layouts, the chrome flip, the group and the
  fallback, and the docked lanes (side by side, the default dock with a wider Pet lane, a hidden
  docked lane, undocked). It also sweeps every hover on every window in test mode for an `ANCHOR_NONE` owner and a
  placement, checks the named surfaces by rule, and guards the source against any anchor but
  `ANCHOR_NONE`.

## Left as they are (out of scope, *What it does not bind*)

| Tooltip | Why it stays |
|---|---|
| The settings pages' tooltips (`settings/*.lua`: `tooltip`, `defaultsTooltip`, `StrataTooltip`) | Pages inside Blizzard's Settings canvas; options-ui governs them, and the library's Options widgets place them. |
| The context menus' entries (`NS.OpenMenu`: a fight row's right-click menu, the late casts' menu, the Share menu, the Usage *Never show* menu) | Drawn by `LibKa0s-Widgets-1.0`'s `ContextMenu` (`core/WidgetsSetup.lua`), which places an entry's tooltip beside the menu itself (body rule 6). Without the library they fall back to the client's `MenuUtil.CreateContextMenu`, whose tooltips the client places. |
| The launcher's options menu and the minimap button's tooltip | The menu is the client's (`MenuUtil.CreateContextMenu`); the minimap tooltip is the library's (`LibKa0s-Launcher-1.0` places it through `PlaceLauncher`, launcher-§7). |
| A LibDataBroker display's tooltip (Titan Panel and the like) | The display draws the bar and places the tooltip; the broker object only fills it. |
| The filter bars' dropdowns, the skin picker, the debug console, the copy window, the perf panel, the sim panel and the title-bar marks | Library-drawn windows and widgets; `LibKa0s v1.105.0` places their tooltips itself. |
