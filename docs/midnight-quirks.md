# Midnight quirks — Ka0s Combat Trail

The client behaviors this addon works around (documentation-§3, Tier 2). The first part of this file is the collection's client-quirks catalog, vendored whole from the Ka0s WoW Addon Standard (client-quirks-§1) and replaced wholesale by `/dev-copilot:wow-revendor-standards`; never edit inside its markers. A correction belongs in this addon's own section, which follows it. Its WoW Forever findings are in `docs/forever-quirks.md` (forever-quirks-§1).

<!-- BEGIN VENDORED: quirks catalog v2.117.0 (source: WowAddonStandards) -->
> Part of the **[Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/STANDARDS.md)** — the split standard. This section is vendored whole into the `docs/midnight-quirks.md` of every addon that ships on Retail (§1), so its links are absolute. Cross-references use the `filename-§N` form (see the index's section map).

## Client quirks

The **Retail** catalog: the client behaviors the collection paid for more than once on Retail. Its WoW
Forever counterpart is forever-quirks, a separate catalog vendored into `docs/forever-quirks.md` (owner
ruling of 2026-11-10); an addon carries the catalog of each client its roster **Clients** value names (§1). Each entry here was discovered
**independently in two or more Ka0s repositories**, written up in each, and promoted by a harvest so the
next addon reads it instead of rediscovering it. A behavior one repo found stays in that repo's
`docs/midnight-quirks.md` until a second repo meets it.

*Why this section exists.* By 2026-11-06 eleven addons kept a private `docs/midnight-quirks.md`, 2,073
lines and about 133 entries between them, and about 81 of those entries were 21 behaviors written up
independently two to eight times. Nine of the eleven opened with their own restatement of the 12.0 secret
rules. Three write-ups contradicted this standard, and one contradiction was this standard's own error
(events-frames-taint-§2, *The combat-start edge*). A catalog was proposed and deferred twice, on
2026-08-25 and 2026-09-22, because an inventory rots; the build stamp per entry (§1) is the answer to that
objection (WowAddonStandards `harvests/2026-11-06/02_FINDINGS.md`, F3-01; every write-up quoted in
`harvests/2026-11-06/03_EVIDENCE.md`, Part A).

### 1. How an entry is written, and how it expires (MUST)

Every entry **MUST** carry:

- **The behavior**, stated as what the client does, not as advice.
- **Measured:** the client build or date it was observed on, where any write-up recorded one. An entry with
  no measurement says *not measured*; that is a weaker entry, not a missing field.
- **Cost:** what happened to an addon that did not know it.
- **Client:** the client it was measured on (clients-§1). Every entry here is a Retail entry, and an entry that names no client is Retail. A behavior measured on WoW Forever is written in forever-quirks, not here, and is not assumed to hold on Retail; forever-quirks-§2 states which of this catalog's entries have been measured on Forever.
- **Do:** the workaround, as a rule an addon can follow.
- **Source:** the deepest write-up — the repo and document that probed furthest — and the harvest that
  promoted it. Every version is quoted in that harvest's `03_EVIDENCE.md`.

**Expiry.** An entry describes a client, and clients move. When the retail interface number moves past the
newest *Measured* stamp in an entry and an addon observes otherwise, the entry is corrected in a standard
release — not worked around in the addon. An entry nobody can reproduce moves to §6 as an open probe rather
than being deleted, because the behavior may only have moved.

**What an addon does with this section (MUST): carry it as a vendored block.** This section and its
Forever counterpart, forever-quirks, are the parts of the standard an addon carries a **copy** of, because it is reference data about the game client
that a working addon needs offline, next to the code that works around it — not a rule, which is only ever
pointed at. Every addon whose roster **Clients** value includes Retail (`Retail · Forever`, `Retail` or
`Retail (port pending)`, clients-§2) carries `docs/midnight-quirks.md` (documentation-§3), and it is two parts: the vendored block,
opened by a `BEGIN VENDORED` HTML comment naming the catalog's version and source and closed by an
`END VENDORED` HTML comment, each spelled exactly as `/dev-copilot:wow-revendor-standards` writes it; then
the addon's own section. The markers are described here rather than shown, because this text travels
inside them: a literal marker in the vendored copy would give the file a second end marker for the next
re-vendor to cut at.

```markdown
[the BEGIN VENDORED comment, stamped quirks catalog v<X.Y.Z>]
… this section, whole …
[the END VENDORED comment]

## <Addon>-specific quirks

… the addon's own quirks: one no second repo has met, its per-event costs, its own probe tables …
```

- The block is **copied whole and replaced wholesale** by `/dev-copilot:wow-revendor-standards`, stamped with
  the standard version it came from, under the same discipline as `libs/LibKa0s/` (anti-pattern #45): never
  a subset, **never edited inside the markers**. A local edit inside them is reverted by the next revendor,
  and the behavior it fixed comes back with no cause in the addon's history; a correction belongs in the
  addon's own section, where the next harvest finds it.
- The addon's own section **MUST NOT** restate a behavior the block carries. When a harvest promotes an
  entry, the revendor prunes the addon's copy: the upstream entry is the deeper write-up, and two live
  copies of one finding is the shape that drifted three times into contradiction.
- An addon with no quirks of its own still carries the block, with an empty own section.
- **One file per client.** A `Forever` addon carries no `docs/midnight-quirks.md`: it carries
  forever-quirks in `docs/forever-quirks.md` instead, and a `docs/midnight-quirks.md` left in it is a
  retired name (documentation-§3). A `Retail · Forever` addon carries both files and files each finding of
  its own under the client it was measured on (forever-quirks-§1).

**Contested behaviors are not rules.** Where two repos recorded opposite behavior and nobody has probed
the difference, the entry goes in §6 with both sides and the probe that would settle it.

Behaviors this standard already states elsewhere are not repeated here: the unknown-event raise
(events-frames-taint-§1), `Settings.OpenToCategory`'s numeric ID and collapsed parent (options-ui-§2),
the protected category switch in combat (options-ui-§2, anti-pattern #88), a secret through `tostring` and
`..` (events-frames-taint-§8), lockdown at `PLAYER_REGEN_DISABLED` (events-frames-taint-§2), the spec
readers' move to `C_SpecializationInfo` (compat, `LibKa0s-Compat-1.0`) and `SendChatMessage`'s move to
`C_ChatInfo` (compat).

### 2. Secret values

**A secret boolean cannot be tested at all.** `if`, `not`, `==` and `and`/`or` on a secret boolean raise
("attempt to compare … (a secret boolean value)"); the value is unusable in Lua, not merely unprintable.
`DurationObject`'s `HasExpired`, `HasStarted`, `IsActive` and `IsZero` come back secret in combat, and an
engine button's `IsShown` has answered a secret boolean out of combat. *Measured:* 12.0.7 (probe table);
12.1 (`IsShown`). *Cost:* a raise on every refresh tick of the path that tests it. *Do:* check
`issecretvalue` before any test; route a secret boolean to a C-side consumer
(`C_CurveUtil.EvaluateColorValueFromBoolean`, `SetAlphaFromBoolean`), or treat it as the cautious answer
(a secret lockdown reads as locked, a secret restriction as active, a secret claim as no claim). Two repos
disagree on whether to gate before the C-side call; that disagreement is recorded in `LibKa0s`
`docs/api/Compat` and is not ruled here. *Source:* KickCD `docs/midnight-quirks.md`, "Secret booleans are
unusable"; seven repos (harvest 2026-11-06, Q6).

**A secret cannot be a table key.** Indexing or assigning with a secret key raises "attempted to perform
indexed assignment on a table that cannot be indexed with secret keys". `UnitGUID` on a follower-dungeon
pet (`party3pet`) answers a secret string. *Cost:* a raise on every refresh tick for a roster keyed by
GUID. *Do:* guard a key with `IsSafeKey` (`LibKa0s-Compat-1.0`) or `issecretvalue` before keying; a
secret GUID is never a handle. *Source:* MultiMeters `docs/midnight-quirks.md`, the follower-dungeon pet
GUID; seven repos (Q7).

**A secret never reaches SavedVariables, and one that does is written as `nil`.** A value captured as
secret stays secret after combat ends, and the client writes a secret to SavedVariables as `nil` — or,
where it was a key, loses the entry. *Measured:* a reload probe, 2026-10-25. *Cost:* silent data loss on
the next reload. *Do:* store a plain value or nothing; never store a captured secret to read later.
*Source:* Combat Trail `docs/known-limitations.md`, the reload probe its race mode carries; three repos (Q21).

**A frame handed a secret has secret geometry, and so does everything anchored to it.** After
`StatusBar:SetValue(secret)` (or `SetAlphaFromBoolean`, or anchoring to an aura engine container) the
frame `HasSecretValues`: its width, points and frame level read secret, out of combat too, and the
taint runs down the anchor chain to every frame anchored to it; a tooltip showing hidden information has
secret geometry. A secret size's `type` is `"number"`, so a type check lets it through, and
`BackdropTemplate`'s own arithmetic on a secret size raises. *Cost:* a raise inside Blizzard code, or a
layout computed from a secret. *Do:* compute layout from configuration and never read geometry back from a
frame that was handed a value; keep a record of the alpha you set rather than calling `GetAlpha()`; read a
frame level under a restricted anchor through a secret-safe guard (frame-layering). *Source:* AuraMaster
`docs/midnight-quirks.md`, the aura engine container entries (measured and dated); six repos and
`LibKa0s` `docs/api/Widgets` (Q8).

**A restricted spell's cooldown: branch on `isActive`, paint with the duration object.** In a restricted
state `C_Spell.GetSpellCooldown`'s timings are secret while `isEnabled` and `isActive` stay plain
(documented NeverSecret). `GetSpellCooldownDuration` answers a **zeroed** object, not `nil`, when there is
no cooldown, and a fresh object per call. *Cost:* raw `SetCooldown` with a secret start or duration raises;
a nil check passes the zeroed object. *Do:* decide from `isActive`; paint with
`Cooldown:SetCooldownFromDurationObject`, which accepts the object from tainted code. *Source:* KickCD
`docs/midnight-quirks.md`, the cooldown probe table; four repos (Q9).

**`notInterruptible` is secret, and the interruptibility events make it plain.** The cast info's
`notInterruptible` is secret; `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` deliver it plain.
`CastingBarFrameTemplate`'s built-in `OnUpdate` compares `GetTime()` with a secret `maxValue` and raises
when the bar shows another unit. *Do:* split the gate — the color path takes the secret C-side, the logic
path takes the event's plain value; do not inherit `CastingBarFrameTemplate` for a unit other than the
player. *Source:* KickCD `docs/midnight-quirks.md`, "split the gate in two"; two repos (Q13).

**`InChatMessagingLockdown` can answer a secret.** *Do:* read it through a guard and treat a secret as
locked. *Source:* DropWatcher and QuickComms `core/Compat.lua` (byte-identical), Combat Trail; three repos (Q27).

### 3. Events

**A valid event can register without complaint and never fire.** `GUILDBANKFRAME_OPENED` registers and
never fires (*Measured:* 12.0.7); `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts;
`UNIT_HEALTH` and `UNIT_NAME_UPDATE` never fire for compound tokens such as `party1target`;
`GET_ITEM_INFO_RECEIVED` does not fire for an item already cached. This is the inverse of the
unknown-event raise (events-frames-taint-§1) and it is silent: nothing errors. *Cost:* a feature that
never runs, with nothing in the log. *Do:* confirm a new event fires in game before building on it, and
prefer an edge with a second source (a frame's `OnShow`, a gated timer) where the event is known to be
silent. *Source:* BankLedger `docs/midnight-quirks.md`, `GUILDBANKFRAME_OPENED`; four repos (Q20).

**Client state can lag its own event, or change with no event at all.** `IsMounted()` has flipped by the
time `PLAYER_MOUNT_DISPLAY_CHANGED` arrives while `C_PlayerInfo.GetGlidingInfo`'s `canGlide` sometimes has
not; after `INSPECT_READY` some slots still answer an item id with no link; switching bank tabs fires no
event, and the live warband tab has taken over a second to catch up; chat lockdown clears with no event.
*Cost:* a read at the edge answers the old state, and the display stays wrong until the next unrelated
event. *Do:* answer at the edge **and once more after a short settle** (a fraction of a second, a bounded
retry), never a poll. *Source:* MultiMeters `docs/midnight-quirks.md`, "some client state lags its own
event"; six repos (Q19).

**An empowered cast fires `UNIT_SPELLCAST_EMPOWER_*`, not the channel events.** `UnitChannelInfo`
reports it, but `UNIT_SPELLCAST_CHANNEL_START` / `_STOP` do not fire for it, and its release fires
`UNIT_SPELLCAST_SUCCEEDED` with the same cast GUID. *Do:* register the `EMPOWER_*` events wherever channels
are tracked. *Source:* KickCD `docs/midnight-quirks.md`, empowered casts; three repos (Q12).

**`ADDON_RESTRICTION_STATE_CHANGED` fires *before* enforcement.** The `Activating` state arrives before the
restriction begins, and access is still permitted during that dispatch; a dungeon restriction type has
gone active on entry and not cleared. Read the restriction type by its `Enum.AddOnRestrictionType` member
name — a member can be missing on some builds. *Measured:* 12.1.0, 2026-09-18. *Do:* treat `Activating`
as the last moment to read, not as the start of the restriction. The payload's second argument is
contested (§6). *Source:* AuraMaster `docs/midnight-quirks.md`, the restriction types; six repos (Q10).

### 4. Combat and secure frames

**Blizzard's aura buttons are forbidden to addon code, and `IsForbidden()` can say otherwise.** In
combat every call on a Blizzard aura button's objects raises "Attempt to access forbidden object from code
tainted by an AddOn"; in an instance (seen in Mythic+) the same buttons answer `IsForbidden()` `false` and
still refuse every read, `GetChildren` included. *Do:* never read Blizzard aura buttons; where a frame
must be inspected, `pcall` the read and treat a failure as forbidden. *Source:* PartyFrameEnhanced
`docs/midnight-quirks.md`, forbidden aura buttons; three repos (Q14).

**Escape runs a protected `Hide()` in combat.** A secure or protected frame listed in `UISpecialFrames` is
hidden by `CloseSpecialWindows`, which is a protected action in combat. *Do:* list a non-secure proxy in
`UISpecialFrames` and hide the protected frame from it out of combat, or keep protected frames out of the
list. *Source:* WhatGroup `docs/midnight-quirks.md`, the escape proxy; two repos (Q24).

### 5. Item, tooltip, enum and realm data

**Item data is nil until cached, and the load event has holes.** `GetItemInfo` answers nothing for an
uncached item; `GET_ITEM_INFO_RECEIVED` does not fire on an addon's first scan for an item the client
already holds; an uncached item's tooltip is not empty but a legible `RETRIEVING_ITEM_INFO` line; a failed
load drops its wait and nothing asks again. *Cost:* a blank or wrong row that never repairs. *Do:* load
through `LibKa0s-Item-1.0`'s cache-then-callback path (library-stack-§7), treat `RETRIEVING_ITEM_INFO` as
not-yet-loaded, and re-ask after a failed load. *Source:* ConsumableMaster `docs/midnight-quirks.md`, the
first-scan hole; seven repos (Q15).

**`C_TooltipInfo` returns raw templates.** Tooltip lines can carry the unexpanded plural grammar
`|4singular:plural;` (*Measured:* 12.1.5, "for the next 3 |4hour:hrs; 49 min") and a no-break space that
Lua's `%s` does not match. *Cost:* a parser that knew only the expanded words read no duration and called a
tradeable drop expired. *Do:* expand `|4…;` before matching, and match the no-break space explicitly.
*Source:* DropWatcher `docs/midnight-quirks.md`, the trade window; two repos (Q16).

**Tooltip line text can be secret** under an addon restriction, including through `TooltipDataProcessor`.
*Do:* guard each line before matching. *Source:* DropWatcher `docs/midnight-quirks.md`; two repos (Q17).

**Blizzard renumbers enums; resolve a member by name, never by number.** One build's
`Enum.TooltipDataLineType` and bank-tab values are not the next build's, and a member can be absent on a
build. *Cost:* a numeric guess for a member the build does not expose landed on an unrelated bank
container. *Do:* read `Enum.X.Member`, and handle its absence; localization-§4 already forbids the string
spelling. *Source:* DropWatcher `docs/midnight-quirks.md`, the research's enum values; five repos (Q18).

**`GetNormalizedRealmName` is nil early in login.** *Cost:* a stored `Name-` key with no realm. *Do:* never
build a `Name-Realm` key before the realm is known; defer, or fall back to `GetRealmName` with its spaces
and hyphens removed. *Source:* DropWatcher `docs/midnight-quirks.md`, realm names; four repos (Q25).

**On Forever a character's name is two words, and its realm is a long label.** Moved to forever-quirks-§4
in v2.117.0, with the Forever catalog; it was here from v2.103.0 to v2.116.0.

**A template-less `FontString` with no font raises on `SetText`.** "Font not set" from a `FontString`
created without a template or `SetFontObject` takes the addon down at load; a mock that does not enforce it
passes every test. *Do:* give every bare `FontString` a font object before its first `SetText`; the kit's
mock enforces it. *Source:* MultiMeters `tests/mock_frame.lua`, the font-not-set guard; three repos and
`LibKa0s` (Q22).

### 6. Open probes — contested behaviors (not rules)

Each needs an in-game probe, recorded with the build, before any section of this standard changes.

- **WoW Forever behaviors.** Moved to forever-quirks in v2.117.0: its §5 holds the Forever open probes,
  the missing-API surface (LibKa0s#44) among them.
- **`string.format` on a secret.** events-frames-taint-§8 says it raises, with three repos; two say it
  works, one with a mid-combat observation. The likely difference is the specifier (`%s` against `%d` and
  `%.1f`) or that the result is itself a secret string. Probe each specifier, in combat, on a damage-meter
  value and a `UnitHealth` value. Until then §8's rule stands.
- **`ADDON_RESTRICTION_STATE_CHANGED`'s second argument.** One repo documents an
  `Enum.AddOnRestrictionState` value; three (one measured) record a boolean as well. Handle both shapes.
  The 2026-09-22 harvest called this settled, and it is not.
- **`SetAllPoints(parent)` on a secure button at load.** One repo records "Cannot anchor protected frames
  to regions" and uses the implicit-parent form; another anchors its secure rows with `SetAllPoints(row)`
  at birth and treats it as working, with its in-game smoke check still owed.
<!-- END VENDORED -->

## CombatTrail-specific quirks

Each entry follows client-quirks-§1's shape. The WoW Forever findings, most of them from `/ct probe`
(its steps are in `smoke-tests.md`, *The probe*), are in `docs/forever-quirks.md`.

**On Retail the live figures lose their decimals: "24M" and a whole "363477".** *Client:* Retail.
*Measured:* the owner's screenshot, 2026-11-13: mid-fight the HUD's live Damage read `24M` (the plain
`AbbreviateNumbers` table, which drops the decimals from 10M up) and its live DPS `363477`
(`FloorToNearestString`), so neither client formatter served a secret there either. After combat
the same fight read `24.39M` and `364.0K` (plain values, abbreviated in Lua). Retail has
`CreateAbbreviateConfig` (the kit's live global list); the assumption, not yet confirmed in game, is
that Retail's `AbbreviateNumbers` takes the config it builds as a second argument. *Do:* `modules/Format.lua` builds a config from the ladder once,
trusts it only if `AbbreviateNumbers(value, config)` renders the plain checks exactly (2763000 as
"2.76M", 30190.4761904 as "30.1K", 69.5625 as "69"), and then sends secret totals and secret rates to it
ahead of the plain `AbbreviateNumbers` and `FloorToNearestString`. A client that ignores the config
fails the first check and keeps today's path. Whether it serves in combat is *not measured*: `/ct debug`
names the path, and `/ct probe`'s formatter trial has a line for it. *Source:* this repo,
`modules/Format.lua`.

**The client number formatter may draw a fractional value raw.** *Client:* Retail (both clients
unmeasured directly). *Measured:* not measured by probe; inferred from the owner's report,
2026-11-10. The live DPS tile drew `77.142857...` and `30.1904761...`, which are 540/7 and 634/21:
a raw per-second rate with its "K" lost to the tile's ellipsis. The C_StringUtil formatter's ladder
truncates through the integer significand, so an integer check value (2763000 -> "2.76M") passes
while a fractional input can come back unfloored. *Cost:* a DPS figure with a long tail of
decimals. *Do:* `modules/Format.lua` checks each constructor
(`Compat.NumberFormatterCandidates`) against a fractional value too (30190.4761904 -> "30.1K") and
uses the first that passes. On WoW Forever (build 70888, the owner's log, 2026-11-11) both
constructors logged "built no formatter" and the live DPS drew `39.7142...` through
`AbbreviateNumbers`: the check then required the instance to be a Lua table, while a client object
may be a userdata (AuraMaster tests only that one came back), so the lookup is now a pcall'd
`SetBreakpoints`; and `CreateNumericRuleFormatter` takes AuraMaster's measured
`{ threshold, format }` rules, not the ladder, so when it refuses the ladder it is tried with one
whole-number rule (`"%d"`: "39", "30190"), checked like the others. Whether either now passes on
Forever is *not measured*: `/ct debug` names the path. A plain number never reaches the client
formatter; Lua abbreviates and truncates it. A secret with no trusted formatter goes to `AbbreviateNumbers` in pcall, and the raw
secret is the last resort. An answer to a secret may itself be a secret string, so its presence
is asked of `Secrets.IsPresent`, never compared to nil. `/ct debug` writes which path served the numbers. Settle it with the
out-of-combat probe in recon R:hud-sizing#4 on both clients (each constructor's `FormatNumber(30190.4761904)`
and `AbbreviateNumbers(30190.4761904)`). *Source:* this repo, `modules/Format.lua` header; plan v0.2
Task A5.

**An off-GCD instant closes the cast in flight while castGUIDs are secret.** *Client:* Retail.
*Measured:* not measured in game; follows from the GUID being unreadable in combat. *Cost:* a cast
interrupted after an instant went off between its START and its end is not marked. *Do:* never key
or compare a secret GUID; accept the lost mark (modules/LaneCasts.lua header).

**The Race window's live damage is secret in combat, so it is held in memory, anchored to nothing, and its bars stand on plain frames.**
*Client:* Retail (Race mode is Retail only). *Measured:* not measured in game; follows from the two
secret-value rules above (a stored secret comes back `nil`; a frame handed one has secret geometry).
*Cost:* a checkpoint reading written to SavedVariables would come back empty after a `/reload`, and a
figure placed off a label holding a secret would inherit its secret geometry. *Do:* the player's damage
beside Best by now and in each Checkpoint is the DPS HUD's last read (`Hud.LiveDamage`), set as a
label's text through `NS.Format.Number` and as the value of a mini pace bar (`StatusBar:SetValue`, the
range plain: `NS.HudBest.Bounds` around the best's figure there), and never compared or computed on; each Checkpoint's reading
is kept in `modules/RaceWindow.lua`'s memory for that race alone and never saved, so a checkpoint
passed unseen before a `/reload` resume shows a dash; Best by now's *Current* figure stands a fixed
`NS.RaceWindowBest.LABEL_W` (44px) after its label, its two anchors both on the card's edges so it
stays inside its half (`Best.Figure`), never anchored to the best's figure, and the checkpoint cell's
lines each anchor to the cell; and a bar handed the figure has secret geometry, so nothing is anchored
to one: Best by now's bar stands on the body's content frame and each checkpoint's on its cell.
*Source:* this repo, `modules/RaceWindow_Board.lua` and `modules/RaceWindow.lua` headers (race window
redesign plan W13, and the mini pace bars of 2026-11-13).

**`UNIT_COMBAT`'s amounts and `UNIT_AURA`'s aura data in combat are assumed sealed, not yet probed.**
*Client:* Retail (12.1.5). *Measured:* not measured; assumed, until the owner probes it (CombatTrail
#11, plan item CL-11a, 2026-11-25). The Combat Log registers `UNIT_COMBAT` for `player` and
`UNIT_AURA` for `player` and `target` through `NS.SafeRegisterUnitEvent`, only while a fight is open.
The assumption is that both are delivered, and that in combat a hit's amount, and an aura's spell ID or
instance, may arrive secret. *Cost:* a sealed aura is no line, so a fully sealed fight logs no aura.
A sealed amount is saved as `"s"`, and the in-memory ring keeps the client's value for a FontString
alone. A refused `UNIT_COMBAT` costs only the hits and heals. *Do:* never compare, count or store a
sealed amount as a number, and never guess a sealed aura's name or ID. After a fight, `/ct diagnostics`
lists any refused event under *rejected events*, and the smoke rows for #11 (SM-CT-LG3 first, docs/smoke-tests.md) record what the log showed; until then this entry stays assumed.
*Source:* this repo, `modules/CombatLog.lua`.
