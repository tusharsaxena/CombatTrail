# Settings panel — Ka0s Combat Trail

How the addon is configured (documentation-§3, Tier 1; options-ui). Everything lives under the game's
**Settings → AddOns → Ka0s Combat Trail**, built with LibKa0s-Options-1.0. The landing page carries
the logo, the version and the command list; every page under it but Profiles (AceDBOptions' own
table, untabbed and with no Defaults button) is a tab strip with a Defaults button that resets that
page on the current profile. Every row is a schema row (`settings/*.lua` through
`NS.RegisterSchemaRows`), so each is also reachable as `/ct get` and `/ct set` with the key shown.

| Page | Covers |
|---|---|
| General | The master switches (enable, lock, debug console, minimap button, test mode, sim mode, the HUD in combat), the skin and its overrides, and the key bindings |
| Lanes | The Player and Pet lanes, one lane at a time through the picker in the page's band: size and anchoring, icons, background and border, ticks and the label, visibility, ignored spells |
| DPS HUD | When the HUD opens and fades, what it paces against, which parts it shows, how often its clock redraws, and the look of each part |
| Combat Log | The log of your casts, auras, hits and heals taken and death (CombatTrail #11): on or off, open now and at each fight's start, docked in the DPS HUD or in its own window; the drawer's filter chips and rows; the window's rows, place, pin, lock, scale and opacity; the sort, the display throttle, the text size, the row height, the time and the columns; what the live views show; the colors; what each fight saves; the Results Log section's chips |
| History | What a fight must pass to be stored, how long it is kept, the Results window's scale and rows, the items Usage never lists, the training dummies (both clients) and the new-best toast (a fight's on both clients, a race's on Retail) |
| Race mode | Retail only: the Race mode switch, the length a race arms at, auto-show (the Race window and the DPS HUD with it) and auto-arm near a training dummy, the race clock (how often it redraws is the DPS HUD page's *HUD refresh rate*), the countdown and the buzzer, the center call-out's look and voice (its one Callout tab: a preview, then Look and Sound), the scoring rules, the late-cast ignore list, and where the Race window stands and how tall it is (its size is the grip's) |
| Profiles | AceDB's own profile controls |

The tree below is page, then tab in strip order, then row, as the schema produces it. Rows a client
cannot have are absent there (clients-§4): the Delves, Arenas, In a vehicle and In a pet battle rows
of the Lanes page's Visibility tab, the Mythic+, Delves and Arenas rows of the History page's
Recording filters, and the New-best toast's *Toast a race's new best* row exist only on Retail.
The whole Race mode page is Retail's: on WoW Forever it is not registered, and none of its rows
or stored keys exist (`settings/Race.lua`).

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
| Lock the lanes | `general.lanesLocked` |
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
*Toggle Results window*, on Retail *Toggle Race window*, and *Toggle lanes*. *Toggle DPS HUD* closes
an open Race window with the HUD, and opens the HUD alone. The keys are the game's, not the profile's, so Defaults
never reaches them; the same bindings show under Options → Keybindings → Ka0s Combat Trail.

Master controls also carries *Reset position* (the lanes, the HUD and the Results window back to their
starting places, and with them the detached Race window's place on Retail and the new-best toast's
dragged place: `NS.ResetPositions`, core/CombatTrail.lua) and *Reset all settings*, which asks first.
Race mode adds one key binding on Retail, *Toggle Race window*, after *Toggle Results window* (the
owner's decision of 2026-11-13, superseding ruling X18; its row is built under `ForClient` and its
binding lives in Retail's `Bindings_Mainline.xml`, a documented deviation). WoW Forever's tab keeps
its three.

## Lanes

The band's lane picker (session only, never stored) chooses the lane every row edits; each row below
is written to `lanes.<k>.`, `<k>` being `player` or `pet`. Tabs: *General*, *Size and position*,
*Icons*, *Background and border*, *Ticks and labels*, *Visibility*, *Ignored spells*
(settings/Lanes.lua, `NS.LANES_TAB_ORDER`).

### General

The tab also carries the host-drawn acts on the lane: unlock it, copy the other lane's settings onto it, reset it, and preview it.

*Link to Player lane* is the Pet lane's alone (after KickCD's Focus-mirrors-Target, off by default).
While on, the Pet lane draws with the Player lane's look and visibility, keeping its switch, where it
sits (anchor, strata, level), its label text and its ignore list (`LaneRender.LINK_OWN`). Its tabs
then show only those rows, a tab left with none drops off the strip, and a note under the row says
why. Copy from Player lane unlinks it.

| Row | Key |
|---|---|
| Enable this lane | `lanes.<k>.enabled` |
| Link to Player lane (Pet lane only) | `lanes.<k>.link` |

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
| Use the skin's texture (on by default: the skin's bar texture) | `lanes.<k>.bgTextureFromSkin` |
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
| Use the skin's color (on by default: the skin's chart grid) | `lanes.<k>.tickColorFromSkin` |
| Show now line | `lanes.<k>.now` |
| Now line color | `lanes.<k>.nowColor` |
| Use class color | `lanes.<k>.nowClassColor` |
| Use the skin's color (on by default: the skin's chart marker) | `lanes.<k>.nowColorFromSkin` |
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
(settings/Hud.lua, `NS.HUD_TAB_ORDER`). Behavior ends with a *Refresh* group whose one row, *HUD refresh
rate* (`hud.refreshRate`: 4, 5, 10 or 20 a second, default 10, on both clients), sets how often every
live part of both windows redraws, in a fight or a race: one beat reads the meter once and redraws the
clock, Damage and DPS, the pace bar, the damage chart and the spell rows, and in a race the Race
window's clock, Best by now and checkpoints from that same read. The footer says the rate ("live · 10
Hz"). Its tooltip names the Race window on Retail only. The Clock and figures tab holds two font blocks, the clock's
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
| HUD refresh rate | `hud.refreshRate` |

### Layout

| Row | Key |
|---|---|
| Show clock | `hud.layout.clock` |
| Show target line | `hud.layout.target` |
| Show damage and DPS boxes | `hud.layout.figures` |
| Show pace bar | `hud.layout.pace` |
| Show damage chart | `hud.layout.chart` |
| Show spell rows | `hud.layout.spells` |
| Spell bars | `hud.bars` |
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
| Same color as Damage | `hud.figures.overColorMatchDamage` |
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
| Pace line color | `hud.chart.bestColor` |
| Use class color | `hud.chart.useClassColorBestColor` |
| Use the skin's color (on by default: the skin's pace-line color) | `hud.chart.bestColorFromSkin` |
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
| Show border (off by default: the bars draw no border) | `hud.spells.borderShow` |
| Border style | `hud.spells.borderStyle` |
| Border thickness (px) | `hud.spells.borderSize` |
| Border color | `hud.spells.borderColor` |
| Use class color | `hud.spells.useClassColorBorder` |
| Use the skin's border (the skin's bar border style and thickness; a skin with None keeps yours) | `hud.spells.borderStyleFromSkin` |
| Use the skin's color | `hud.spells.borderColorFromSkin` |
| Font | `hud.spells.font` |
| Font size | `hud.spells.fontSize` |
| Font color | `hud.spells.fontColor` |
| Use class color | `hud.spells.useClassColorFont` |
| Font flags | `hud.spells.fontFlags` |
| Font shadow | `hud.spells.fontShadow` |
| Use the skin's font | `hud.spells.fontFromSkin` |
| Use the skin's color | `hud.spells.fontColorFromSkin` |
| Use the skin's shadow | `hud.spells.fontShadowFromSkin` |

*Use the skin's texture* is on by default in both blocks, so the chart columns, the spell rows and the
pace bar (its red shortfall included) draw the skin's bar texture; the *Bar texture* pick draws only
once it is off. The Results detail's damage profile and spell breakdown follow these two blocks. The
Results table's bars, the detail's Targets bars, the compare's bars and the Race window's time bar
have no texture row and always draw the skin's (AF-CT-TEX).

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

## Combat Log

Tabs: *Combat Log*, *Docked drawer*, *Detached window*, *Order and display*, *What to show*, *Colors*,
*Storage*, *Results* (settings/Log.lua, `NS.LOG_TAB_ORDER`; CombatTrail #11, CL-11c2). Every row writes
through `NS.SetByPath`, and its SETTINGS_CHANGED redraws whichever home is up: the DPS HUD's drawer (the
HUD grows or shrinks with it), the detached window, and the Results fight detail's Log section. The log's
own controls write the same rows: the HUD's Log control and `/ct log` (*Show the Combat Log*), the
drawer's chevron (*Folded to one line*), its detach mark and the window's dock mark (*Where the log
lives*), the window's attach mark (*Attach beside the DPS HUD*), `/ct log pin|unpin` (*Stay up while the
HUD is hidden*) and a click on the Time header (*Sort order*). The detached window's place and size are
its drag's and its grip's (`log.window.position`, `width`, `height`), with no row, so the page's
Defaults leaves them where they are. The window's gear opens this page.

### Combat Log (tab)

| Row | Key |
|---|---|
| Enable the Combat Log | `log.enabled` |
| Show the Combat Log | `log.drawer.shown` |
| Open it when a fight starts | `log.drawer.autoOpen` |
| Where the log lives (Docked in the DPS HUD, In its own window) | `log.home` |

### Docked drawer

| Row | Key |
|---|---|
| Show the filter chips | `log.drawer.chips` |
| Rows shown (3 to 20) | `log.drawer.rows` |

### Detached window

*Rows shown* is drawn disabled while *Fill the window with rows* is on (`disabledIf`). The window is
standalone (owner feedback item 11): it has no attach, side, HUD-height or pin rows (schema step 6).

| Row | Key |
|---|---|
| Fill the window with rows | `log.window.fill` |
| Rows shown (3 to 40) | `log.window.rows` |
| Lock the window | `log.window.locked` |
| Window scale | `log.window.scale` |
| Window opacity | `log.window.alpha` |

### Order and display

*N (ms)* is drawn disabled while *Show new rows* is Instant. The throttle delays only what the drawer and
the window show; every event is still captured and saved. *Text size* runs 8 to 16 points (10, the body
text's own) and widens the fixed columns and the icon with it; *Row height (px)* runs 12 to 28 (14), and
the drawer, the window and the Results Log section all take their heights from it.

| Row | Key |
|---|---|
| Sort order (Newest first, Oldest first) | `log.view.sort` |
| Show new rows (Instant, At most one row every N ms, In batches every N ms) | `log.view.throttle` |
| N (ms) | `log.view.throttleMs` |
| Text size | `log.view.fontSize` |
| Row height (px) | `log.view.rowHeight` |
| Time (From the pull, Clock time) | `log.view.timeFormat` |
| Show the Info column | `log.view.columns.info` |
| Show the Spell/School column | `log.view.columns.spell` |
| Show the Amount column | `log.view.columns.amount` |

### What to show

The live views' filter: the drawer and the window. These rows are the defaults of each view's chips
(Casts, Pet, Buffs, Debuffs, Taken, Heals: the window's under its status line, the drawer's behind its
header's filter mark). Each view seeds its chips from them when it is built, when the log is opened or
moved, at each fight's start and at a write here; a click on a chip turns it in that view alone, for the
session, and is never stored. What is saved is the Storage tab's, apart from it.
A hit or a heal whose amount the client keeps secret is never compared, so *Least amount shown* never
hides it.

| Row | Key |
|---|---|
| Your casts | `log.show.casts` |
| Your pet's casts | `log.show.petCasts` |
| Buffs on you | `log.show.playerBuffs` |
| Debuffs on you | `log.show.playerDebuffs` |
| Your debuffs on your target | `log.show.targetDebuffs` |
| Buffs on your target | `log.show.targetBuffs` |
| Hits taken | `log.show.hits` |
| Heals taken | `log.show.heals` |
| Deaths | `log.show.deaths` |
| Show auto attacks | `log.show.autoAttacks` |
| Least amount shown | `log.show.minAmount` |

### Colors

The *Color-blind safety* group turns school colors and row washes off; every event still differs by
its tag. *Your color* is a ColorPair whose *Use class color* is on by default (the log has drawn "You" in
the class color since it shipped). The two target colors are a palette, one per reaction, so they carry
no class companion (options-ui-§17's exemption); each has *Use the skin's color* on by default, which
draws the skin's `ct.log.hostile` or `ct.log.friendly`.

| Row | Key |
|---|---|
| School colors | `log.view.schoolColors` |
| Row washes | `log.view.washes` |
| Your color | `log.colors.you` |
| Use class color | `log.colors.useClassColorYou` |
| Hostile target color | `log.colors.hostile` |
| Use the skin's color (hostile) | `log.colors.hostileFromSkin` |
| Friendly target color | `log.colors.friendly` |
| Use the skin's color (friendly) | `log.colors.friendlyFromSkin` |

### Storage

Each fight freezes these at its start, so a change takes hold from the next fight. *Fights that keep
their log* is the store's own bound instead (modules/Retention.lua): each purge run (login, daily,
`/ct purge`) strips the log from every stored fight but the newest that many carrying one.

| Row | Key |
|---|---|
| Save a log with each fight | `log.store.enabled` |
| Lines kept per fight (100 to 1000) | `log.store.lines` |
| Fights that keep their log (0 = all; 0 to 500) | `log.store.fights` |
| Your casts | `log.store.categories.casts` |
| Your pet's casts | `log.store.categories.petCasts` |
| Buffs on you | `log.store.categories.playerBuffs` |
| Debuffs on you | `log.store.categories.playerDebuffs` |
| Your debuffs on your target | `log.store.categories.targetDebuffs` |
| Buffs on your target | `log.store.categories.targetBuffs` |
| Hits taken | `log.store.categories.hits` |
| Heals taken | `log.store.categories.heals` |
| Deaths | `log.store.categories.deaths` |

### Results

| Row | Key |
|---|---|
| Jump to the Timeline on clicking a cast | `log.results.jumpToCast` |
| Casts | `log.results.chips.casts` |
| Pet | `log.results.chips.pet` |
| Buffs | `log.results.chips.buffs` |
| Debuffs | `log.results.chips.debuffs` |
| Taken | `log.results.chips.taken` |
| Heals | `log.results.chips.heals` |

## History

Tabs: *Recording filters*, *History*, *Results window*, *Usage*, *Training dummies*, *New-best toast* (settings/History.lua,
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
| Casts in By ability | `results.timelineMarks` |

Under its own *Ability timeline* heading, a dropdown: *Ability icons* (`icon`, the default) or *Tick
lines* (`tick`). The timeline's *Icons* and *Ticks* words on its *By ability* heading line write the
same key, and an open timeline redraws with its zoom and pan kept.

### Usage

| Row | Key |
|---|---|
| Hidden items | `global.usage.hidden` (drawn as a list with add and remove, not a text box) |
| Hidden buffs | `global.usage.hiddenSpells` (drawn as a spell list with add and remove, under the items; CombatTrail #13) |

### Training dummies

On both clients (race plan Task A2). A blurb, *Add your target* (captures the target and counts it as
a single-target dummy), the library's ID list over the player's own dummies (a creature ID or a
captured name; the X takes one off), one checkbox per built-in (clear it to switch the built-in off;
none on WoW Forever, whose seed is empty), then *Reset list* last.

| Row | Key |
|---|---|
| Your training dummies | `dummies.custom` (skipRender: drawn as the tab's body, not a text box) |

### New-best toast

On both clients (race plan Task C2, ruling X19: the section sits on a page both clients have, with only
the races row Retail's). The rows, then *Test toast* last (a sample toast run as a real one; drag it to
place it while it shows, and General > Master controls' *Reset position* puts it back). Duration and sound
are read as each toast shows; the scale re-anchors a shown toast. A race or fight toggle switched off takes
that kind's toasts down, waiting or shown, and leaves the other kind's. A new profile toasts a race's
new best and not a fight's: *Toast a fight's new best* starts off.

| Row | Key |
|---|---|
| Toast a race's new best (Retail only) | `toast.races` |
| Toast a fight's new best | `toast.fights` |
| Play a sound | `toast.sound` |
| Toast sound | `toast.soundKey` |
| Toast duration (seconds) | `toast.duration` |
| Toast scale | `toast.scale` |

## Race mode

Retail only (race plan Task B3). Tabs: *Race*, *Callout*, *Late-cast ignore list*, *Race window*
(settings/Race.lua, `NS.RACE_TABS` for the page's own three; *Callout* is LibKa0s-Callout-1.0's
settings section as one tab, callout plan rows C5 and C11). The Race tab opens on the page's one note on where Race mode came
from, then the switch; the race clock's two colored clocks and the window's look are the DPS HUD page's
appearance blocks (spec §8), and its lock is General's *Lock frame*. The training dummies are the History
page's, and the New-best toast's section is History's too (ruling X19). The countdown rows carry no
reaction of their own: modules/Countdown.lua re-arms the race's call-out off their SETTINGS_CHANGED;
the buzzer row is read when the buzzer goes (Countdown.Buzzer). They decide when the call-out speaks
for the race; the call-out's own look and voice are its own tab (below).

### Race

| Row | Key |
|---|---|
| Race mode | `race.enabled` |
| Default race length | `race.defaultLength` |
| Show the Race window near a training dummy | `race.autoShow` |
| Show the DPS HUD near a training dummy | `race.autoShowHud` |
| Arm on a training dummy | `race.autoArm` |
| Race clock | `race.clock` |
| Center-screen countdown | `race.centerCountdown` |
| Center countdown from (seconds) | `race.finalCountdown` |
| STOP at the buzzer | `race.buzzer` |
| Sticky-combat hint after (seconds) | `race.hintDelay` |
| Late-cast grace (seconds) | `race.grace` |
| Damage-restart gap (seconds) | `race.restartGap` |

Under the headings *Race mode*, *Length*, *Near a training dummy*, *Clock*, *Countdown*, *At the buzzer*
and *Scoring rules*. *Near a training dummy* holds three rows. *Show the Race window near a training
dummy* (on) opens the Race window while a dummy is the target or has its nameplate up, outside
instances; a Race window the player opens during that dummy session closes with it too, and one the
player closes stays closed until the next session. *Show the DPS HUD near a training dummy* (on) does
the same: the Race window never shows without the DPS HUD (race window redesign plan W29), so either
row on opens both near a dummy, the DPS HUD as an auto open that fades after a fight by its own rules
and takes the Race window with it, both opening again at the dummy session's next ask. Both close with
the session unless a fight is on the HUD or the player opened or pinned it, and once the player closes
either, both stay closed until the next dummy session. Neither row depends on the other. *Arm on a training dummy*
(off) arms a race on targeting one out of combat. *Race clock* offers *Elapsed and time left*, *Time
left* and *Elapsed*; *Time left* (one large countdown, green to amber to red over the race) is a new profile's, and a profile that saved
the pair keeps it. How often the race clocks and the rest redraw is the DPS HUD page's *HUD refresh
rate*. A new default length forgets the length last armed (`Race.ForgetLength`); the
switch and the three dummy rows re-sync auto-show's and auto-arm's events (`AutoArm.Sync`), and the switch
going off cancels a race still armed (one running runs on), as does a profile switch, copy or reset
that lands on Race mode off (the page's `SETTINGS_CHANGED` receiver, path `profile`). Grace and the
restart gap apply to new races: each race keeps the values it armed with. *Center countdown from*
takes 3 to 20 seconds (`Countdown.MIN` and `MAX`; 20 is the call-out's longest countdown); numbers above
the call-out's *Speak numbers from* are shown, not said.

### Callout

The call-out's own settings: LibKa0s-Callout-1.0's settings section as one tab (the library's
docs/api/Callout, version 4.5, The one tab), drawn by `NS.Callout:SettingsTab({ options = NS.Helpers,
key = "callout", prefix = "callout." })` as one host tab on the host's write route, labeled in the
library's own word, *Callout*. Its render calls the instance's `BuildSettings(ctx, { options, layout =
"side", prefix })`, which draws through this addon's Options instance: every control is the panel's
own dropdown, slider, checkbox, color swatch or side-tab list (`O.SideTabs`, OptionsNav minor 7), in
the skin and under the combat lock, read by the descriptor's `get` and written by its `set`, so
through `NS.SetByPath`. The rows it draws are the instance's `SchemaRows("callout.", { texts = false
})`, which settings/Race.lua registers as this page's rows: so the page's Defaults, the global reset
and `/ct get|set|list|reset` reach every one. Registered, each is skipRender (the section draws its own
copy by the same path) and grouped under the one tab's key, `callout`, so the tab takes the group's
place in the strip.

Top to bottom: a **Preview** heading (no sample line under it since LibKa0s v1.102.0, CalloutSettings
minor 5: the real call-out is where the look shows), *Test countdown* (5 to GO! on the real call-out) and *Play*, *Text to play* (the
stock words, led by *Countdown 10 to 1*, which counts the real call-out down from 10 with no finish),
*Unlock to move* (the drag strip, `?` · settings · close: its close locks the call-out and turns *Center-screen countdown* off with one chat line saying where to turn it back on, and its gear opens this tab, core/CalloutSetup.lua; the drag writes `callout.point`) and *Reset position*. None of them
touches a race. Under it, the **side tabs**: a list on the left, *Look* and *Sound*, and the selected
one's rows on the right. Look is selected first; the pick is session state, never saved.

**No stock texts.** The call-out's words and their mutes are the addon's to control (owner,
2026-11-14): `texts = false` leaves their 46 rows out, so nothing draws them, the seam refuses
`callout.texts.*` and `callout.muted.*`, and the call-out says the library's stock words in its voice.

| Side tab | Row | Key |
|---|---|---|
| Look | Font | `callout.font` |
| Look | Size | `callout.size` |
| Look | Outline (led by From skin, the default) | `callout.outline` |
| Look | Use the skin's shadow (on: Shadow and its offsets are not read) | `callout.fontShadowFromSkin` |
| Look | Shadow | `callout.shadow` |
| Look | Shadow X offset, Shadow Y offset (disabled with no shadow) | `callout.shadowX`, `callout.shadowY` |
| Look | Animation | `callout.anim` |
| Look | Hold | `callout.hold` |
| Look (Glow) | Glow behind the text | `callout.glow` |
| Look (Glow) | Glow color, and its swatch | `callout.glowCustom`, `callout.glowColor` |
| Look (Glow) | Use class color | `callout.useClassColorGlow` |
| Look (Glow) | Use the skin's color | `callout.glowColorFromSkin` |
| Look (Glow) | Intensity (percent), Thickness (px) | `callout.glowIntensity`, `callout.glowThickness` |
| Look (Glow) | X offset, Y offset | `callout.glowX`, `callout.glowY` |
| Look (Colors) | one swatch per kind | `callout.colors.<kind>` (`number`, `info`, `go`, `stop`, `warn`, `error`) |
| Look (Colors) | Use the skin's color, beside Numbers (on: the skin's HUD text color; the swatch stays live) | `callout.numberColorFromSkin` |
| Sound | Voice (the eight packs, Game TTS, off; Arena announcer (John) first and the default) | `callout.voice` |
| Sound | Sound channel | `callout.channel` |
| Sound | Speak numbers from | `callout.speakFrom` |
| Sound | Text to speech voice, Speech rate, Speech volume (only with a client voice listed; disabled unless the voice is Game TTS) | `callout.ttsVoice`, `callout.ttsRate`, `callout.ttsVolume` |
| Preview | Text to play, Unlock to move (session only, never stored) | `callout.play`, `callout.unlocked` |

**The glow, as AuraMaster's.** Laid out in AuraMaster's two columns under Look's *Glow* heading. The
color follows AuraMaster's order: *Use class color* wins, then *Use the skin's color*, then the
*Glow color* swatch, else each word's own kind color. A fresh profile has *Glow color* ticked on a
black swatch, at 100%, 2 px and offset 1, 1, with *Use the skin's color* unticked: Combat Trail's own
glow defaults over the library's (the owner's settings of 2026-11-20, SD-CT-DEF; the unticked companion
is a documented deviation, `docs/ARCHITECTURE.md`). The rest of the look follows the skin (LibKa0s
v1.108.0, the owner's U-1 of 2026-11-20); *Font* reads
the skin's font, ahead of the call-out's own faces, Oxanium SemiBold, Oxanium Bold, Bebas Neue and Russo
One, and *Outline* *From skin*. The meaning kinds (info, GO, STOP, warn, error) draw the skin's `sem.*`
colors until one is picked (U-2). A profile that still stored the old look (Oxanium SemiBold, Thick
outline) moves once, its glow's *Use the skin's color* left as it was (SD-CT-DEF) (`docs/schema.md`, the step onto the skin's defaults).
Every Glow row but the toggle and the
class-color pair is disabled while the glow is off. A profile from before stored *Off*, *Soft* or
*Strong*; the 2 -> 3 migration turns it into these keys (`docs/schema.md`, Migrations), and as it
named no color or offset such a profile reads the black swatch at 1, -1.

### Late-cast ignore list

A blurb, the library's spell ID list (an add box for a spell ID, a link or a name a race cast late; the
X takes one off; 8690 says it stands for every hearthstone), then *Reset list* (the six defaults).

| Row | Key |
|---|---|
| Late-cast ignore list | `race.lateIgnore` (skipRender: drawn as the tab's body, not a text box) |

### Race window

| Row | Key |
|---|---|
| Attach to the DPS HUD | `raceWindow.attached` |
| Side of the DPS HUD | `raceWindow.side` |
| Match the DPS HUD's height | `raceWindow.matchHud` |

Attached (on), the Race window stands flush against the DPS HUD on the side picked (right by default),
its top or left edge level with the HUD's, and moves with it; off, it stands where its title bar was
dragged to, and General's *Lock frame* holds it. *Match the DPS HUD's height* (on) applies on the left
or right: the Race window takes the HUD's height and follows each HUD resize (the grip, auto-grow, a
part or the title bar or footer shown or hidden), never shorter than the height its tallest screen
needs. Above or below the HUD, detached, or with the row off, it keeps its own height. Both windows
take the DPS HUD's scale, so equal heights line up.

Its size has two hidden rows (skipRender; the window's resize grip is their control, and the tab's
Defaults and `/ct set` reach them like any row):

| Row | Key |
|---|---|
| Race window width (px) | `raceWindow.width` (skipRender: set by the grip; 260 to 600, default 260) |
| Race window height (px) | `raceWindow.height` (skipRender: set by the grip; 0 to 1000, default 0, the content height) |

The grip shows only while the frames are unlocked. Matched left or right of the HUD it drags the width
alone (the height is the HUD's); otherwise it drags both. It never goes below 260 wide or below the
height the content needs, and the screens' bodies stretch to fill what it gives them.

## Profiles

AceDBOptions' own table, drawn by AceConfigDialog into the library's panel (settings/Profiles.lua):
choose, create, copy, reset and delete profiles. See [`profiles.md`](profiles.md).
