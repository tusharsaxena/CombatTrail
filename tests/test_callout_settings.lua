-- tests/test_callout_settings.lua — the race call-out's settings on the host's write route (callout
-- plan rows C5, C11 and C12; LibKa0s-Callout-1.0 at 3.4, re-pinned at 4.5 with LibKa0s v1.102.0):
-- the instance's SchemaRows("callout.", { texts = false }) registered as Race mode page rows, each
-- declared retail, skipRender and grouped under the one tab's key; no stock-text or mute row (the
-- words are the addon's); the AceDB defaults seeded from the rows (Arena John the default voice);
-- `callout.point` in the schema's writeThrough; every instance write (a setting, a color, the
-- drag's point, Reset position) through NS.SetByPath; `/ct get|set|reset` and the page's Defaults
-- reaching the rows, the glow's among them; the library's settings section drawn as the page's one
-- Callout tab (Preview, then the Look and Sound side tabs); the 2 -> 3 migration (the retired glow
-- choice, the dropped texts and mutes, a stored voice kept); and all of it absent on WoW Forever
-- (clients-§4, §6).

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse, assertNil =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local function forever() return T.NS.Compat.IsForever() end


local function text(M) return table.concat(M.__printed(), "\n") end

--- The call-out's registered rows, by path.
local function calloutRows(NS)
    local out, n = {}, 0
    for _, row in ipairs(NS.Schema) do
        if type(row.path) == "string" and row.path:find("^callout%.") then
            out[row.path], n = row, n + 1
        end
    end
    return out, n
end

--- Record every path NS.SetByPath is handed, then call the real seam.
local function recordWrites(NS)
    local real, writes = NS.SetByPath, {}
    NS.SetByPath = function(path, ...)
        writes[#writes + 1] = path
        return real(path, ...)
    end
    return writes
end

-- ── per client ──────────────────────────────────────────────────────────────────────────────────

test("callout settings: every SchemaRows row is a Race mode row, declared retail, drawn by the section", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    local Callout = inst.mocks.LibStub("LibKa0s-Callout-1.0")
    local want, named = NS.Callout:SchemaRows("callout.", { texts = false })
    local got, n = calloutRows(NS)
    assertEqual(n, #want, "one registered row per SchemaRows row")
    -- 25 scalars: the glow's eight among them, and from LibKa0s v1.108.0 (Callout minor 5) the shadow's
    -- and the numbers' skin companions, fontShadowFromSkin and numberColorFromSkin.
    assertEqual(#want, 25 + #Callout.KINDS + 2, "the scalars (the glow's eight among them), colors and the two session rows")
    for _, w in ipairs(want) do
        local row = got[w.path]
        assertTrue(row ~= nil, w.path .. " is registered")
        assertTrue(NS.FindSchemaRow(w.path) == row, w.path .. " is found by path")
        assertEqual(row.page, "race", w.path)
        assertEqual(table.concat(row.clients or {}, ","), "retail", w.path .. " is declared retail")
        assertTrue(row.skipRender, w.path .. ": the library's section draws it")
        assertEqual(row.group, "callout", w.path .. ": its group is the one tab's key")
    end
    for path in pairs(got) do
        assertFalse(path:find("^callout%.texts%.") ~= nil, path .. ": no stock-text row")
        assertFalse(path:find("^callout%.muted%.") ~= nil, path .. ": no mute row")
    end
    for _, key in ipairs({ "glow", "glowIntensity", "glowThickness", "glowX", "glowY", "glowCustom", "glowColor",
        "useClassColorGlow", "glowColorFromSkin", "fontShadowFromSkin", "numberColorFromSkin" }) do
        assertTrue(got["callout." .. key] ~= nil, "callout." .. key .. " is a row")
    end
    assertEqual(got["callout.glow"].type, "bool", "the glow is a toggle, as AuraMaster's")
    assertEqual(named[1], "callout.point", "the drag's place is the named state")
    assertEqual(named[1], NS.CALLOUT_POINT)
    local listed = false
    for _, p in ipairs(NS.SCHEMA_WRITE_THROUGH) do if p == named[1] then listed = true end end
    assertTrue(listed, "callout.point is the schema's writeThrough")
    assertNil(got["callout.point"], "and has no row: no control chooses it")
end)

test("callout settings: absent on WoW Forever, no row, default or writeThrough path", function()
    if not forever() then return end
    local NS = T.load().NS
    local _, n = calloutRows(NS)
    assertEqual(n, 0, "no call-out row on WoW Forever")
    assertNil(NS.defaults.profile.callout, "no call-out default")
    for _, p in ipairs(NS.SCHEMA_WRITE_THROUGH) do
        assertFalse(p == "callout.point", "callout.point is not written through on WoW Forever")
    end
    assertFalse(NS.SetByPath("callout.point", { "CENTER", "CENTER", 0, 0 }), "nothing stores it")
end)

-- ── the defaults ────────────────────────────────────────────────────────────────────────────────

test("callout settings: the defaults are seeded from the rows, and the schema validates against them", function()
    if forever() then return end
    local NS = T.load().NS
    local SchemaLib = NS.__schemaLib
    local D = NS.defaults.profile
    assertTrue(type(D.callout) == "table", "profile.callout is seeded")
    for path, row in pairs((calloutRows(NS))) do
        if row.sessionOnly then
            assertNil(SchemaLib.Read(D, path), path .. ": a session row stores nothing")
        else
            assertTrue(SchemaLib.SameValue(SchemaLib.Read(D, path), row.default), path .. " is seeded with its row's default")
            assertTrue(SchemaLib.SameValue(NS.GetSetting(path), row.default), path .. " reads its default")
        end
    end
    assertEqual(table.concat(D.callout.point, ","), "CENTER,CENTER,0,180", "the default place")
    -- GO's default is Ka0s Default's sem.good (LibKa0s v1.108.0, U-2: a meaning kind draws its token
    -- until a color is picked), in the panel's named shape.
    assertEqual(D.callout.colors.go.r, 0.35, "a color in the panel's named shape")
    assertNil(D.callout.texts, "no stock-text defaults")
    assertNil(D.callout.muted, "no mute defaults")
    assertEqual(D.callout.voice, "male-arena-john", "Arena John, the default voice for a new profile")
    assertEqual(D.callout.glow, true, "the glow on")
    assertEqual(D.callout.glowIntensity, 1, "at full intensity (Callout minor 4, LibKa0s v1.102.0)")
    assertEqual(D.callout.glowThickness, 1, "1 px thick")
    assertEqual(D.callout.glowX .. "," .. D.callout.glowY, "1,-1", "1 px right and 1 px down")
    assertEqual(D.callout.glowCustom, true, "Glow color ticked")
    assertEqual(D.callout.glowColor.r .. "," .. D.callout.glowColor.g .. "," .. D.callout.glowColor.b, "0,0,0", "a black swatch")
    -- The look follows the skin (LibKa0s v1.108.0, the owner's U-1 of 2026-11-20): the Skin font, the
    -- skin's outline, its glow color, its shadow and its HUD text color for the numbers.
    assertEqual(D.callout.font, "Skin font", "the skin's face")
    assertEqual(D.callout.outline, "@skin", "the skin's outline")
    assertEqual(D.callout.glowColorFromSkin, true, "the skin's glow color")
    assertEqual(D.callout.fontShadowFromSkin, true, "the skin's shadow")
    assertEqual(D.callout.numberColorFromSkin, true, "the skin's HUD text color for the numbers")
    assertEqual(D.callout.shadowX .. "," .. D.callout.shadowY, "1,1", "the shadow 1 px right and 1 px up")
    assertEqual(NS.Callout:Get("voice"), "male-arena-john", "a fresh profile speaks with Arena John")
    local errors, _, missing = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(missing, 0)
    assertEqual(NS.Callout:Get("size"), 96, "the instance reads the seeded profile")
end)

-- ── the write route ─────────────────────────────────────────────────────────────────────────────

test("callout settings: every instance write goes through NS.SetByPath, under callout.", function()
    if forever() then return end
    local NS = T.load().NS
    local writes = recordWrites(NS)
    local co = NS.Callout
    assertTrue(co:Set("size", 120))
    assertEqual(writes[#writes], "callout.size")
    assertEqual(NS.db.profile.callout.size, 120, "stored by the seam")
    assertFalse(co:Set("texts.GO", "Now!"), "no own-text row: the seam refuses it")
    assertNil(NS.db.profile.callout.texts, "and nothing is stored")
    assertTrue(co:Set("glowIntensity", 0.7))
    assertEqual(writes[#writes], "callout.glowIntensity")
    assertTrue(co:SetColor("stop", 0.5, 0.25, 1))
    assertEqual(writes[#writes], "callout.colors.stop")
    local c = NS.db.profile.callout.colors.stop
    assertEqual(table.concat({ NS.ColorDecode(c) }, ","), "0.5,0.25,1,1", "in the panel's codec")
    assertFalse(co:Set("size", 999), "a size the row refuses")
    assertEqual(NS.db.profile.callout.size, 120, "and nothing stored")
end)

test("callout settings: a drag's point and Reset position are written through NS.SetByPath", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local writes = recordWrites(NS)
    local co = NS.Callout
    co:SetLocked(false)
    local f = assert(co:Frame())
    f:__fire("OnDragStart")
    -- Where the client answers the frame stands once the player has moved it.
    rawset(f, "GetPoint", function() return "TOPLEFT", M.UIParent, "TOPLEFT", 40, -60 end)
    f:__fire("OnDragStop")
    assertEqual(writes[#writes], "callout.point", "the drag wrote through the seam")
    assertEqual(NS.db.profile.callout.point[1], "TOPLEFT")
    assertEqual(NS.db.profile.callout.point[4], -60)
    co:SetLocked(true)
    co:ResetPosition()
    assertEqual(writes[#writes], "callout.point")
    assertEqual(table.concat(NS.db.profile.callout.point, ","), "CENTER,CENTER,0,180", "back on the default place")
end)

-- ── the slash command and the resets ────────────────────────────────────────────────────────────

test("callout settings: /ct set, get and reset reach a call-out row", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("set callout.size 150")
    assertEqual(NS.db.profile.callout.size, 150, "set: " .. text(M))
    assertEqual(NS.Callout:Get("size"), 150, "the call-out reads it")
    NS.Slash:OnSlash("set callout.voice male")
    assertEqual(NS.Callout:Get("voice"), "male", "a list row")
    M.__resetPrinted()
    NS.Slash:OnSlash("set callout.muted.STOP true")
    assertFalse(NS.Callout:Get("muted.STOP"), "no mute row: refused, " .. text(M))
    NS.Slash:OnSlash("set callout.texts.READY Now")
    assertNil(NS.db.profile.callout.texts, "no own-text row: nothing stored")
    M.__resetPrinted()
    NS.Slash:OnSlash("get callout.texts.READY")
    assertTrue(text(M):find("not found", 1, true) ~= nil, "get refuses a stock text: " .. text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("get callout.size")
    assertTrue(text(M):find("150", 1, true) ~= nil, "get: " .. text(M))
    NS.Slash:OnSlash("reset callout.size")
    assertEqual(NS.GetSetting("callout.size"), 96, "reset: back to the row's default")
    M.__resetPrinted()
    NS.Slash:OnSlash("set callout.voice nobody")
    assertEqual(NS.GetSetting("callout.voice"), "male", "a voice that is none stores nothing: " .. text(M))
    M.__resetPrinted()
    NS.Slash:OnSlash("list")
    assertTrue(text(M):find("callout.glowThickness", 1, true) ~= nil, "list names the call-out's rows")
    assertFalse(text(M):find("callout.texts.", 1, true) ~= nil, "and no stock text")
end)

test("callout settings: the glow's rows are reached by /ct set, get and reset", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("set callout.glow false")
    assertEqual(NS.db.profile.callout.glow, false, "set: " .. text(M))
    assertFalse(NS.Callout:Get("glow"), "the call-out reads it")
    NS.Slash:OnSlash("set callout.glowThickness 5")
    assertEqual(NS.Callout:Get("glowThickness"), 5)
    NS.Slash:OnSlash("set callout.glowX -4")
    assertEqual(NS.Callout:Get("glowX"), -4)
    NS.Slash:OnSlash("set callout.useClassColorGlow true")
    assertTrue(NS.Callout:Get("useClassColorGlow"))
    NS.Slash:OnSlash("set callout.glowThickness 9")
    assertEqual(NS.GetSetting("callout.glowThickness"), 6, "a thickness past 6 is held to the row's 6")
    NS.Slash:OnSlash("set callout.glowThickness 5")
    M.__resetPrinted()
    NS.Slash:OnSlash("get callout.glowThickness")
    assertTrue(text(M):find("5", 1, true) ~= nil, "get: " .. text(M))
    NS.Slash:OnSlash("reset callout.glow")
    NS.Slash:OnSlash("reset callout.glowThickness")
    assertTrue(NS.Callout:Get("glow"), "reset: the glow back on")
    assertEqual(NS.Callout:Get("glowThickness"), 1, "and its thickness back to 1")
end)

test("callout settings: the Race mode page's Defaults and a profile reset put the call-out back", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    assertTrue(NS.SetByPath("callout.size", 140))
    assertTrue(NS.SetByPath("callout.colors.go", { r = 0, g = 0, b = 1, a = 1 }))
    assertTrue(NS.SetByPath("callout.glow", false))
    assertTrue(NS.SetByPath("callout.voice", "female"))
    inst.mocks.__subcategories["Race mode"]:__fire("OnShow")
    NS.Helpers.RestoreDefaults("race", NS.pageCtx.race)
    assertEqual(NS.GetSetting("callout.size"), 96)
    assertEqual(NS.GetSetting("callout.colors.go").r, 0.35)
    assertTrue(NS.GetSetting("callout.glow"), "the glow back on")
    assertEqual(NS.GetSetting("callout.voice"), "male-arena-john", "and Arena John")
    assertTrue(NS.SetByPath("callout.size", 140))
    NS.db:ResetProfile()
    assertEqual(NS.Callout:Get("size"), 96, "a profile reset restores the seeded default")
end)

-- ── the section ─────────────────────────────────────────────────────────────────────────────────

test("callout settings: the Race mode page draws one Callout tab after Race", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    M.__resetPrinted()
    M.__subcategories["Race mode"]:__fire("OnShow")
    assertEqual(#M.__printed(), 0, "the render printed: " .. text(M))
    local tab = NS.Callout:SettingsTab({ options = NS.Helpers, prefix = "callout." })
    assertEqual(tab.key, "callout")
    assertEqual(tab.label, "Callout", "the library's own word")
    local ctx = NS.pageCtx.race
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "race", nil, nil, { tabs = { tab } })
    assertEqual(table.concat(keys or {}, ","), "Race,callout,Late-cast ignore list,Race window")
    for _, word in ipairs({ "Call-out look", "Call-out sound", "Call-out texts" }) do
        assertNil(rawget(NS.L, word), word .. ": the three tab words are gone from the locale")
    end
end)

test("callout settings: the one tab is the library's side layout on the host's route: Preview, Look and Sound", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local co, views = NS.Callout, {}
    local real = co.BuildSettings
    co.BuildSettings = function(self, parent, opts)
        local view = real(self, parent, opts)
        views[#views + 1] = { view = view, opts = opts }
        return view
    end
    M.__subcategories["Race mode"]:__fire("OnShow")
    assertTrue(NS.pageCtx.race ~= nil, "the page is built")
    assertTrue(NS.Helpers.SelectTab("race", "callout"), "the Callout tab is selected")
    M.__subcategories["Race mode"]:__fire("OnShow")   -- a hidden page repaints on its next show
    local last = views[#views]
    assertTrue(last ~= nil, "the section built")
    assertEqual(last.opts.layout, "side", "the one tab's layout")
    assertNil(last.opts.tab, "not one of the three tabs")
    assertTrue(last.opts.options == NS.Helpers, "with the addon's Options instance")
    assertEqual(last.view.kind, "options")
    assertEqual(last.view.layout, "side")
    assertEqual(last.view.prefix, "callout.", "on the host's route")
    -- LibKa0s v1.102.0 (CalloutSettings minor 5): the one tab draws no sample line, so the side
    -- layout has no preview to repaint; the Preview block's controls stay.
    assertNil(last.view.preview, "no sample line in the one tab")
    assertNil(last.view.repaint, "and nothing to repaint")
    assertEqual(last.view.side, "look", "Look is the first side tab")
    local buttons = last.view.sideTabs
    assertEqual(#buttons, 2, "two side tabs")
    assertEqual(buttons[1].__ka0sNavText .. "," .. buttons[2].__ka0sNavText, "Look,Sound")
    local seen = {}
    for _, r in ipairs(last.view.rows) do
        assertTrue(NS.FindSchemaRow(r.path) ~= nil, tostring(r.path) .. " is a registered row")
        seen[r.key] = true
    end
    assertTrue(seen.glow and seen.glowThickness and seen["colors.go"], "Look holds the glow rows and the colors")
    assertNil(seen.voice, "Sound's rows are not drawn under Look")
    -- A path the section draws is written by the Options descriptor's set, which is the seam.
    local writes = recordWrites(NS)
    assertTrue(NS.SetByPath("callout.hold", 3))
    assertEqual(writes[#writes], "callout.hold")
    assertEqual(co:Get("hold"), 3)
end)

-- ── the 2 -> 3 migration (callout plan row C11) ──────────────────────────────────────────────────

-- An instance that logs in over `seeded` SavedVariables (tests/test_load.lua's boot).
local function boot(seeded)
    local inst = T.load{ init = false }
    _G.CombatTrailDB = seeded
    local AceAddon = inst.mocks.LibStub("AceAddon-3.0")
    AceAddon:InitializeAddon(inst.NS)
    AceAddon:EnableAddon(inst.NS)
    return inst.NS
end

test("callout settings: the migration rewrites a stored glow choice, drops the texts and mutes, keeps a voice", function()
    if forever() then return end
    local NS = boot({
        global = { schemaVersion = 2 },
        profileKeys = { ["Hunter - Realm"] = "Default" },
        profiles = {
            Default = { callout = { glow = "strong", voice = "female", texts = { FAILED = "TOO SOON" },
                muted = { STOP = true } } },
            Soft = { callout = { glow = "soft", glowThickness = 4 } },
            Off = { callout = { glow = "off" } },
            Plain = { race = { enabled = true } },
        },
    })
    local sv = _G.CombatTrailDB
    assertEqual(NS.db.global.schemaVersion, 3, "stamped")
    local t = sv.profiles.Default.callout
    assertEqual(t.glow, true, "strong: on")
    assertEqual(t.glowIntensity, 0.7, "at 70%")
    assertEqual(t.glowThickness, 5, "and 5 px")
    assertNil(t.texts, "the own texts dropped")
    assertNil(t.muted, "the mutes dropped")
    assertEqual(t.voice, "female", "a chosen voice is kept")
    assertEqual(NS.Callout:Get("voice"), "female", "and spoken with")
    local soft = sv.profiles.Soft.callout
    assertEqual(soft.glow, true, "soft: on, a profile that is not the active one")
    assertEqual(soft.glowThickness, 4, "a stored thickness wins over the choice's")
    assertEqual(sv.profiles.Off.callout.glow, false, "off: off")
    -- LibKa0s v1.102.0 (Callout minor 4): the retired choice named no color, offset or swatch, so the
    -- migration stores none and a migrated profile reads the new defaults for them: Glow color ticked,
    -- the black swatch, drawn 1 px right and 1 px down, where v1.100.0 drew the kind color at 0, 0.
    -- (The active profile's table holds AceDB's copy of every default, savedvariables-§1, so the
    -- stored check reads the profile that is not the active one.)
    for _, key in ipairs({ "glowCustom", "glowColor", "glowX", "glowY" }) do
        assertNil(rawget(soft, key), "soft: no " .. key .. " stored by the migration")
    end
    assertTrue(NS.Callout:Get("glowCustom"), "the active Strong profile reads Glow color ticked")
    assertEqual(NS.Callout:Get("glowX") .. "," .. NS.Callout:Get("glowY"), "1,-1", "at the new offset")
    -- From LibKa0s v1.108.0 (U-1) the glow draws the skin's glow color by default (Ka0s Default's
    -- gold); the black swatch is what it draws with the companion off.
    assertEqual(table.concat({ NS.Callout:GetGlowColor("go") }, ","), "1,0.82,0", "in the skin's glow color, not GO's")
    assertTrue(NS.SetByPath("callout.glowColorFromSkin", false))
    assertEqual(table.concat({ NS.Callout:GetGlowColor("go") }, ","), "0,0,0", "off: in the black swatch")
    assertNil(sv.profiles.Plain.callout, "a profile with no call-out table gains none")
    local errors = NS.ValidateSchema()
    assertEqual(errors, 0, "the boot check reads the bool rows clean")
end)

test("callout settings: a fresh profile is untouched by the migration and speaks with Arena John", function()
    if forever() then return end
    local NS = boot(nil)
    assertEqual(NS.db.global.schemaVersion, 3)
    assertEqual(NS.Callout:Get("voice"), "male-arena-john")
    assertTrue(NS.Callout:Get("glow"))
    local sv = _G.CombatTrailDB
    for _, profile in pairs(sv and sv.profiles or {}) do
        assertNil(rawget(profile, "callout") and rawget(profile.callout, "texts"), "no texts stored")
    end
    -- A second run is a no-op on a migrated profile.
    NS.db.global.schemaVersion = 2
    NS:RunMigrations()
    assertTrue(NS.Callout:Get("glow"))
end)

-- ── the one-time step onto the skin's defaults (LibKa0s v1.108.0, R-2, U-1, U-14) ────────────────

test("skin defaults step: a value stored at its old default moves once; a pick and the next run stay", function()
    local NS = boot({
        global = { schemaVersion = 3 },
        profileKeys = { ["Hunter - Realm"] = "Default" },
        profiles = {
            Default = { hud = { clock = { fontFlags = "" }, spells = { borderStyleFromSkin = false } } },
            Old = { hud = { clock = { fontFlags = "" }, spells = { borderStyleFromSkin = false,
                    borderColorFromSkin = false } },
                    callout = { font = "Ka0s Oxanium SemiBold", outline = "THICKOUTLINE", glowColorFromSkin = false } },
            Picked = { hud = { clock = { fontFlags = "THICKOUTLINE" }, spells = { borderStyleFromSkin = true } },
                       callout = { font = "Ka0s Inter", outline = "OUTLINE" } },
            Plain = { general = { locked = true } },
        },
    })
    local sv = _G.CombatTrailDB
    local old = sv.profiles.Old
    assertEqual(old.hud.clock.fontFlags, "@skin", "the clock's old \"\" moves to From skin (U-14)")
    assertEqual(old.hud.spells.borderStyleFromSkin, true, "the border's companions move (SD-SK-CT.3)")
    assertEqual(old.hud.spells.borderColorFromSkin, true)
    assertEqual(old.skin.defaultsMoved, true, "the record written")
    if not forever() then
        assertEqual(old.callout.font, "Skin font", "the call-out's L17 face moves to the Skin font (U-1)")
        assertEqual(old.callout.outline, "@skin", "and its outline to From skin")
        assertEqual(old.callout.glowColorFromSkin, true, "and its glow to the skin's color")
    end
    local picked = sv.profiles.Picked
    assertEqual(picked.hud.clock.fontFlags, "THICKOUTLINE", "a picked flag stays")
    assertEqual(picked.callout.font, "Ka0s Inter", "a picked face stays")
    assertEqual(picked.callout.outline, "OUTLINE", "a picked outline stays")
    assertEqual(picked.skin.defaultsMoved, true)
    assertNil(rawget(sv.profiles.Plain, "hud"), "a profile with no hud table gains none")
    assertEqual(sv.profiles.Plain.skin.defaultsMoved, true, "only the record")
    assertEqual(NS.GetSetting("hud.clock.fontFlags"), "@skin", "the active profile moved too")
    -- Once per profile: a value set back to the old default afterwards is the player's, and stays.
    old.hud.clock.fontFlags = ""
    NS:RunMigrations()
    assertEqual(old.hud.clock.fontFlags, "", "the record holds: no second move")
    assertFalse(NS.FollowSkinDefaults(old), "the step answers false on a profile it ran on")
end)

test("skin defaults step: a new or reset profile takes the step, which moves nothing a player sees", function()
    local NS = boot(nil)
    local p = NS.db.profile
    assertEqual(p.skin.defaultsMoved, true, "a fresh profile's record is written at the boot")
    assertEqual(p.hud.clock.fontFlags, "@skin", "its defaults already follow")
    NS.db:SetProfile("Second")
    assertEqual(NS.db.profile.skin.defaultsMoved, true, "a new profile runs it from the profile event")
    NS.db:ResetProfile()
    assertEqual(NS.db.profile.skin.defaultsMoved, true, "a reset profile runs it again")
    assertEqual(NS.db.profile.hud.spells.borderStyleFromSkin, true)
end)

test("skin defaults step: with no LibKa0s the same writes are made by hand, and the record", function()
    local NS = T.load{ libFiles = {} }.NS
    local p = { hud = { clock = { fontFlags = "" }, spells = { borderColorFromSkin = false } },
                callout = { font = "Ka0s Oxanium SemiBold" } }
    assertTrue(NS.FollowSkinDefaults(p), "it ran")
    assertEqual(p.hud.clock.fontFlags, "@skin")
    assertEqual(p.hud.spells.borderColorFromSkin, true)
    assertNil(p.hud.spells.borderStyleFromSkin, "a key never stored is not created")
    assertEqual(p.callout.font, "Ka0s Oxanium SemiBold", "no call-out library, no call-out move")
    assertEqual(p.skin.defaultsMoved, true, "the record, written by the step itself")
    assertFalse(NS.FollowSkinDefaults(p), "and once only")
end)

-- ── the drag strip's marks (LibKa0s#100, Callout minor 5, SD-CT-100) ─────────────────────────────

-- The call-out's drag strip, as LibKa0s-Widgets-1.0's DragHandle built it for the call-out's frame on
-- its first unlock (the instance builds its frame, and the strip with it, lazily), and the spec the
-- call-out handed it.
local function unlockedStrip(inst)
    local W = inst.mocks.LibStub("LibKa0s-Widgets-1.0")
    local real, built, spec = W.DragHandle, nil, nil
    W.DragHandle = function(parent, s)
        local h = real(parent, s)
        if s and s.moveFrame ~= nil then built, spec = h, s end
        return h
    end
    local ok, err = pcall(function() inst.NS.Callout:SetLocked(false) end)
    W.DragHandle = real
    if not ok then error(err, 0) end
    return built, spec
end

test("callout strip: unlocked, the strip carries ? · settings · close; the X locks it and turns the countdown off", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local h, spec = unlockedStrip(inst)
    assertTrue(h ~= nil, "the call-out's drag strip is built")
    assertTrue(type(spec.onClose) == "function" and type(spec.onSettings) == "function",
        "the call-out hands the strip this addon's close and settings")
    assertTrue(h.close ~= nil, "the close mark is drawn (onClose passed)")
    assertTrue(h.settings ~= nil, "the settings mark is drawn")
    assertTrue(NS.GetSetting("race.centerCountdown"), "the countdown on by default")
    local printed = #M.__printed()
    h.close:GetScript("OnClick")(h.close, "LeftButton")
    assertTrue(NS.Callout:Locked(), "the X locks the call-out: its sample and strip go")
    assertFalse(h:IsShown(), "the strip is hidden")
    assertEqual(NS.GetSetting("race.centerCountdown"), false, "the center countdown is off, through the seam")
    assertEqual(#M.__printed(), printed + 1, "one chat line")
    assertTrue(M.__printed()[#M.__printed()]:find("Race mode > Race > Countdown", 1, true) ~= nil,
        "it says where to turn it back on")
    -- Restorable: the row turns it back on, and the call-out's other settings were kept.
    assertTrue(NS.SetByPath("race.centerCountdown", true))
    assertTrue(NS.GetSetting("race.centerCountdown"))
    -- A second close with the countdown already off says nothing more.
    NS.SetByPath("race.centerCountdown", false)
    printed = #M.__printed()
    NS.CalloutClose()
    assertEqual(#M.__printed(), printed, "no chat line when it was already off")
end)

test("callout strip: the settings mark opens the Race mode page on its Callout tab", function()
    if forever() then return end
    local inst = T.load()
    local NS = inst.NS
    local H = NS.Helpers
    local opened, selected = {}, {}
    local open, select_ = H.OpenOptionsPanel, H.SelectTab
    H.OpenOptionsPanel = function(page) opened[#opened + 1] = page end
    H.SelectTab = function(page, tab) selected[#selected + 1] = page .. "/" .. tostring(tab) end
    local h = unlockedStrip(inst)
    local ok, err = pcall(function() h.settings:GetScript("OnClick")(h.settings, "LeftButton") end)
    H.OpenOptionsPanel, H.SelectTab = open, select_
    NS.Callout:SetLocked(true)
    if not ok then error(err, 0) end
    assertEqual(opened[1], "race", "the Race mode page")
    assertEqual(selected[1], "race/callout", "on its Callout tab")
end)
