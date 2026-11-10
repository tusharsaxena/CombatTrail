# Settings panel — Ka0s Combat Trail

How the addon is configured (documentation-§3, Tier 1; options-ui). Everything lives under the game's
**Settings → AddOns → Ka0s Combat Trail**, built with LibKa0s-Options-1.0. The landing page carries
the logo, the version and the command list; every page under it is a tab strip with a Defaults button
that resets that page on the current profile. Every row is a schema row (`settings/*.lua` through
`NS.RegisterSchemaRows`), so each is also reachable as `/ct get` and `/ct set` with the key shown.

| Page | Covers |
|---|---|
| General | The master switches (enable, lock, debug console, minimap button, test mode, sim mode, the HUD in combat), the skin and its overrides, and the key bindings |
| Lanes | The Player and Pet lanes, one lane at a time through the picker in the page's band: size and anchoring, icons, background and border, ticks and the label, visibility, ignored spells |
| DPS HUD | When the HUD opens and fades, what it paces against, which parts it shows, and the look of each part |
| History | What a fight must pass to be stored, how long it is kept, the Results window's scale and rows, and the items Usage never lists |
| Profiles | AceDB's own profile controls |

The tree below is page, then tab in strip order, then row, as the schema produces it. Rows a client
cannot have are absent there (clients-§4): the Delves and Arenas rows of the Lanes page's Visibility
tab, and the Mythic+, Delves and Arenas rows of the History page's Recording filters, exist only on
Retail.

## General

Tabs: *Master controls*, *Look and skin*, *Keybindings* (settings/General.lua).

### Master controls

| Row | Key |
|---|---|
| Enable Ka0s Combat Trail | `general.enabled` |
| Lock frame | `general.locked` |
| Debug console | `general.debugConsole` |
| Minimap button | `general.minimap.shown` |
| Test mode | `general.testMode` |
| Sim mode | `general.simMode` |
| Show DPS HUD in combat | `general.hudInCombat` |
| Debug logging | `general.debug` |

### Look and skin

| Row | Key |
|---|---|
| Skin source | `skin.source` |
| Skin | `skin.skin` |
| Ignore settings panel | `skin.ignorePanel` |
| Ignore fonts | `skin.ignoreFonts` |
| Font | `skin.font` |
| Texture | `skin.texture` |
| Font outline | `skin.outline` |
| Skin picker seen | `skin.pickerSeen` |
| Global font scale | `general.fontScale` |

### Keybindings

The library's Keybindings tab over `NS.BINDINGS` (core/LauncherSetup.lua): *Toggle DPS HUD*,
*Toggle Results window* and *Toggle lanes*. The keys are the game's, not the profile's, so Defaults
never reaches them; the same bindings show under Options → Keybindings → Ka0s Combat Trail.

Master controls also carries *Reset position* (the lanes, the HUD and the Results window back to their
starting places) and *Reset all settings*, which asks first.

## Lanes

The band's lane picker (session only, never stored) chooses the lane every row edits; each row below
is written to `lanes.<k>.`, `<k>` being `player` or `pet`. Tabs: *General*, *Size and position*,
*Icons*, *Background and border*, *Ticks and labels*, *Visibility*, *Ignored spells*
(settings/Lanes.lua, `NS.LANES_TAB_ORDER`).

### General

The tab also carries the host-drawn acts on the lane: unlock it, copy the other lane's settings onto it, reset it, and preview it.

| Row | Key |
|---|---|
| Enable this lane | `lanes.<k>.enabled` |

### Size and position

| Row | Key |
|---|---|
| Direction | `lanes.<k>.direction` |
| Scale | `lanes.<k>.scale` |
| Lane length (px) | `lanes.<k>.width` |
| Seconds shown | `lanes.<k>.seconds` |
| Icon size (px) | `lanes.<k>.iconSize` |
| Icon spacing (px) | `lanes.<k>.spacing` |
| Anchor | `lanes.<k>.anchor.mode` |
| Frame by name | `lanes.<k>.anchor.frameName` |
| Point | `lanes.<k>.anchor.point` |
| Relative point | `lanes.<k>.anchor.relPoint` |
| Gap (px) | `lanes.<k>.anchor.gap` |
| X offset | `lanes.<k>.anchor.x` |
| Y offset | `lanes.<k>.anchor.y` |
| Frame strata | `lanes.<k>.strata` |
| Frame level | `lanes.<k>.levelOffset` |

### Icons

| Row | Key |
|---|---|
| Icon zoom | `lanes.<k>.zoom` |
| Fade portion | `lanes.<k>.fade` |
| Mark interrupted casts | `lanes.<k>.markInterrupted` |
| Stack repeated casts | `lanes.<k>.stack` |
| Show spell tooltip | `lanes.<k>.tooltip` |
| Show spell name | `lanes.<k>.showName` |
| Show border | `lanes.<k>.border` |
| Border style | `lanes.<k>.borderTexture` |
| Border thickness (px) | `lanes.<k>.borderSize` |
| Border color | `lanes.<k>.borderColor` |
| Use class color | `lanes.<k>.borderClassColor` |
| Use the skin's border | `lanes.<k>.borderTextureFromSkin` |
| Use the skin's color | `lanes.<k>.borderColorFromSkin` |
| Glow long cooldowns | `lanes.<k>.glowLongCD` |
| Long cooldown (seconds) | `lanes.<k>.glowMinCD` |
| Glow color | `lanes.<k>.glowColor` |
| Use class color | `lanes.<k>.glowClassColor` |
| Use the skin's color | `lanes.<k>.glowColorFromSkin` |

### Background and border

| Row | Key |
|---|---|
| Show background | `lanes.<k>.background` |
| Background texture | `lanes.<k>.bgTexture` |
| Background color | `lanes.<k>.bgColor` |
| Use class color | `lanes.<k>.bgClassColor` |
| Use the skin's color | `lanes.<k>.bgColorFromSkin` |
| Padding (px) | `lanes.<k>.padding` |
| Show border | `lanes.<k>.laneBorder` |
| Border style | `lanes.<k>.laneBorderTexture` |
| Border thickness (px) | `lanes.<k>.laneBorderSize` |
| Border color | `lanes.<k>.laneBorderColor` |
| Use class color | `lanes.<k>.laneBorderClassColor` |
| Use the skin's border | `lanes.<k>.laneBorderTextureFromSkin` |
| Use the skin's color | `lanes.<k>.laneBorderColorFromSkin` |

### Ticks and labels

| Row | Key |
|---|---|
| Show GCD ticks | `lanes.<k>.ticks` |
| Tick spacing | `lanes.<k>.tickSpacing` |
| Tick width (px) | `lanes.<k>.tickWidth` |
| Tick color | `lanes.<k>.tickColor` |
| Use class color | `lanes.<k>.tickClassColor` |
| Show now line | `lanes.<k>.now` |
| Now line color | `lanes.<k>.nowColor` |
| Use class color | `lanes.<k>.nowClassColor` |
| Show label | `lanes.<k>.label` |
| Label position | `lanes.<k>.labelPosition` |
| Label text | `lanes.<k>.labelText` |
| Font | `lanes.<k>.labelFont` |
| Font size | `lanes.<k>.labelSize` |
| Font color | `lanes.<k>.labelColor` |
| Use class color | `lanes.<k>.labelClassColor` |
| Font flags | `lanes.<k>.labelOutline` |
| Font shadow | `lanes.<k>.labelShadow` |
| Use the skin's font | `lanes.<k>.labelFontFromSkin` |
| Use the skin's color | `lanes.<k>.labelColorFromSkin` |
| Use the skin's shadow | `lanes.<k>.labelShadowFromSkin` |

### Visibility

| Row | Key |
|---|---|
| Show the lane | `lanes.<k>.visibility.show` |
| Hide after combat (seconds) | `lanes.<k>.visibility.hideAfter` |
| Opacity in combat | `lanes.<k>.visibility.alphaCombat` |
| Opacity out of combat | `lanes.<k>.visibility.alphaOOC` |
| Open world | `lanes.<k>.visibility.where.world` |
| Dungeons | `lanes.<k>.visibility.where.dungeon` |
| Raids | `lanes.<k>.visibility.where.raid` |
| Delves | `lanes.<k>.visibility.where.delve` |
| Battlegrounds | `lanes.<k>.visibility.where.bg` |
| Arenas | `lanes.<k>.visibility.where.arena` |
| Mounted | `lanes.<k>.visibility.hideMounted` |
| In a vehicle | `lanes.<k>.visibility.hideVehicle` |
| In a pet battle | `lanes.<k>.visibility.hidePetBattle` |
| Resting | `lanes.<k>.visibility.hideResting` |

### Ignored spells

A host-drawn list over `lanes.<k>.ignore` (modules/LaneIgnore.lua): add a spell by ID, name or
shift-clicked link, remove one, or reset the list to the client's seed. `/ct ignore` does the same.

## DPS HUD

Tabs: *Behavior*, *Layout*, *Clock and figures*, *Damage chart*, *Spell rows*, *Window*
(settings/Hud.lua, `NS.HUD_TAB_ORDER`). The Clock and figures tab holds two font blocks, the clock's
(`hud.clock.*`) and the figures' (`hud.figures.*`). The clock's Font size row is the composed one (6 to 32),
and the clock draws its value scaled to DPS Race's single clock (× 40/26: the default 26 draws 40 points high); its
tooltip says so. HUD width runs from `Hud.MIN_WIDTH` (260, DPS Race's) to `Hud.MAX_WIDTH` (600).

Layout's size rows (v0.2 Task B3): Window size picks Fixed (the default: the height holds Spell bars rows
under every part the layout shows, and the HUD's bottom-right grip sets the width and the bars) or
Auto-grow (the height follows the rows, up to Spell bars). Spell bars runs 1 to 15, default 5. Grow
(Down, the default, or Up) is read by Auto-grow only, so it is drawn disabled in Fixed (`disabledIf`).
Spells past the rows scroll with the mouse wheel in both. The Spell rows tab's old "Spell rows shown"
row (`hud.spells.rows`) is retired into Spell bars.

### Behavior

| Row | Key |
|---|---|
| Show the HUD | `hud.show` |
| Only in instances (when Show the HUD is On each fight's first hit; Always ignores it) | `hud.instancesOnly` |
| Fade after the fight (seconds, 0 = never) | `hud.fadeAfter` |
| Stay open while the mouse is over it | `hud.holdOnMouse` |
| Pace compares against | `hud.paceAgainst` |
| Pace bar range | `hud.paceRange` |
| Show fight-over card | `hud.overCard` |
| Show why a fight was not saved | `hud.showSkipReason` |

### Layout

| Row | Key |
|---|---|
| Show clock | `hud.layout.clock` |
| Show target line | `hud.layout.target` |
| Show damage and DPS boxes | `hud.layout.figures` |
| Show pace bar | `hud.layout.pace` |
| Show damage chart | `hud.layout.chart` |
| Show spell rows | `hud.layout.spells` |
| Window size | `hud.sizeMode` |
| Spell bars | `hud.bars` |
| Grow (Auto-grow only) | `hud.grow` |
| HUD width (px) | `hud.width` |
| HUD scale | `hud.scale` |

### Clock and figures

| Row | Key |
|---|---|
| Font | `hud.clock.font` |
| Font size | `hud.clock.fontSize` |
| Font color | `hud.clock.fontColor` |
| Use class color | `hud.clock.useClassColorFont` |
| Font flags | `hud.clock.fontFlags` |
| Font shadow | `hud.clock.fontShadow` |
| Use the skin's font | `hud.clock.fontFromSkin` |
| Use the skin's color | `hud.clock.fontColorFromSkin` |
| Use the skin's shadow | `hud.clock.fontShadowFromSkin` |
| Font | `hud.figures.font` |
| Font size | `hud.figures.fontSize` |
| Font color | `hud.figures.fontColor` |
| Use class color | `hud.figures.useClassColorFont` |
| Font flags | `hud.figures.fontFlags` |
| Font shadow | `hud.figures.fontShadow` |
| Use the skin's font | `hud.figures.fontFromSkin` |
| Use the skin's color | `hud.figures.fontColorFromSkin` |
| Use the skin's shadow | `hud.figures.fontShadowFromSkin` |
| Final DPS color | `hud.figures.overColor` |
| Use class color | `hud.figures.useClassColorOverColor` |
| Background color | `hud.figures.boxBg` |
| Use class color | `hud.figures.useClassColorBoxBg` |
| Use the skin's background | `hud.figures.boxBgFromSkin` |
| Border color | `hud.figures.boxBorder` |
| Use class color | `hud.figures.useClassColorBoxBorder` |
| Use the skin's color | `hud.figures.boxBorderFromSkin` |

### Damage chart

| Row | Key |
|---|---|
| Chart height (px) | `hud.chart.height` |
| Maximum columns | `hud.chart.columns` |
| Bar texture | `hud.chart.barTexture` |
| Bar opacity | `hud.chart.barAlpha` |
| Bar color | `hud.chart.barColor` |
| Use class color | `hud.chart.useClassColorBar` |
| Use the skin's texture | `hud.chart.barTextureFromSkin` |
| Burst column color | `hud.chart.burstColor` |
| Use class color | `hud.chart.useClassColorBurstColor` |
| Pace line color | `hud.chart.bestColor` |
| Use class color | `hud.chart.useClassColorBestColor` |
| Show zero line | `hud.chart.zeroLine` |
| Show cooldown icons | `hud.chart.cooldowns` |
| Shortest cooldown (seconds) | `hud.chart.cooldownMin` |

### Spell rows

| Row | Key |
|---|---|
| Row height (px) | `hud.spells.rowHeight` |
| Show spell icons | `hud.spells.icons` |
| Show pet paw | `hud.spells.paw` |
| Bar texture | `hud.spells.barTexture` |
| Bar opacity | `hud.spells.barAlpha` |
| Bar color | `hud.spells.barColor` |
| Use class color | `hud.spells.useClassColorBar` |
| Use the skin's texture | `hud.spells.barTextureFromSkin` |
| Pet bar color | `hud.spells.petColor` |
| Use class color | `hud.spells.useClassColorPetColor` |
| Font | `hud.spells.font` |
| Font size | `hud.spells.fontSize` |
| Font color | `hud.spells.fontColor` |
| Use class color | `hud.spells.useClassColorFont` |
| Font flags | `hud.spells.fontFlags` |
| Font shadow | `hud.spells.fontShadow` |
| Use the skin's font | `hud.spells.fontFromSkin` |
| Use the skin's color | `hud.spells.fontColorFromSkin` |
| Use the skin's shadow | `hud.spells.fontShadowFromSkin` |

### Window

| Row | Key |
|---|---|
| Show title bar | `hud.window.titleBar` |
| Show title | `hud.window.title` |
| Show footer | `hud.window.footer` |
| Background color | `hud.window.bg` |
| Use class color | `hud.window.useClassColorBg` |
| Use the skin's background | `hud.window.bgFromSkin` |
| Border color | `hud.window.border` |
| Use class color | `hud.window.useClassColorBorder` |
| Use the skin's color | `hud.window.borderFromSkin` |
| Point | `hud.position.point` |
| Relative point | `hud.position.relPoint` |
| X offset | `hud.position.x` |
| Y offset | `hud.position.y` |
| Frame strata | `hud.window.strata` |
| HUD opacity | `hud.window.alpha` |

## History

Tabs: *Recording filters*, *History*, *Results window*, *Usage* (settings/History.lua,
`NS.HISTORY_TAB_ORDER`; the History tab's internal key stays `retention`). The History tab also shows
the stored count and its estimated size, and carries *Purge history…*.

### Recording filters

| Row | Key |
|---|---|
| Minimum fight length (seconds) | `history.minLength` |
| Bosses only | `history.bossesOnly` |
| Raids | `history.content.raid` |
| Dungeons | `history.content.dungeon` |
| Mythic+ dungeons | `history.content.mplus` |
| Delves | `history.content.delve` |
| Battlegrounds | `history.content.bg` |
| Arenas | `history.content.arena` |
| Open world | `history.content.world` |
| Training dummies | `history.content.dummy` |
| Scenarios | `history.content.scenario` |

### History (tab)

| Row | Key |
|---|---|
| Keep history for (days, 0 = forever) | `history.days` |
| Never purge a fight that holds a best | `history.keepBests` |
| Maximum stored fights (0 = no limit) | `history.maxFights` |

### Results window

| Row | Key |
|---|---|
| Window scale | `results.scale` |
| Row height (px) | `results.rowHeight` |
| Close when combat starts | `results.closeInCombat` |
| Include talents link when sharing | `results.shareTalents` |

### Usage

| Row | Key |
|---|---|
| Hidden items | `global.usage.hidden` (drawn as a list with add and remove, not a text box) |

## Profiles

AceDBOptions' own table, drawn by AceConfigDialog into the library's panel (settings/Profiles.lua):
choose, create, copy, reset and delete profiles. See [`profiles.md`](profiles.md).
