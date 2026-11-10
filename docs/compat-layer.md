# Compat layer — Ka0s Combat Trail

The addon-specific shims on `NS.Compat` (documentation-§3, Tier 2: `core/Compat.lua` publishes three
or more beyond what LibKa0s supplies; the count is
`cat core/Compat*.lua | grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.'`).

`core/Compat.lua` is the family's root and only file. No other file names a version-variant client
API: a module calls `NS.Compat.Name(...)`. The members LibKa0s-Compat-1.0 supplies (the client
checks `IsRetail`, `IsForever`, `ClientKey`, `ForClient`; the secret guards `IsSecret`, `CanAccess`,
`IsSafeKey`; the spec readers; `UnitCharacterName` and `RealmKey`) are bound here with a stub arm for
a library-absent load and are documented by the library, not here.

## The addon's own shims

| Shim | Answers | Client notes |
|---|---|---|
| `CanAccessTable(t)` | Whether a table may be read (`canaccesstable`, else readable) | No LibKa0s major carries it |
| `SpellTexture(id)` | A spell's icon, the id passed through untested | `C_Spell.GetSpellTexture`, else `GetSpellTexture`; may answer secret in combat |
| `SpellName(id)` | A spell's name | `C_Spell.GetSpellName`, else `GetSpellInfo` |
| `SpellBaseCooldown(id)` | A spell's base cooldown in ms (the lanes' glow) | May answer secret in combat; read through `NS.Secrets` |
| `SpellHaste()` | The player's spell haste (the haste-adjusted ticks) | Read only out of combat |
| `InPetBattle()` | Whether a pet battle is on | False where the client has none |
| `InVehicle()` | Whether the player rides a vehicle | |
| `InDelve()` | Whether a delve is in progress | Retail only: always false on WoW Forever |
| `KeystoneLevel()` | The active Mythic+ keystone level | Retail only: always nil on WoW Forever |
| `DelveTierText()` | The delve tier, from the scenario tracker's widgets | Retail only; not verified in game (smoke list) |
| `PvpRules()` | `{ ratedBG, ratedArena, soloShuffle, blitz }` for the board key's PvP bracket | Arena brackets false on WoW Forever |
| `BuildInfo()` | Version, build, interface (the probe, the record) | |
| `ClientApis()` | Which version-variant APIs exist (the probe) | |
| `ChatSender()` | The function that sends one chat message (Share) | `C_ChatInfo.SendChatMessage`, else `SendChatMessage` |
| `ChatLocked()` | Whether chat sends are refused now (encounters, rated PvP) | False where the client has no lockdown |
| `NewNumberFormatter()` | The client's secret-safe number abbreviator (modules/Format.lua) | Nil where the client has none; Format falls back |
| `PopupEditBox(dialog)` | A StaticPopup's edit box (the note popup) | The field name differs between clients |

## Rules

- A client check is always `NS.Compat.IsRetail()`, `IsForever()`, `ClientKey()` or
  `ForClient(list)` (clients-§3), never a project-id comparison in a module.
- A Retail-only shim answers its "absent" value on WoW Forever (false or nil), so a caller needs no
  client check of its own.
- A shim that can meet a secret never tests it; the caller reads the answer through `NS.Secrets`.
