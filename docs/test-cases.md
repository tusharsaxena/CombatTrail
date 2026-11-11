# Test Cases

The full inventory of every headless test case in this repo, grouped by the suite file it
lives in. The `## Totals` table below counts the cases that run: its **Total** is the
authoritative pass count, and the README test badge and any count quoted in the docs must equal
it. A declared skip is listed by name in its group and counted on the `Skipped` row, never in
Total.

**Generated — do not hand-edit.** Regenerate with `lua tests/run.lua --list > docs/test-cases.md`.

### test_load.lua (13)

- load: NS is the AceAddon object named CombatTrail
- load: the identity constants
- load: NS.db.profile exists after OnInitialize, with the defaults' sub-tables
- load: the core seams are published
- load: NS.Compat.ClientKey() follows the kit profile
- load: NS.Compat.ClientKey() is retail on a retail mock and forever on a forever mock
- load: NS.Compat.ForClient keeps a declared feature on its clients only
- load: NS.Print tags its line with the chat prefix
- load: the library-absent load still loads and initializes
- load: the settings stamp is 2 and the fight record's format is 2
- load: a schema 1 store loads empty at version 2, keeping the account's other state
- load: a store already at version 2 keeps its fights
- load: a fresh install runs step 2 harmlessly

### test_loadorder.lua (4)

- load order: the runner loaded exactly the TOC's files, in the TOC's order
- load order: the locale and the namespace come first, the AceAddon promotion after the printer
- load order: every derived path exists on disk
- load order: no libs/ path leaked into the addon's own list

### test_vendor_sync.lua (3)

- libs/LibKa0s is the LibKa0s release CLAUDE.md says this addon bundles
- tests/_kit is the test kit that shipped with that release
- the automated-test runner is recorded executable (100755)

### test_settings.lua (19)

- settings: the pages register in the panel's order, General first and Profiles last
- settings: every page is a subcategory under its player-facing name
- settings: every page renders without printing
- settings: the General page's tabs are Master controls, Look and skin and Keybindings
- settings: general.enabled round-trips through /ct set and /ct get
- settings: general.locked round-trips through /ct set and /ct get
- settings: general.testMode round-trips through /ct set and /ct get
- settings: general.simMode round-trips through /ct set and /ct get
- settings: general.hudInCombat round-trips through /ct set and /ct get
- settings: general.minimap.shown round-trips through /ct set and /ct get
- settings: general.debug round-trips through /ct set and /ct get
- settings: general.fontScale round-trips through /ct set and /ct get
- settings: the minimap row stores LibDBIcon's own hide key in the global store
- settings: general.enabled false stands the addon down, true stands it up
- settings: the session rows never reach the profile
- settings: a stored write announces SETTINGS_CHANGED with its path
- settings: the schema validates against the defaults
- settings: Reset all settings puts every general row back
- settings: library absent, the pages register nothing and the switch still writes

### test_slash.lua (19)

- slash: help lists every verb spec §8 names
- slash: help lists every COMMANDS verb, in order
- slash: an unknown verb says so and prints the help
- slash: bare /ct opens the settings panel
- slash: /ct and /combattrail are both registered on the one dispatcher
- slash: disable and enable write general.enabled through the seam
- slash: a feature verb refuses with the one line while disabled; settings verbs still answer
- slash: disabled, each feature verb answers one refusal line; lane, ignore and dummy still act
- slash: under the perf hold alone a feature verb answers the capture line
- slash: lock and unlock write general.locked
- slash: test turns test mode on and off
- slash: `debug on`/`off` flip the session flag; bare `debug` toggles only the window
- slash: `resetall` asks first, through the one popup
- slash: a verb whose feature is not built yet says so in one line
- slash: the stub's live-verb set is the library's LIVE_VERBS
- slash: the stub's refusal format is byte-equal to the live library's
- slash: library absent, /ct still answers, and enable/disable still land
- launcher: the menu carries Enabled, Locked, Test mode, Sim mode and Show window
- launcher: the menu's toggles are the slash verbs' handlers

### test_lane_casts.lua (33)

- lane casts: both lanes carry spec §4's defaults
- lane casts: delve and arena exist only on Retail (clients-§4)
- lane casts: the client's seed list is picked once (forever profile uses Forever seed list)
- lane casts: player cast pushes to player lane
- lane casts: pet cast pushes to pet lane
- lane casts: same castGUID twice pushes once
- lane casts: the dedupe memory stays bounded
- lane casts: ignored spellID (6603) does not push
- lane casts: an unignored seed (stored false) pushes again
- lane casts: per-lane ignore list is independent
- lane casts: secret spellID still pushes with texture, no raise
- lane casts: a texture lookup that raises still pushes, with no texture
- lane casts: secret castGUID skips dedupe
- lane casts: interrupted cast that had a start pushes with interrupted=true
- lane casts: a failed cast that had a start pushes with interrupted=true
- lane casts: instant cast failure does not push
- lane casts: a cast that started and succeeded pushes once, not interrupted
- lane casts: a failed press during another cast does not mark the cast in flight
- lane casts: the interrupt mark can be turned off per lane
- lane casts: a secret castGUID's interrupt pushes when a cast was in flight
- lane casts: pet lane with no pet: PetName() is nil and label falls back
- lane casts: a secret pet name reads as no name
- lane casts: both lanes on registers the cast events for player and pet only
- lane casts: a lane turned off drops its unit, both off registers nothing
- lane casts: general.enabled off drops every registration, on rebuilds them
- lane casts: a disabled login registers nothing
- lane casts: a listener hears every cast the lanes' rules keep, whatever each lane shows
- lane casts: the log names each registration rebuild and the stand-down
- lane casts: an event the client refuses is logged once
- lane casts: a cast a guard keeps off a lane is logged once per guard
- lane casts: a secret START then a secret FAILED pushes nothing
- lane casts: a secret START, SUCCEEDED, then INTERRUPTED pushes the cast once, clean
- lane casts: a listener that raises costs neither the lane its push nor the next listener

### test_lane_layout.lua (13)

- lane layout: left puts the newest icon at the right edge (age 0 -> x 452)
- lane layout: left scrolls 40 px a second (age 6 -> x 212)
- lane layout: right puts the newest at the left edge and scrolls right (age 6 -> x 240)
- lane layout: up and down mirror left and right on y (TOPLEFT offsets, down is negative)
- lane layout: an unknown direction reads as left
- lane layout: an icon is expired once it has scrolled the whole lane
- lane layout: a cast close behind the newer one is pushed one icon plus spacing away
- lane layout: alpha is 1 before the fade and 0.5 halfway through it (fade 0.2)
- lane layout: fade 0 keeps every icon opaque until it leaves
- lane layout: TickOffsets with a 1.5 s GCD gives 8 offsets in 60 px steps
- lane layout: TickOffsets with a 1 s step gives 12, and nothing for a step of 0 or nil
- lane layout: TickStep reads the spacing setting and the haste
- lane layout: LaneSize is length by icon, plus the padding, turned for up and down

### test_lane_render.lua (38)

- lane render: a push shows one icon with the cast's texture
- lane render: the pool reuses frames after expiry
- lane render: OnUpdate is armed while icons show and nil once the lane is empty
- lane render: OnUpdate moves the icon and fades it
- lane render: Clear empties the lane and disarms OnUpdate
- lane render: the icons a lane holds stay bounded however fast casts arrive
- lane render: a cast LaneCasts hears reaches the lane over the bus
- lane render: a lane switched off hides and takes no push
- lane render: stand-down clears and hides every lane; stand-up shows them again
- lane render: Apply restyles the border color on live icons
- lane render: icon size and zoom follow Apply
- lane render: an interrupted item shows the ✕ mark, a clean one does not
- lane render: a long base cooldown glows, cached per spellID
- lane render: a secret base cooldown is never compared or cached, and nothing raises
- lane render: glowMinCD sets the bar and glowLongCD off never glows
- lane render: a secret texture goes to SetTexture untouched, and nothing raises
- lane render: the tooltip is wired only while `tooltip` is on
- lane render: stack folds a repeat of the newest cast into one icon with a count
- lane render: showName writes the spell's name under the icon
- lane render: ticks follow the spacing setting and switch off
- lane render: haste-adjusted ticks read UnitSpellHaste out of combat
- lane render: the size follows width, icon size, padding and direction
- lane render: the label reads You, and the pet's name or a dimmed Pet
- lane render: background and now line follow their switches
- lane render: icon levels stay within laneLevel+1..laneLevel+8 after 500 pushes
- lane render: the newest icon has the highest level in the band
- lane render: lane uses its configured strata (default LOW) and Apply moves live icons with it
- lane render: no absolute SetFrameLevel call (every level is the lane's plus a LAYERS offset)
- lane render: the skin draws each color while its companion is on, the swatch once it is off
- lane render: a class color comes before the skin's
- lane render: the label's From skin flags resolve through the skin's outline
- lane render: the label draws the skin's label color while its companion is on
- lane render: a skin switch repaints a live lane
- lane render: a skin's border styles draw the edges while their companions are on
- lane render: a skin switch repaints the interrupt mark on a live icon
- lane render: haste ticks keep the last plain haste in combat and never read it there
- lane render: the spell names under the icons use the label's face, the skin's while it is on
- lane render: Count answers a lane's live icons without building it

### test_lane_anchor.lua (33)

- lane anchor: free mode uses saved point
- lane anchor: dock pet under player follows player
- lane anchor: a side-by-side dock puts the gap on the x axis
- lane anchor: a docked lane follows a host docked later in the build order
- lane anchor: dock cycle (player→pet while pet→player) is refused and prints once
- lane anchor: a dock to itself or to a lane switched off falls back to free
- lane anchor: a lane at its fallback place sits on screen, x and y from the CENTER
- lane anchor: leaving dock mode for free moves a TOP under BOTTOM point to CENTER
- lane anchor: dragging a lane at its fallback place keeps its dock point
- lane anchor: the unit frame list names each supported addon, Blizzard's last
- lane anchor: unit-frame mode picks the first existing frame in order
- lane anchor: a frame named by the player wins over the list
- lane anchor: a forbidden frame is skipped
- lane anchor: missing frame falls back to free and prints one diagnostic
- lane anchor: a unit frame missing at login is looked for again on entering the world
- lane anchor: switching to unit-frame mode makes the strata Match host
- lane anchor: leaving free mode moves a CENTER-to-CENTER point to TOP under BOTTOM
- lane anchor: strata follows host when strata="HOST"
- lane anchor: explicit strata (e.g. LOW) overrides the host in unit-frame mode
- lane anchor: level offset adds to the relative base
- lane anchor: a secret host strata or level is never used
- lane anchor: Edit Mode shows each lane's overlay and closing it hides them
- lane anchor: the Locked row keeps Edit Mode from showing the overlay
- lane anchor: /ct unlock shows the overlay and /ct lock hides it
- lane anchor: an unlocked lane shows even when its visibility says never
- lane anchor: the overlay is chrome over the icon band, mouse-live at MEDIUM or above
- lane anchor: dragging a free lane saves its place
- lane anchor: Edit Mode closing under a drag still saves the place
- lane anchor: a docked lane is not dragged on its own
- lane anchor: ResetPosition puts both lanes back where they started
- lane anchor: stand-down drops the Edit Mode callbacks and hides the overlay
- lane anchor: a place saved with no schema row builds the table it writes into
- lane anchor: a delve reads as none on WoW Forever, whatever the client says (clients-§4)

### test_lane_visibility.lua (30)

- lane visibility: show always shows in and out of combat
- lane visibility: show never hides everywhere
- lane visibility: show combat shows only in combat
- lane visibility: show combatOrTarget shows in combat or with a target
- lane visibility: an unknown show mode reads as always
- lane visibility: hideAfter keeps a combat lane up for N seconds after combat
- lane visibility: each where key maps its instance type
- lane visibility: a scenario outside a delve counts as the open world
- lane visibility: a delve is its own where key on Retail
- lane visibility: forever: delve/arena keys absent from the defaults the Lanes page reads
- lane visibility: mounted, vehicle, pet battle and resting each hide while their rule is on
- lane visibility: the hide rules' defaults (mounted, vehicle and pet battle on; resting off)
- lane visibility: Alpha follows alphaCombat and alphaOOC
- lane visibility: Context reads the client
- lane visibility: a lane set to never hides, and back to always shows
- lane visibility: a combat lane shows on PLAYER_REGEN_DISABLED and hides hideAfter seconds after
- lane visibility: combatOrTarget follows PLAYER_TARGET_CHANGED
- lane visibility: mounting hides the lane through PLAYER_MOUNT_DISPLAY_CHANGED
- lane visibility: a vehicle hides the lane through UNIT_ENTERED_VEHICLE
- lane visibility: a pet battle hides the lane until it closes
- lane visibility: resting hides the lane once hideResting is on
- lane visibility: a where key switched off hides the lane on ZONE_CHANGED_NEW_AREA
- lane visibility: the lane's alpha follows combat
- lane visibility: a cast on a hidden lane is dropped
- lane visibility: hiding a lane clears its icons and its OnUpdate
- lane visibility: the first cast of a pull shows a combat lane before PLAYER_REGEN_DISABLED
- lane visibility: UNIT_PET refreshes the pet lane's label
- lane visibility: events are registered only while some lane uses their rule
- lane visibility: a lane set to never or switched off needs no event
- lane visibility: stand-down drops every registration and the hide-after timer

### test_lanes_page.lua (25)

- lanes page: all seven tabs exist, General first and Ignored spells last
- lanes page: every lane setting has a row for each lane
- lanes page: switching dropdown rebinds every control to lanes.pet.*
- lanes page: a pick keeps the open tab
- lanes page: copy from player copies everything but anchor and label
- lanes page: reset lane restores defaults for that lane only
- lanes page: forever profile: no delve or arena rows on the Visibility tab
- lanes page: vehicle and pet battle hides are Retail-only rows
- lanes page: Size and position has Frame strata (BACKGROUND to HIGH, + Match host in unit-frame mode) and Frame level 0-50
- lanes page: the dock gap and the frame name show only in the modes that use them
- lanes page: ignore tab add by ID, by name, remove, reset to seed
- lanes page: slash: /ct lane pet off disables the pet lane
- lanes page: slash: /ct ignore add 2649 pet
- lanes page: the lane and ignore verbs answer while the addon is disabled
- lanes page: the page's Defaults resets both lanes and their ignore lists
- lanes page: preview fills the picked lane with sample casts
- lanes page: a Use class color companion draws the player's class color
- lanes page: the words follow options-ui-§16/§21 and frame-layering-§1
- lanes page: every pixel row says (px) (options-ui-§21 Units)
- lanes page: the three texture pickers offer Flat, so the flat default stays pickable
- lanes page: the Frame level tooltip says lanes at one level mix their icons (frame-layering-§3)
- lanes link: off by default; on, the Pet lane reads the Player lane's look but keeps its own place
- lanes link: a linked Pet lane follows the Player lane's Visibility
- lanes link: the Pet lane's tabs show only the rows it keeps while linked, with a note
- lanes link: Copy from Player lane gives the Pet lane its own copy and unlinks it

### test_probe.lua (33)

- probe: report runs with no C_DamageMeter
- probe: the enemy view lists each enemy's every field (issue #6's feasibility)
- probe: the spell color curve section says when the client has no curve API
- probe: the spell color curve maps a plain pet ID and a plain other ID to their colors
- probe: each sample runs the formatter trial and the color curve on what the HUD draws
- probe: report lists the 8 functions with mock meter
- probe: a function the client lacks is named
- probe: a meter call that raises is reported, never raised
- probe: secret values reported as <secret>, never tostring'd
- probe: the report is written to the debug console in one chat line
- probe never registers COMBAT_LOG_EVENT_UNFILTERED
- probe: in-combat samples recorded via kit combat toggle
- probe: a second /ct probe after the fight reports without arming again
- probe: start in combat takes the +5 s sample now
- probe: start resets the counts and samples; stop disarms
- probe: an unknown word answers the usage line
- probe: cast secrecy counts, in and out of combat, player and pet
- probe: pet is separate source: yes
- probe: pet is separate source: no while the pet's own source is empty
- probe: pet is separate source: no while the player's source holds the pet's spells
- probe: pet is separate source: unknown with no pet, or while the values are secret
- probe: pace pet-fill anchor check builds hidden bars and reports ok
- probe: pace pet-fill anchor reports a SetPoint that raised
- probe: stand-down drops its registrations; stand-up brings them back while armed
- probe: nothing is registered until the probe is armed
- probe: Disarm and a fresh Arm cancel the samples still pending
- probe: a plain /ct probe in combat schedules the +5 s sample, one per combat
- probe: a function the client lacks reads missing, not raised
- probe: the pet verdict says it cannot see double counting
- probe: forever: the report dumps every talent API's answer and the tree it picks
- probe: forever: missing or secret talent answers never raise
- probe: forever: a talent read that raises prints one line and the rest of the report
- probe: retail: no talent-tree section (clients-§4)

### test_meter.lua (37)

- meter: the stat and session constants come from the client enum
- meter: without the enum, the documented values stand and the enemy view is unread
- meter: PET_SEPARATE is the spec §12 seam, true out of the box
- meter: IsAvailable passes Blizzard's reason through, and answers on a client without the API
- meter: SessionIDs and HasSession track the client's list by plain ID, in combat too
- meter: SessionAfter answers the first session that appeared at or after t
- meter: SessionIDs says whether the read succeeded, so a raise is not a reset
- meter: SessionsAfter answers every session since t, oldest first, from a list already read
- meter: SessionAfter reads IDs mid-combat and forgets a session the client dropped
- meter: a stand-down forgets the baseline; the stand-up primes it again
- meter: ResolvePet answers the pet's GUID, nil with no pet, and remembers the last plain one
- meter: ReadLive returns opaque player and pet tables
- meter: ReadLive with no pet GUID returns pet=nil
- meter: ReadLive with a pet the meter has no source for returns pet=nil
- meter: ReadLive reads the Current session, or one session by ID
- meter: ReadLive answers no sources with no session, and nil with no API or a raising client
- meter: the player's live DPS rungs: the source, the local row, the Dps type, else nil
- meter: the rung that served is logged once per fight, under the Meter tag
- meter: ReadFinal merges player+pet totals and marks isPet
- meter: ReadFinal with no pet is the player alone
- meter: ReadFinal reads the pet that fought after it was dismissed
- meter: an opaque pet GUID reaches the client untouched and is never remembered
- meter: ReadFinal returns nil while values are secret
- meter: ReadFinal of a missing session, a raising client or no API answers nil and a reason
- meter: ReadFinal with no damage of the player's is a zero result, not an error
- meter: amountPerSecond nil → dps computed as total/duration in ReadFinal
- meter: an empty pet source falls back to tagging the pet's spells in the player's
- meter: a folded source's rows the meter names a creature on are the pet's, Auto Attack too
- meter: the pet with no cast set yet still splits by creature name
- meter: ReadLive flags a row the meter plainly names a creature on; a secret name says nothing
- meter: a creature name still secret after combat seals the record read
- meter: PET_SEPARATE=false path tags by cast set
- meter: ReadEnemies sorts by damage taken
- meter: ReadEnemies is empty with a reason while sealed, missing or without the enum
- meter: modules/Meter.lua is the only file that reads C_DamageMeter
- meter: Call reports a missing function and a raising one without throwing
- meter: ReadFinal keeps the player's part when only the pet's read raises

### test_format.lua (19)

- format: a plain fractional DPS abbreviates in Lua, never through the client formatter
- format: a secret goes to a formatter that passes both checks
- format: a formatter that renders a fraction raw fails the check, and the next constructor answers
- format: a client formatter that is a userdata, not a table, is still used (WoW Forever, 2026-11-11)
- format: a rule formatter refusing the ladder serves whole numbers, never a raw fraction
- format: a secret with no trusted formatter goes to AbbreviateNumbers
- format: a secret with no client formatter at all is handed back untouched
- format: a secret the client formatter answers with a secret string goes to SetText untouched
- format: Secrets.IsPresent answers a secret and a plain value without comparing either
- format: the debug log names the path that served a number, once per change
- format: a refused or failing constructor is skipped
- format: a formatter that passes its checks but raises on a secret says so, once (WoW Forever, 2026-11-11)
- format: the probe's trial runs every path on a value and describes each answer
- format: the trial on a secret never shows its text
- format: a client formatter that raises on a secret is dropped after the first
- format: a secret rate is written whole by FloorToNearestString, never with its decimal tail
- format: a total and a rate drawn in turn log each path once, not a line per redraw
- format: a plain rate abbreviates in Lua; with no helper a secret rate takes Number's chain
- format: Clock, Length, Pct and SignedPct take plain numbers

### test_fight.lua (30)

- fight: the states and the timing constants are the plan's
- fight: normal combat → started, ticks, ended final
- fight: the tick runs at 4 Hz in combat only
- fight: a session that appears after combat entry binds on its first update
- fight: an older session is never bound, and a fight with no session ends lost
- fight: secret update arguments bind through the session list, never compared
- fight: a DPS-type update is not damage and starts no clock
- fight: FD within grace keeps one fight
- fight: FD beyond grace ends the first fight
- fight: re-entry past the grace while updates still land parks the first fight until the settle
- fight: a new session within grace without an encounter is a new fight
- fight: encounter split sessions merge after combat
- fight: an encounter that starts mid-combat with a meter split is its own fight
- fight: an encounter that starts mid-combat without a split names the whole fight
- fight: a wipe and a new pull of the same boss are two fights
- fight: an encounter that ends while idle (the player died out of it) names no later fight
- fight: meter reset mid-fight → lost
- fight: the bound session disappearing → lost; a failed list read is no evidence
- fight: a session gone by the settle read ends lost
- fight: settle waits for quiet
- fight: a still-sealed read retries, then reads
- fight: a read sealed past the retries ends lost
- fight: idle registers only the idle events
- fight: COMBAT_LOG_EVENT_UNFILTERED is never registered
- fight: an event the client rejects costs only itself, and is never unregistered
- fight: disabled addon registers nothing
- fight: a stand-down mid-fight drops the fight, its timers and every registration
- fight: an encounter that starts in combat while idle starts a fight
- fight: COMBAT_ENTERED is sent on the regen edge from idle, on the grace carry-on and on park+begin
- fight: COMBAT_ENTERED is not sent on a meter split, ENCOUNTER_START in combat, or while stood down

### test_identity.lua (47)

- identity: boss fight key e:3176:15
- identity: M+ trash key carries :k12
- identity: a dungeon without a keystone is dungeon content with no qualifier
- identity: delve key carries :d8 (retail)
- identity: a scenario that is no delve is scenario content
- identity: bg key carries bracket
- identity: an arena is arena content on retail, keyed by bracket
- identity: open world key has no qualifier
- identity: a named target with no NPC ID falls back to the name-only key
- identity: the snapshot reads the target's level
- identity: the key is t:<npcID>:<level>:<name>:<difficulty>
- identity: one NPC at two levels is two boards; the same NPC and level share one
- identity: a skull level keys as -1
- identity: the level is taken only when the primary is the snapshot's target
- identity: a boss fight's key ignores the level and the NPC ID, which stay for display
- identity: a world boss keeps its creature key, level aside
- identity: a sealed level or GUID leaves the fields nil and never raises
- identity: where carries the zone and subzone; sealed or raising ones are absent
- identity: the dummy seed is picked once, per client; Forever's is empty by decision
- identity: dummy creature -> content dummy
- identity: a dummy found only by the snapshot's target is still a dummy
- identity: no enemies and no snapshot -> Unknown target, key nil
- identity: an encounter with no readable enemy is named by the encounter and keeps its board
- identity: a battleground fight with no readable target has no board
- identity: a world boss target snapshot makes a boss
- identity: the snapshot reads who and target
- identity: a player target's GUID is no creature
- identity: a secret target in combat leaves its fields absent, never raises
- identity: the fight's snapshot is taken at combat entry
- identity: forever: delve/mplus fields never set
- identity: the content keys follow the client
- identity: two-word Forever names handled
- identity: forever: trees 31/20/0 make the first tree the spec (talent tabs)
- identity: forever: the C_Traits groups stand in when there are no talent tabs
- identity: forever: a tie goes to the first tree
- identity: forever: 0/0/0 or no talent API gives no spec and never raises (Review focus 5)
- identity: forever: the second talent-tab shape (id, name, desc, icon, points) reads too
- identity: forever: sealed points give no trees; the last plain read stands in
- identity: forever: a sealed config ID keeps the last plain read and never raises
- identity: forever: a sealed config info keeps the last plain read and never raises
- identity: forever: a sealed tree list keeps the last plain read and never raises
- identity: forever: a sealed tree ID keeps the last plain read and never raises
- identity: forever: a sealed group list keeps the last plain read and never raises
- identity: forever: a sealed currency row keeps the last plain read and never raises
- identity: forever: Prime reads the trees out of combat, so the session's first sealed read has one
- identity: the stand-up primes the trees (core/CombatTrail.lua RegisterGameEvents)
- identity: retail: the talent trees are absent and the spec is the client's

### test_dummies.lua (29)

- dummies: the seed is picked once per client; Forever's is empty by decision
- dummies: Lookup answers the seed by creature ID, with its name and category
- dummies: Lookup answers a copy, so a caller cannot edit the seed
- dummies: five categories in order, each with an enUS label, and Other for no dummy
- dummies: Parse reads entries and hides, ascending, the last of an ID winning
- dummies: Normalize drops a custom entry for a built-in and a hide of a non-built-in
- dummies: the row refuses what does not parse and stores what it normalizes
- dummies: Add marks a creature, Lookup answers it, Remove takes it off
- dummies: a custom dummy added with no category is single target
- dummies: a built-in is switched off and back on, never recategorized
- dummies: Defaults clears the list; a profile switch reads the other profile's
- dummies: a typed category word is a key or its label; auto and nonsense are none
- dummies: a custom dummy makes a fight's content "dummy" on WoW Forever too
- dummies: a built-in switched off is open-world content again
- dummies: test mode's sample dummy keeps its seed name when the player switches it off
- dummies: Read and Capture keep what the game says, by map, and count the captures
- dummies: a sealed field is left out of the read, and a player is no creature
- dummies: Resolve takes an ID or a captured or seeded name
- dummies: a captured custom dummy answers its captured name
- dummies: the Training dummies section is on both clients
- dummies: the row's default empties the list
- dummies: the tab draws Add your target, the list, a box per built-in and Reset list
- dummies: Add your target counts the target as single target, and says so with none
- dummy verb: add marks the target, captures it and says what it saved
- dummy verb: add refuses a word that is no category, no target, and a player
- dummy verb: on a built-in, add says so and captures; remove switches it off, add brings it back
- dummy verb: remove takes a typed creature ID or name; show lists yours and the switched-off
- dummy verb: capture saves without marking; an unknown word prints the usage
- dummy verb: answers while the addon is disabled, on both clients

### test_cast_codec.lua (7)

- cast codec: the format is delta deciseconds and the spell ID in base 36, flags after a colon
- cast codec: codec round-trips 0.1 s times and flags
- cast codec: an out-of-order list still round-trips (a negative delta)
- cast codec: Decode skips what does not parse and answers an empty list for nothing
- cast codec: 250 casts packs under 2.5 KB
- codec: the spell list round-trips with the pet flag and a raid-sized total
- codec: the spell list skips a row without an ID or a total, and a token that does not parse

### test_casts.lua (17)

- casts: a fight's casts come from the lanes' capture, timed from its combat entry
- casts: pet casts tagged unit=pet, and the pet's spells make PetSpellSet
- casts: secret spellID cast is dropped from the record, not stored as nil-key
- casts: an interrupted cast is kept with interrupted=true; an instant that fails is not
- casts: the auto-repeat swings and shots are never kept
- casts: the record hears a lane that is off and a spell a lane ignores
- casts: no second UNIT_SPELLCAST_* registration; lanes off still hear both units for the record
- casts: a pre-pull cast within PREPULL is kept at a negative time; an older one is not
- casts: the next fight's pre-pull never reaches into the fight before it
- casts: a fight parked at a late re-entry ends at its combat end
- casts: a lost fight's capture is dropped
- casts: Live reads the fight in progress without ending it; Finish answers once
- casts: Finish answers each spell's base cooldown, known ones only, asked once per spell
- casts: a secret base cooldown is not cached, so the spell's cooldown arrives once readable
- casts: while idle the buffer holds only the pre-pull's worth
- casts: a stand-down drops every capture and the buffer
- casts: IsLong is 29 s or more; Group orders long cooldowns first, then by count

### test_usage.lua (11)

- usage: the snapshot reads the on-use slots, the bag consumables and the auras
- usage: an item's class is asked once per session, not on every snapshot
- usage: an unreadable bag stack makes the after counts unknown, never a false drop
- usage: a sealed aura ends the aura walk; a client without the APIs snapshots nothing
- usage: detection stacks casts, the bag drop and the start's auras, in that order
- usage: usage detects potion from cast + bag delta
- usage: of two items with one use spell, a cast is the one whose count dropped
- usage: the candidates are the on-use gear, then every bag consumable by item
- usage: each fight snapshots at its start, and ForFight detects with the counts after it
- usage: a parked fight's end counts are taken as the next fight starts
- usage: food is found by the Well Fed spell ID, or by the client's own name for it

### test_stats.lua (9)

- stats: on WoW Forever Read reads the classic panel's set and never asks the spec
- stats: on WoW Forever the view is the classic panel's two groups, an unread row left out
- stats: Read reads the primary stat, stamina, armor and every rating with its percent
- stats: crit is the highest of melee, ranged and each spell school's
- stats: a secret value is absent, never compared or kept
- stats: a client without the APIs, or one that raises, yields absent fields; nothing readable is nil
- stats: the fight's start read rides the fight; Fill completes it after combat from a fresh read
- stats: Groups lays out Primary, Secondary and Tertiary with each value's text
- stats: deltas against the compared fight, signed, the percent deciding a rated row

### test_loadouts.lua (22)

- loadouts: an item link trims to its item string, and back
- loadouts: Snapshot reads the gear as item strings without the shirt or the tabard, and the talents
- loadouts: a client without the APIs, or one that raises, or a secret, yields absent fields
- loadouts: the snapshot rides the fight from its start
- loadouts: the hash is djb2 as eight hex digits, and pure
- loadouts: loadout dedupes by hash
- loadouts: two loadouts with one hash are told apart; the same one finds its own key
- loadouts: Sweep drops the loadouts no stored fight refers to
- gear sets: one changed slot (an enchant) is a second set; the stored set is a plain copy
- gear sets: two sets with one hash are told apart by their canonical form
- gear sets: a burst of six PLAYER_EQUIPMENT_CHANGED in one frame interns one set
- gear sets: a login with unchanged gear makes no new set
- gear sets: recon runs on PLAYER_ENTERING_WORLD, on the equipment change and on UNIT_INVENTORY_CHANGED
- gear sets: a stand-down drops the events and the pending recon; the stand-up reconciles
- gear sets: the fight takes the set current at combat start, even with a swap pending or in combat
- gear sets: a recon in combat over sealed links is read again once combat ends
- gear sets: a recon the pull runs in combat over a sealed link is read again once combat ends
- gear sets: with no set known yet, the pull reconciles once
- gear sets: GearOf reads the record's set, else an inline gear (sample fights)
- gear sets: Sweep drops the orphaned sets, keeping the referenced and the current one
- gear sets: Sweep mid-fight keeps the live fight's set after a swap in combat
- gear sets: the stored size estimate counts the sets

### test_filters.lua (12)

- filters: the history defaults are the plan's
- filters: the minimum length defaults to 30 s on Retail and 15 s on WoW Forever
- filters: every content kind is saved by default, scenarios too
- filters: the content toggles are exactly this client's content kinds
- filters: retail: the mplus, delve and arena toggles are present and on
- forever: mplus/delve/arena filter keys absent
- filters: a fight under the minimum length is skipped as short
- filters: the minimum length follows the setting
- filters: bossesOnly drops non-encounter
- filters: content toggle drops world
- filters: scenarios are stored by default, a kind without a toggle is dropped
- filters: the short check comes before the content check

### test_bests.lua (10)

- bests: best per character×spec×boardKey
- bests: For with exclude answers the runner-up
- bests: unknown target never a best
- bests: a record with a board key but the unknown flag, or no character, never counts
- bests: one NPC at two levels is two boards; the same NPC and level share one
- bests: a tie goes to the earlier fight
- bests: BestCurve names the best fight's id for a board, a character and a spec
- bests: the boards follow a save and a delete
- bests: the character key carries the client, so boards never mix Retail and Forever
- bests: forever: the predominant tree splits the boards as a spec does (D5)

### test_retention.lua (13)

- retention: purge removes >7 days except bests
- retention: keepBests off lets an old best go
- retention: days=0 keeps forever
- retention: purge of 600 fights keeps bests and caps at 500
- retention: maxFights 0 is no cap
- retention: a purge sweeps the loadouts no fight holds any more
- retention: the purge repairs an order that lost step with the store
- retention: a record from a later version is left alone
- retention: the purge runs at login and on a daily timer
- retention: the daily run waits out combat and a fight in progress
- retention: the stand-down cancels the daily timer, the stand-up arms it again
- retention: /ct purge purges now and says how many went
- retention: EstimateBytes sizes the store as SavedVariables writes it

### test_record.lua (18)

- record: a real fight becomes a stored record with the spec §5 fields
- record: a 10 s fight is skipped as short
- record: a lost fight is skipped as lost
- record: a filtered fight is skipped as filtered
- record: a fight with no readable character is skipped as unknown
- record: a fight with no readable target is stored as Unknown target, with no board key
- record: an unreadable meter duration falls back to the fight's own clock
- record: the fight's casts are packed into the record
- record: the enemies are summed across a merged fight's sessions
- record: the stored fight keeps its targets, summed across sessions (issue #6)
- record: 5-min raid record < 6 KB
- record: All walks newest first; Delete and SetNote edit the store and say so
- record: two fights saved in the same second get distinct ids
- reload mid-fight leaves store valid
- no secret reaches the record
- record: a short fight with no readable character is skipped as short, the filters first
- record: three fights in the same gear share one gear set; a swap between fights is a second
- record: targets merge enemies of one name, highest first, whole, capped

### test_slices.lua (18)

- slices: a 2 s step, at most 60 columns, a column that grows with the fight
- slices: a read copies the handles into each step it is the first read at or after
- slices: a store without Begin takes nothing, and a secret id is never a key
- slices: the store never inspects a value, a secret or a plain one
- slices: the store grows with an open-ended fight and stops at MAX_STEPS
- slices: a 5 minute fight re-buckets into 50 columns of 6 s, each its last step's total
- slices: a column whose last step is a hole takes its latest filled step, and an empty one stays empty
- slices: an expected length sizes the columns before the fight reaches it
- slices: the views are cached until the next capture
- slices: Tail is the last 60 steps, one column a step
- slices: a closed store takes no more reads, and only KEEP closed stores are held
- slices: Drawable answers only a final record with plain damage and steps this session
- slices: a secret fight is captured once a step, opaque, and its record finds the chart
- slices: a fight the recording filters skip lets its store go, so it never holds a KEEP slot
- slices: no read before a session is bound, and those boundaries become holes
- slices: a lost fight forgets its store, and the stand-down drops an open one
- slices: Seed fills in the step, count and filled a store leaves out
- slices: a saved fight's store keeps its record id, not the fight table

### test_hud_states.lua (25)

- hud: the states and the defaults are the plan's
- hud: auto: hidden -> live on FIGHT_STARTED's first hit
- hud: the live figures are the meter's handles, copied and never inspected
- hud: a fractional secret DPS draws the trusted formatter's text, never a raw decimal
- hud: noBest when Bests.For is nil hides pace; a stored best makes it live with pace
- hud: the live pace key is the stored boardKey, level and NPC ID included (plan A2)
- hud: paceAgainst none is always noBest; last paces against the newest fight on the board
- hud: over card after FIGHT_ENDED final with saved chip
- hud: a faster fight on the board says New best with its gain
- hud: skip reason chip on FIGHT_SKIPPED short
- hud: overCard off: an auto-opened HUD closes with the fight
- hud: fades after hud.fadeAfter unless mouse over or pinned
- hud: a pointer that leaves from a chip still lets the card fade
- hud: fadeAfter 0 keeps the card up until the next fight or a close
- hud: a HUD the player opened never fades
- hud: toggle mode never auto-shows
- hud: Show DPS HUD in combat off: auto opens nothing
- hud: always mode is up at login and after a stand-up, and never fades
- hud: instancesOnly hides in world
- hud: always beats instancesOnly: in the open world it stays up through two fights
- hud: always plus instancesOnly: a player close holds for that fight only
- hud: a HUD the player closed mid-fight stays closed for that fight
- hud: /ct hud show, hide, pin and unpin
- hud: Locked stops the drag; Reset position puts it back
- hud: disabled addon: hidden, no timer, and no fight opens it

### test_hud_pace.lua (5)

- pace: uses the best's slices when present, else its linear pace
- pace: the bounds sit the best's pace in the middle; the range is held to the slider
- pace: split at the tick, red short of it, green past it; a separate pet paces player-only
- pace: a total with no pet source of its own runs against the best's merged pace
- pace: no best, or the layout's pace off, hides the bar

### test_hud_chart.lua (7)

- chart cooldown icons for base CD >= 29 s
- chart: unchanged cooldown icons are not laid again on the next ticks
- chart: the HUD and the slices share one live read on a boundary tick
- chart: live columns are the slices, scaled to the best's player damage
- chart: with no best the scale is the live total itself, and no line
- chart: hud.chart.columns caps the columns; the layout's chart off hides it
- chart: the pure layout helpers

### test_hud_breakdown.lua (11)

- breakdown never sorts or computes in combat (mock secret values)
- breakdown: pet rows carry paw and pet color
- breakdown: a folded pet row the meter names a creature on draws as the pet's, live
- breakdown: the over card's rows are merged, highest first, with their shares
- breakdown: hud.bars caps the rows and the wheel scrolls past them
- breakdown: the layout's spell rows off hides them
- hud: the live DPS figures are written whole through the rate path; Damage is not
- hud: the DPS box shows your pet's DPS too; your figures share a color, the pet's another
- breakdown: every other spell row is faintly tinted, on the HUD and in the fight detail (2026-11-11)
- breakdown: the snapped rows are whole pixels, never taller than the layout's room (2026-11-11)
- breakdown: at a UI scale that is not round, every row and its border sit on whole pixels (2026-11-11)

### test_hud_appearance.lua (8)

- every hud appearance key applies (one assertion per key via Apply)
- appearance: every look key in the defaults has a case
- appearance: the spell bars draw no border out of the box
- appearance: Hud.Apply bumps the stamp, so a part restyles once, not on every tick
- palette: NS.Constants.PALETTE holds the shared bar colors
- palette: the HUD's bar defaults equal the palette entries
- palette: each block's swatch is its own table, never the palette's
- palette: the live HUD draws the palette with no setting touched

### test_hud_page.lua (14)

- hud page: six tabs, Behavior first and Window last
- hud page: every hud.* default has a control
- hud page: every row's default is the profile's (defaults/Profile.lua is the only source)
- hud page: changes apply live via Hud.Apply
- hud page: a drawn control writes through the seam and the HUD follows
- hud page: every tab renders without printing
- hud page: the composed blocks follow the skin with the profile's defaults
- hud page: every color is a ColorPair with its Use class color companion
- hud page: Frame strata offers BACKGROUND to HIGH and never DIALOG (frame-layering-§1)
- hud page: the words follow options-ui-§21: (px), (seconds), never (s)
- hud page: no subsection restates its tab (options-ui-§7) and no row names a Retail-only feature (clients-§4)
- hud page: the value checks refuse what the HUD cannot draw
- hud page: /ct set reaches a hud path, and hud.show always opens the HUD
- hud page: the page's Defaults puts every hud row back

### test_hud_layout.lua (9)

- hud layout: the live body stacks the top, Damage profile, the pace bar, the plot, Spell breakdown
- hud layout: the fight-over card stacks the same under its chips
- hud layout: with the plot off the heading stays over the pace bar
- hud layout: with nothing to pace against the plot sits right under its heading
- hud layout: the defaults are DPS Race's sizes
- hud layout: the window is 260 wide on DPS Race's insets, its height the stack's
- hud layout: a spell row is 18 high in a 10 point face, its icon 16
- hud layout: the clock draws DPS Race's 40 in the skin's face
- hud layout: the settings' width floor is the HUD's

### test_hud_sizing.lua (19)

- hud sizing: the defaults are fixed, 5 bars, grow down; spells.rows is retired
- hud sizing: the fixed height is derived from the bars, the same with 0, 3 or 20 spells
- hud sizing: every part shown with a pet fills the fixed window exactly
- hud sizing: a layout part switched off shrinks the fixed height, the bars stay
- hud sizing: a pet appearing mid-fight keeps the fixed height and the bars
- hud sizing: the fight-over card fits the fixed window, fewer rows and the wheel past them
- hud sizing: a grip release stores the width and the rounded bars, and the height snaps
- hud sizing: while the grip is held the rows follow the drag and nothing is stored
- hud sizing: the grip's bounds follow the parts shown
- hud sizing: the grip is hidden while locked and in auto mode, and refuses a drag
- hud sizing: the wheel scrolls the live rows, clamped, and the note counts them
- hud sizing: with every spell in view there is no scroll and no count
- hud sizing: zero spells draws no row and keeps the HUD drawable
- hud sizing: a new fight starts its rows at the top
- hud sizing: auto mode grows with the rows up to the bars, then scrolls
- hud sizing: grow down keeps the top in place, grow up the bottom
- hud sizing: a stored point that already suits the grow edge is kept
- hud sizing: switching the mode mid-fight redraws without error
- hud sizing: grow up chosen before the window is built takes the bottom edge at its first show

### test_sizing.lua (7)

- sizing: a size change the grip did not start redraws at once
- sizing: while the grip is held, one cheap layout a frame; one redraw on release
- sizing: changes inside one frame coalesce into one layout now and one next frame
- sizing: a right press or a refused gate starts no drag
- sizing: a hide while the grip is held ends the drag as a release would
- results sizing: a 30-frame drag rebinds no row until the release, then stores the size
- results sizing: a drag keeps the minimum and shrinks the list without a rebind

### test_results_table.lua (42)

- results: default view: current character, last 7 days, grouped by date and character
- results: the date range and the character filter
- results: bossesOnly filter
- results: the filters are faceted: each list reads the fights the other filters pass
- results: the Spec dropdown and grouping are on both clients; Forever names a talent tree (D5, D11)
- results: forever: the predominant tree is the row's second icon, the Spec filter and the grouping
- results: forever: content facet lacks mplus/delve/arena
- results: delta vs group best
- results: the leader of a group is the earlier fight on a DPS tie
- results: the table's columns are the plan's
- results: table builds 500 rows via pooled rows
- results: a header click sorts, a second flips it, and a saved view keeps the sort
- results: Save persists results.view; Clear goes back to it; Reset deletes it
- results: right-click menu has Note, Share, Compare With This Fight, Delete
- results: the window is a toplevel HIGH browser in the close stack
- results: ShowFight opens the window on the fight; Toggle closes and opens it
- results: the HUD's Results control reaches the window
- results: the verb, Reset position and the Locked row
- results: the drag stores the window's place
- results: the sample source lists its fights, refuses Save view, and gives the store back
- results: the stand-down hides the window and the stand-up brings it back
- results: a saved fight redraws a shown list
- results: every cell and header has a tooltip
- results: entering combat closes the window when Close when combat starts is on, and not when off
- results: a window reopened mid-combat stays open through a split or an encounter start
- results: the fold arrow shows chevron-right collapsed and chevron-left expanded
- results: Character is a fixed 104 px column and the target column takes the rest
- results: the window opens at its least width, which no shipped number overrides
- results: a stored Character width wins, within the room the target column leaves
- results: dragging the Character header's edge resizes it and stores the width on release
- results: a window hidden while the Character edge is held ends the drag and stores the width
- results: a profile switch lays the columns out at the new profile's widths, shown or hidden
- results: no spec: the row draws its class icon and no second icon
- results: no Status column; the best is only compared against (owner, 2026-11-10)
- results: the Used column lists the fight's usage as icons, +n past what fits, a dash for none
- results: the Note column shows the note cut to ten characters, the whole of it on hover
- results: a note is added, edited and cleared from the note box, and a reload keeps it
- results: a note's escape codes and control characters are neutralized
- results: the Damage and DPS bars are the palette's blue, not the class color, under every skin
- results: the list's rows are striped on a white background, every other one tinted
- results: under the date groupings Delta still measures each fight against its encounter
- results: the bar holds Save, Reset and Clear, right to left Clear last

### test_results_detail.lua (20)

- detail: the header meta is three lines: where and who, what, the stamp (plan A2)
- detail: an open-world fight names its zone, not the continent, and the target's level
- detail: shows Leads by on best
- detail: a fight the filters leave out falls back to its board
- detail: a fight with no chart this session has no Damage profile section
- detail: pet spells tagged
- detail: gear in the character frame's order, talents with View Talents and no Copy (C3)
- detail: forever: the talents line names the class and its points per tree (C3)
- detail: usage rows, and Edit for a fight with a usage record
- detail: the buttons and their seams
- detail: the footer in DPS Race's order: Add Note, Share, Timeline, Compare, Delete at the right (C3)
- detail: delete asks to confirm, then FIGHTS_CHANGED
- detail: collapsed puts the detail in the list's place; the fold arrow sets it beside
- detail: ShowFight on a fight the view filters out shows its detail
- detail: the popups the window opened close with it
- detail: the window steps aside for the talent tree and comes back
- detail: forever: the header's second icon is the predominant tree's, hidden with none (D5)
- detail: the Targets section lists each enemy with its amount and share
- detail: a fight with no targets (an older record) has no Targets section
- detail: Targets rows skip a malformed entry and share out of what is listed

### test_results_sections.lua (5)

- sections: every heading has an arrow, open (chevron-down) by default, its text after it
- sections: the arrow folds a section, hides its body, stores it, and moves the next heading up
- sections: a left click on the heading's text folds it; a right click does not
- sections: a rebuilt pane reads the folds back; Reset position keeps them
- sections: the Note's arrow shows with a note only; Add Note opens a folded Note

### test_share.lua (6)

- share: line format and length <= 255
- share: talents link appended when enabled
- share: send goes out of combat only, and the menu grays the channels the player is not in
- share: the row menu's Share is live for a stored fight
- share: the whisper box offers the target as the client addresses them (realm on Retail, full regional name on Forever)
- share: forever: the line names the predominant talent tree (D5)

### test_timeline.lua (12)

- timeline: rows order long CDs first
- timeline: decodes packed casts
- timeline: pet toggle hides pet rows
- timeline: compare lanes align to their own fight start
- timeline: the compare target is the pick, else the best, else the runner-up
- timeline: the axis, the zoom and the stacking arithmetic
- timeline: opens from the detail over the Results window, under its cover
- timeline: pet toggle hides pet rows in the window, the zoom kept
- timeline: zoom, pan and the wheel
- timeline: Escape goes to it first, and it closes with the Results window
- timeline: the empty cases
- timeline: a stand-down refuses the open

### test_timeline_marks.lua (11)

- timeline marks: the fights' colors are the palette's text hues under this kit profile
- timeline marks: the caster colors are the palette's lines, and the row defaults to icons
- timeline marks: by default every cast in By ability is its ability's icon on the lanes' layer
- timeline marks: a lane icon's tooltip is the Casts icon's for the same cast
- timeline marks: a pre-pull cast's icon sits whole inside the lanes' padded clip
- timeline marks: a player's cast is edged PLAYER_LINE and a pet's PET_LINE, in the lanes and the Casts strips
- timeline marks: in tick mode a pet's tick is PET_LINE and a player's PLAYER_LINE in both lanes
- timeline marks: the setting written while the window is open redraws it as ticks, keeping the zoom
- timeline marks: a profile switch redraws an open window in the new profile's mode
- timeline marks: the two words on the By ability heading line switch the marks
- timeline marks: zoomed in, the icons follow the zoomed axis; a drag of the grip moves them without re-pooling

### test_compare.lua (12)

- compare: vs best, runner-up when best
- compare: session pick overrides until cleared
- compare: spells side by side, matched by spell and caster
- compare: different loadout mark
- compare: the window opens over the Results window, follows the detail and closes with it
- compare: an upgraded item is on the gear line
- compare: the gear line reads stored sets, a sample's inline gear, and one set on both says no change
- compare: Escape closes the compare first and the Results window stays
- compare: the Compare button's tooltip names the fight it compares with
- compare: this fight is yellow and the other blue, in the best and the runner-up cases alike
- compare: trinkets and consumables used by both fights, side by side
- compare: the Different loadout tooltip writes a Forever fight's talent points

### test_gear.lua (6)

- gear: the stored item strings parsed for their enchant and gems
- gear: gear changed slots detected
- gear: a stored gear set and a sample's inline gear read alike through Loadouts.GearOf
- gear: the character panel's layout and its size
- gear: the window opens from the detail, marks the changes and closes with the Results window
- gear: a stand-down refuses the open, a deleted fight closes it

### test_usage_edit.lua (4)

- usage edit: the pure rows, ticks and saves
- usage edit: save persists
- usage edit: never-show list hides
- usage edit: a sample fight changes in memory only

### test_history_page.lua (17)

- history page: five tabs, Recording filters first and Training dummies last
- history page: every history.* key, the Results window's settings and the hidden list have a row
- history page: the rows sit on their tabs, the hidden list on Usage
- history page: every row's default is the shipped one (defaults/Profile.lua is the only source)
- history page: forever: no delve/arena/mplus rows
- history page: a content row stores its kind and the filter follows
- history page: the History tab shows the stored count and size
- history page: purge now confirm
- history page: the Usage tab draws the hidden items as the ID list
- history page: Window scale reaches the Results window and every follower
- history page: Row height reaches the Results list
- history page: the words follow options-ui-§21 and no subsection restates its tab (options-ui-§7)
- history page: the minimum length tooltip names this client's default
- history page: every tab renders without printing
- history page: the page's Defaults puts every row back and leaves the fights
- history page: /ct set reaches a history path
- history page: the keep-bests tooltip names the board's spec, a talent tree on Forever (D5, D11)

### test_preview.lua (7)

- preview: test mode fills lanes, HUD and Results with sample strip, nothing written to db
- preview: entering combat ends test mode
- preview: refused in combat; a window the player opened stays
- preview: Reset all settings and the stand-down end test mode
- preview: the sample history spans the client's content kinds (clients-§4)
- preview: a sample fight is the same each time, and its parts agree
- preview: the first-run skin picker shows the HUD's sample in the skin, and its close puts it back

### test_sim.lua (5)

- sim newbest ends with New best chip
- sim short ends Not saved
- sim: behind saves under the best; first has no pace; lost is not saved
- sim: the verb starts it through the step session, and stop ends it
- sim: combat ends it; a refused start leaves nothing on

### test_bindings.lua (11)

- bindings: NS.BINDINGS is Bindings.xml's order, Show window first, each with a tooltip
- bindings: Bindings.xml is the addon's own category, no header, no default, labeled
- bindings: the General page ends in the Keybindings tab, after Master controls
- bindings: the tab's rows are NS.BINDINGS in order, labeled as the client labels them
- bindings: a key bound in the tab is the client's key
- bindings: each button is plain, named, hidden and down-edge only
- bindings: the HUD key runs the launcher's Show window handler
- bindings: the Results key shows and hides the Results window
- bindings: the lanes key turns the lanes off and back on as they were
- bindings: stood down, each key answers the refusal line and changes nothing
- bindings: the General Defaults tooltip says it leaves key bindings alone

### test_diagnostics.lua (6)

- diagnostics: the report carries every section of this addon's own
- diagnostics: a setting off its default is listed with its default
- diagnostics: test mode shows in the preview line
- diagnostics: stood down, the runtime sections say so and the stored ones still print
- diagnostics: the report arms no timer and registers no event
- diagnostics: a rejected event is listed

### test_skin_surfaces.lua (5)

- skin surfaces: every window has a declared surface
- skin surfaces: the runner hands the kit this declaration
- skin surfaces: every lane companion is a row on the Lanes page, on by default
- skin surfaces: the lane label's Font flags lead with From skin, its default
- skin surfaces: each declared companion is a schema row that defaults on

### test_docs.lua (15)

- docs: README opens on its H1 and keeps the canonical section order
- docs: README badge row tracks the TOC and the case inventory
- docs: README names every slash verb
- docs: README carries the fixed bug-report body and the first version row
- docs: README has no numbered list, no placeholder, no logo and no library list
- docs: the root holds README, CLAUDE and DEPENDENCIES, and no CHANGELOG or TODO
- docs: every doc CLAUDE.md and DEPENDENCIES.md point at exists
- docs: ARCHITECTURE carries the ten mandated sections and the over-cap census under the register
- docs: ARCHITECTURE carries the per-client feature table
- docs: every TOC file is in the module map and the hub
- docs: every bus message and slash verb is documented
- docs: settings-panel.md has a Row | Key line for every drawn schema row
- docs: the Documentation map registers every doc under docs/, each once, each on disk
- docs: every smoke check names its client
- docs: the smoke suite carries the in-game verification list and the probe steps

### test_eol.lua (2)

- eol: every tracked file carries the terminator .gitattributes declares for it
- eol: .gitattributes is line-endings-§5's canonical body for this repo kind

### test_prose.lua (15)

- prose: no authored file carries a British spelling from localization-§5's published list
- prose: the gate carries localization-§5's two lists whole, and nothing of its own
- prose self-test: the carve-out suppresses the named generated folder, and only it
- prose self-test: a path the carve-out does not name is not covered by one that looks like it
- prose self-test: a carve-out that is not a set of path strings is a failure, not a silence
- prose self-test: a TOC's file lines are read as paths, and its directives and comments are not
- prose self-test: a .pkgmeta's ignore block is read, and the keys around it are not
- prose self-test: an ignore entry covers a path exactly, by folder, and by wildcard
- prose self-test: the carve-out admits a generated dump and refuses a file the TOC loads
- prose self-test: a waiver-file exclusion meets the same two refusals as the carve-out
- prose self-test: each list is refused on the matching rule its own scan uses
- prose self-test: the scan and the refusals read the added exclusions through one reader
- prose self-test: a narrowing is refused by what it suppresses, not by how it is written
- prose self-test: the disclosure names what each entry suppressed, and says when it is bounded
- prose self-test: a malformed waived is a failure, not a silence

### test_layout_cap.lua (13)

- layoutcap: every authored file over the 1500-line cap is named in the census
- layoutcap: no census row outlives the breach it records
- layoutcap: every over-cap census row carries one of layout-§1's three terminal states
- layoutcap: the census and the exempt set agree about which paths were exempted
- layoutcap: an empty census is written as a result rather than left standing empty
- layoutcap self-test: the parser reads the census nested under the register, and stops there
- layoutcap self-test: a census outside its register, or at the wrong level, is not read
- layoutcap self-test: an over-cap file missing from the census is reported, and an exempt one is not
- layoutcap self-test: a census row that outlives its breach is reported
- layoutcap self-test: an over-cap row that names no terminal state is reported
- layoutcap self-test: the census and the exempt set are held to naming the same paths
- layoutcap self-test: a census that states nothing is told apart from one that states none
- layoutcap self-test: the exempt set takes folders as well as paths

### test_lizard_sighted.lua (8)

- lizard sighted: every hazard lizard loses a function over is neutralized
- lizard sighted: fields, strings, comments and look-alike names come through unchanged
- lizard sighted: a method definition is rewritten to its dot form with self
- lizard sighted: no line is added or removed, CRLF included
- lizard sighted: countFunctions counts the keyword, not strings, comments or longer names
- lizard sighted: listedCounts reads the per-file table, once per file
- lizard sighted: parity names every file whose counts differ, and only those
- lizard sighted: lizard lists every function of a hazard fixture once it is sanitized

### test_client_globals.lua (3)

- client globals: no call of a global a client lacks
- client globals: every allowlist row has a reason and a finding to excuse
- client globals: the check is falsifiable, a planted bare call is flagged for both clients

### test_diagnostics_contract.lua (9)

- diagnostics contract: both forms run the report
- diagnostics contract: the debug word is matched in any case
- diagnostics contract: both markers carry the brand and the end counts the report
- diagnostics contract: the report appends after what the console already holds
- diagnostics contract: the report lands with logging off and turns it on for the session
- diagnostics contract: an addon that opts out lands the report and leaves logging off (skipped: this addon keeps the default (Kit.diagnostics.enablesLogging is not false), so its report turns logging on; the case above holds it)
- diagnostics contract: with logging already on, the report writes no second enable line
- diagnostics contract: both forms run while the addon is disabled
- diagnostics contract: no other name runs the report

### test_skin_switch.lua (40)

- skin switch: the check is falsifiable, a surface that redraws a literal is reported
- skin switch: the HUD's window shell changes
- skin switch: the HUD's window shell changes with the Scope ignored
- skin switch: the HUD's footer changes
- skin switch: the HUD's footer changes with the Scope ignored
- skin switch: the HUD's test strip changes
- skin switch: the HUD's test strip changes with the Scope ignored
- skin switch: the live figures' text changes
- skin switch: the target line changes
- skin switch: the target line changes with the Scope ignored
- skin switch: the Results window's shell changes
- skin switch: the Results window's shell changes with the Scope ignored
- skin switch: the Results footer changes
- skin switch: the Results footer changes with the Scope ignored
- skin switch: the Results test strip changes
- skin switch: the Results test strip changes with the Scope ignored
- skin switch: the fight detail's name changes
- skin switch: the fight detail's name changes with the Scope ignored
- skin switch: the fight detail's Delete button changes
- skin switch: the fight detail's Delete button changes with the Scope ignored
- skin switch: the ability timeline's shell changes
- skin switch: the ability timeline's shell changes with the Scope ignored
- skin switch: the dim cover changes
- skin switch: the dim cover changes with the Scope ignored
- skin switch: the compare's shell changes
- skin switch: the compare's shell changes with the Scope ignored
- skin switch: the compare's spell header changes
- skin switch: the compare's spell header changes with the Scope ignored
- skin switch: the compare's usage heading changes
- skin switch: the compare's usage heading changes with the Scope ignored
- skin switch: the gear view's shell changes
- skin switch: the gear view's shell changes with the Scope ignored
- skin switch: the gear view's legend changes
- skin switch: a lane's background changes
- skin switch: a lane's label changes
- skin switch: a lane icon's border changes
- skin switch: an interrupted cast's mark changes
- skin switch: an interrupted cast's mark changes with the Scope ignored
- skin switch: a lane's edit overlay changes
- skin switch: a lane's edit overlay changes with the Scope ignored

### test_skin_values.lua (3)

- skin values: every host row carries its file, substring, why and cause id
- skin values: no typed value outside the kit's categories and the host's rows
- skin values: the check is falsifiable, a planted value of each shape is reported

## Totals

| Suite | Cases |
|-------|------:|
| test_load.lua | 13 |
| test_loadorder.lua | 4 |
| test_vendor_sync.lua | 3 |
| test_settings.lua | 19 |
| test_slash.lua | 19 |
| test_lane_casts.lua | 33 |
| test_lane_layout.lua | 13 |
| test_lane_render.lua | 38 |
| test_lane_anchor.lua | 33 |
| test_lane_visibility.lua | 30 |
| test_lanes_page.lua | 25 |
| test_probe.lua | 33 |
| test_meter.lua | 37 |
| test_format.lua | 19 |
| test_fight.lua | 30 |
| test_identity.lua | 47 |
| test_dummies.lua | 29 |
| test_cast_codec.lua | 7 |
| test_casts.lua | 17 |
| test_usage.lua | 11 |
| test_stats.lua | 9 |
| test_loadouts.lua | 22 |
| test_filters.lua | 12 |
| test_bests.lua | 10 |
| test_retention.lua | 13 |
| test_record.lua | 18 |
| test_slices.lua | 18 |
| test_hud_states.lua | 25 |
| test_hud_pace.lua | 5 |
| test_hud_chart.lua | 7 |
| test_hud_breakdown.lua | 11 |
| test_hud_appearance.lua | 8 |
| test_hud_page.lua | 14 |
| test_hud_layout.lua | 9 |
| test_hud_sizing.lua | 19 |
| test_sizing.lua | 7 |
| test_results_table.lua | 42 |
| test_results_detail.lua | 20 |
| test_results_sections.lua | 5 |
| test_share.lua | 6 |
| test_timeline.lua | 12 |
| test_timeline_marks.lua | 11 |
| test_compare.lua | 12 |
| test_gear.lua | 6 |
| test_usage_edit.lua | 4 |
| test_history_page.lua | 17 |
| test_preview.lua | 7 |
| test_sim.lua | 5 |
| test_bindings.lua | 11 |
| test_diagnostics.lua | 6 |
| test_skin_surfaces.lua | 5 |
| test_docs.lua | 15 |
| test_eol.lua | 2 |
| test_prose.lua | 15 |
| test_layout_cap.lua | 13 |
| test_lizard_sighted.lua | 8 |
| test_client_globals.lua | 3 |
| test_diagnostics_contract.lua | 8 |
| test_skin_switch.lua | 40 |
| test_skin_values.lua | 3 |
| Skipped | 1 |
| **Total** | **943** |
