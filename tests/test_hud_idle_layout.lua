-- tests/test_hud_idle_layout.lua — the idle HUD keeps the in-combat layout (owner feedback round 6,
-- R6-CT-01: "Looks a bit weird out of combat - doesn't seem to line up with the in combat view"). The
-- section stack is placed from the configuration alone, never from what the fight has: the target
-- line's slot, the boxes with their pet row, the Damage profile section (its heading, the pace line
-- whenever the HUD paces, the plot frame and its time labels), the spell rows' whole window and the
-- docked Combat Sequence sit at the same offsets with no fight yet, live and on the fight-over card,
-- so nothing jumps when a fight starts or ends. A part the layout switches off stays off in every
-- state. Every offset read here is one the code set (a recorder over the setters), never a size read
-- back off a value-bearing region.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse
local H = dofile(T.root .. "/tests/hud_fixture.lua")(T)

local ENEMIES = { { name = "Angry Boar", creatureID = 1985, damage = 40000 } }

-- A fight with `n` player spells (ids 1001...), and optionally the pet's two.
local function fightOf(n, pet)
    local spells = {}
    for i = 1, n do spells[i] = { id = 1000 + i, dmg = 1000 * (n - i + 1), dps = 25 * (n - i + 1) } end
    local f = { damage = 40000, dps = 1000, duration = 40, spells = spells, enemies = ENEMIES }
    if pet then
        f.pet = { damage = 8000, dps = 200,
                  spells = { { id = 17253, dmg = 5000, dps = 125 }, { id = 16827, dmg = 3000, dps = 75 } } }
    end
    return f
end

-- Record what the code sets on `f` (the kit's frames answer no geometry unless armed).
local function track(f)
    rawset(f, "__points", {})
    rawset(f, "ClearAllPoints", function(self) rawset(self, "__points", {}) end)
    rawset(f, "SetPoint", function(self, ...)
        local list = rawget(self, "__points")
        list[#list + 1] = { ... }
    end)
    rawset(f, "SetSize", function(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end)
    rawset(f, "SetWidth", function(self, w) rawset(self, "__w", w) end)
    rawset(f, "SetHeight", function(self, h) rawset(self, "__h", h) end)
    return f
end

local function y(region) return region and region.__points and region.__points[1] and region.__points[1][5] end

-- Every placed part of the body on screen, tracked, then the HUD redrawn: each section's offset and
-- height, keyed by name, plus whether it shows.
local function geometry(Hud, key)
    local body = H.body(Hud, key)
    local w, p = body.w, body.parts
    -- Rebuild the box's value anchor too: tracked, then placed again.
    for _, k in ipairs({ w.damage, w.dps }) do track(k.frame); k.placed = nil end
    for _, part in ipairs({ p.chart and p.chart.plot, p.pace and p.pace.bar, p.spells and p.spells.frame }) do
        if part then track(part) end
    end
    track(Hud.Frame())
    Hud.Apply()
    Hud.Refresh()
    local chart, spells = p.chart, p.spells
    local g = {
        clock = y(w.clock), target = w.target:IsShown() and y(w.target) or "hidden",
        box = y(w.damage.frame), boxH = w.damage.frame.__h, dpsBox = y(w.dps.frame), dpsBoxH = w.dps.frame.__h,
        stackTop = body.stackTop, height = body.height, window = Hud.Frame().__h,
        profile = chart and chart.title:IsShown() and y(chart.title) or "hidden",
        -- the plot's and the axis's slots, drawn or not (R7-CT-01: the empty plot is hidden, its slot kept)
        plot = chart and (chart.plot:IsShown() or body.chartSlot) and y(chart.plot) or "hidden",
        axis = chart and (chart.axis[1]:IsShown() or body.chartSlot) and y(chart.axis[1]) or "hidden",
        plotShown = chart and chart.plot:IsShown(),
        spells = spells and spells.title:IsShown() and y(spells.title) or "hidden",
        rows = spells and spells.frame:IsShown() and y(spells.frame) or "hidden",
        rowsH = spells and spells.frame:IsShown() and spells.frame.__h or "hidden",
    }
    return g, body
end

local function assertSame(a, b, what)
    for _, k in ipairs({ "clock", "target", "box", "boxH", "dpsBox", "dpsBoxH", "stackTop", "height", "window",
                         "profile", "plot", "axis", "spells", "rows", "rowsH" }) do
        assertEqual(b[k], a[k], what .. ": " .. k)
    end
end

-- The HUD opened by the player with no fight yet.
local function idle(opts)
    opts = opts or {}
    local inst, meter, Hud = H.fresh({ pet = opts.pet })
    for k, v in pairs(opts.hud or {}) do H.setHud(inst, k, v) end
    Hud.Show()
    return inst, meter, Hud
end

-- A fight live from t 100 on `session`, paced against a stored `best` when given.
local function liveOn(session, opts)
    opts = opts or {}
    local inst, meter, Hud = H.fresh({ pet = opts.pet })
    for k, v in pairs(opts.hud or {}) do H.setHud(inst, k, v) end
    if opts.best then H.whole(inst, meter, 1, opts.best, 10, 40) end
    H.start(inst, meter, 2, session, 100)
    H.tick(inst, 101.25, 102)
    return inst, meter, Hud
end

-- ── the stack ───────────────────────────────────────────────────────────────────────────────────

test("hud idle layout: with no fight the stack sits where the paced live fight with a pet puts it", function()
    local _, _, IdleHud = idle()
    local still, idleBody = geometry(IdleHud, "live")
    local _, _, LiveHud = liveOn(fightOf(8, true), { pet = true, best = fightOf(8, true) })
    local live, liveBody = geometry(LiveHud, "live")
    assertTrue(liveBody.paceShown == true and liveBody.chartShown == true, "the live fight paces and charts")
    assertSame(live, still, "idle vs live")
    assertTrue(still.profile ~= "hidden", "the Damage profile section is there with no fight")
    assertTrue(still.plot ~= "hidden", "its plot's slot too")
    -- red under (R7-CT-01, the owner: "Remove the empty graph when empty - but keep the spacing")
    assertFalse(still.plotShown, "the empty plot is not drawn")
    assertFalse(idleBody.parts.chart.axis[1]:IsShown(), "nor its 0:00")
    assertTrue(live.plotShown, "a fight's plot is drawn")
    assertEqual(idleBody.height, LiveHud.FixedHeight() - (LiveHud.Frame().__h - liveBody.height),
        "the idle stack fills the one window")
end)

test("hud idle layout: the fight-over card lines up with the live body and the idle one", function()
    local _, _, IdleHud = idle()
    local still = geometry(IdleHud, "live")
    local inst, _, Hud = liveOn(fightOf(8, true), { pet = true, best = fightOf(8, true) })
    local live = geometry(Hud, "live")
    H.finish(inst, 100, 40)
    assertEqual(Hud.State(), "over")
    local over = geometry(Hud, "over")
    assertSame(live, over, "live vs over")
    assertSame(still, over, "idle vs over")
end)

test("hud idle layout: a live fight with no pet and nothing to pace against keeps the same slots", function()
    local _, _, IdleHud = idle()
    local still = geometry(IdleHud, "live")
    local _, _, Hud = liveOn(fightOf(2))
    local live, body = geometry(Hud, "live")
    assertFalse(body.paceShown == true, "no best: no pace drawn")
    assertSame(still, live, "idle vs a bare live fight")
end)

test("hud idle layout: the idle placeholders are muted and say what is missing", function()
    local inst, _, Hud = idle()
    local _, body = geometry(Hud, "live")
    local w, chart = body.w, body.parts.chart
    assertEqual(w.target.__text, "No target", "the target line's slot holds a placeholder")
    assertTrue(w.damage.petLabel:IsShown() and w.damage.petValue:IsShown(), "the pet row's slot is kept")
    assertEqual(w.damage.petValue.__text, "\226\128\148", "a dash for the pet")
    assertEqual(w.dps.petValue.__text, "\226\128\148")
    -- Muted: the pet's dash in the target line's dim, not the pet figure's own hue.
    local function rgb(fs) local r, g, b = fs:GetTextColor(); return ("%.3f %.3f %.3f"):format(r, g, b) end
    assertEqual(rgb(w.damage.petValue), rgb(w.target), "the idle pet dash is dim")
    assertEqual(w.damage.value.__text, "\226\128\148")
    -- the heading stays; the empty plot and its time labels are hidden, their slot kept (R7-CT-01)
    assertTrue(chart.title:IsShown() and not chart.plot:IsShown() and not chart.axis[1]:IsShown())
    assertEqual(chart.note.__text, "No fight yet")
    assertEqual(chart.axis[1].__text, "0:00")
    assertEqual(chart.axis[2].__text, "", "no span to mark")
    assertEqual(chart.axis[3].__text, "")
    assertEqual(#body.parts.spells.list:Rows(), 0, "no rows to draw")
    local ui = Hud.__ui()
    -- The footer names you now, as a fight's names you at its entry (the client's own read).
    local who, parts = inst.NS.Identity.Who(), {}
    for _, s in ipairs({ who.specName, who.name }) do if s then parts[#parts + 1] = s end end
    assertEqual(ui.footLeft.__text or "", table.concat(parts, " \194\183 "), "the footer names the character")
    assertEqual(ui.footRight.__text, "waiting for a fight")
    assertTrue(inst.NS.Hud.State() ~= "hidden")
end)

test("hud idle layout: a fight that starts takes its placeholders away", function()
    local _, _, PetHud = liveOn(fightOf(4, true), { pet = true })
    local _, petBody = geometry(PetHud, "live")
    local function rgb(fs) local r, g, b = fs:GetTextColor(); return ("%.3f %.3f %.3f"):format(r, g, b) end
    assertTrue(petBody.w.damage.petValue:IsShown(), "the pet's figure in its slot")
    assertTrue(rgb(petBody.w.damage.petValue) ~= rgb(petBody.w.target), "in the pet figure's own hue, not dim")
    local _, _, Hud = liveOn(fightOf(4))
    local _, body = geometry(Hud, "live")
    local w = body.w
    assertTrue(w.target.__text:find("Angry Boar", 1, true) == 1, "the fight's own target line")
    assertFalse(w.damage.petLabel:IsShown(), "no pet: the slot stays, empty")
    assertTrue(body.parts.chart.note.__text ~= "No fight yet")
    assertEqual(Hud.__ui().footRight.__text, "live", "the footer says live (R7-CT-02: no rate)")
end)

-- ── the switches ────────────────────────────────────────────────────────────────────────────────

test("hud idle layout: a part switched off stays off in both states, and both still line up", function()
    for _, hud in ipairs({ { ["layout.chart"] = false }, { ["layout.chart"] = false, ["layout.pace"] = false },
                           { ["layout.target"] = false }, { ["layout.figures"] = false },
                           { ["layout.spells"] = false }, { paceAgainst = "none" } }) do
        local label = ""
        for k, v in pairs(hud) do label = label .. k .. "=" .. tostring(v) .. " " end
        local _, _, IdleHud = idle({ hud = hud })
        local still = geometry(IdleHud, "live")
        local _, _, Hud = liveOn(fightOf(8, true), { pet = true, best = fightOf(8, true), hud = hud })
        local live = geometry(Hud, "live")
        assertSame(still, live, label)
        if hud["layout.chart"] == false then assertEqual(still.plot, "hidden", label .. ": no plot idle") end
        if hud["layout.spells"] == false then assertEqual(still.spells, "hidden", label .. ": no rows idle") end
        if hud["layout.target"] == false then assertEqual(still.target, "hidden", label) end
    end
end)

test("hud idle layout: the idle stack is the window's fixed stack exactly", function()
    local inst, _, Hud = idle()
    local _, body = geometry(Hud, "live")
    local NS = inst.NS
    assertEqual(body.height, NS.HudStates.FixedStack(NS.db.profile.hud.layout, 5, true),
        "every reserved slot drawn, no blank under the stack")
end)
