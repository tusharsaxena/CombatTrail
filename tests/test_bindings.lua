-- tests/test_bindings.lua — the key bindings as the player meets them (launcher-§6, options-ui-§20,
-- plan Task 5.2): the bindings file the client reads in the addon's own category (Bindings_Mainline.xml
-- on Retail, with the Retail-only Toggle Race window key after Results; Bindings.xml on WoW Forever,
-- the three shared keys; the pair in step, a documented deviation), NS.BINDINGS in that file's order
-- with its labels, the General page's last tab, `Keybindings`, drawn by the library, and each press
-- running the one handler its surface shares (the HUD's toggle, the Results window's toggle, the Race
-- window's toggle and the lanes' toggle), refused while stood down exactly as the verb is. Capture,
-- conflict, combat and settings-window cases are the library's (testing-§8) and are not repeated.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local HUD, RESULTS, RACE, LANES =
    "CLICK CombatTrailToggleHud:LeftButton", "CLICK CombatTrailToggleResults:LeftButton",
    "CLICK CombatTrailToggleRace:LeftButton", "CLICK CombatTrailToggleLanes:LeftButton"
local LABELS = {
    [HUD]     = "Toggle DPS HUD",
    [RESULTS] = "Toggle Results window",
    [RACE]    = "Toggle Race window",
    [LANES]   = "Toggle lanes",
}

local function forever() return T.NS.Compat.IsForever() end

-- What this client binds, in its file's order: Retail's four, WoW Forever's three.
local function expected()
    if forever() then return { HUD, RESULTS, LANES } end
    return { HUD, RESULTS, RACE, LANES }
end

-- The file this client reads: the flavor-suffixed one on Retail, Bindings.xml on WoW Forever.
local function bindingsFile()
    return T.root .. (forever() and "/Bindings.xml" or "/Bindings_Mainline.xml")
end

-- Every Binding name in `path`, in order (comments stripped).
local function namesIn(path)
    local f = assert(io.open(path, "rb"), path)
    local body = f:read("*a"):gsub("<!%-%-.-%-%->", "")
    f:close()
    local names = {}
    for name in body:gmatch('<Binding%s+name="([^"]+)"') do names[#names + 1] = name end
    return names
end

local function buttons()
    local list = { "CombatTrailToggleHud", "CombatTrailToggleResults", "CombatTrailToggleLanes" }
    if not forever() then table.insert(list, 3, "CombatTrailToggleRace") end
    return list
end

--- The General page's ctx, drawn on `tab` (nil: its first): the strip's tab keys, the Keybindings
--- tab's row records when that tab drew.
local function showGeneral(inst, tab)
    local M, NS = inst.mocks, inst.NS
    local H = NS.Helpers
    local realTabs, realRows = H.RenderTabbedSchema, H.KeybindRows
    local keys, rows, ctx
    H.RenderTabbedSchema = function(c, ...)
        ctx = c
        local groups, drawn = realTabs(c, ...)
        keys = drawn
        return groups, drawn
    end
    H.KeybindRows = function(...)
        rows = realRows(...)
        return rows
    end
    local ok, err = pcall(function()
        local panel = M.__subcategories["General"]
        panel:Show()
        panel:__fire("OnShow")
        -- The first show drew the first tab; draw it again, on the tab asked for.
        if ctx and tab then
            ctx.activeTab = tab
            ctx._renderFn(ctx)
        end
    end)
    H.RenderTabbedSchema, H.KeybindRows = realTabs, realRows
    assert(ok, err)
    return keys, rows
end

local function text(M) return table.concat(M.__printed(), " | ") end

test("bindings: NS.BINDINGS is the bindings file's order, Show window first, each with a tooltip", function()
    local NS = T.NS
    local want = expected()
    assertEqual(#NS.BINDINGS, #want)
    for i, command in ipairs(want) do
        assertEqual(NS.BINDINGS[i].command, command)
        assertEqual(type(NS.BINDINGS[i].tooltip), "string", command)
        assertTrue(#NS.BINDINGS[i].tooltip > 0, command .. " tooltip is empty")
    end
end)

test("bindings: this client's bindings file is the addon's own category, no header, no default, labeled", function()
    local list = T.assertBindingsXml(bindingsFile(), {
        category = "BINDING_HEADER_COMBATTRAIL",
        commands = T.NS.BINDINGS,
        brand    = T.NS.BRAND,
        globals  = T.mocks._G,
        labels   = LABELS,
    })
    assertEqual(#list, #expected())
    assertEqual(T.mocks._G.BINDING_HEADER_COMBATTRAIL, "Ka0s Combat Trail")
end)

test("bindings: the pair in step: Bindings_Mainline.xml is Bindings.xml with the Race key after Results", function()
    local shared, mainline = namesIn(T.root .. "/Bindings.xml"), namesIn(T.root .. "/Bindings_Mainline.xml")
    assertEqual(table.concat(shared, ","), table.concat({ HUD, RESULTS, LANES }, ","), "Bindings.xml: the shared three")
    assertEqual(table.concat(mainline, ","), table.concat({ HUD, RESULTS, RACE, LANES }, ","),
        "Bindings_Mainline.xml: the shared three, the Race key after Results")
end)

test("bindings: on WoW Forever no Race key: no button, no row, no label", function()
    if not forever() then return end
    local inst = T.load()
    assertTrue(inst.mocks.__frameByName.CombatTrailToggleRace == nil, "the Race key's button was built")
    for _, b in ipairs(inst.NS.BINDINGS) do assertFalse(b.command == RACE, "a Race key row") end
    assertTrue(rawget(inst.mocks._G, "BINDING_NAME_" .. RACE) == nil, "a Race key label")
end)

test("bindings: the Race key runs /ct race toggle's handler (Retail)", function()
    if forever() then return end
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local calls = 0
    local real = NS.ToggleRaceWindow
    NS.ToggleRaceWindow = function(...) calls = calls + 1; return real(...) end
    M.__frameByName.CombatTrailToggleRace:__fire("OnClick", "LeftButton")
    assertEqual(calls, 1, "the press ran the shared handler once")
    assertTrue(NS.RaceWindow.IsShown(), "the Race window opened")
    M.__frameByName.CombatTrailToggleRace:__fire("OnClick", "LeftButton")
    NS.ToggleRaceWindow = real
    assertFalse(NS.RaceWindow.IsShown(), "and closed")
end)

test("bindings: the General page ends in the Keybindings tab, after Master controls", function()
    local inst = T.load()
    inst.mocks.__resetPrinted()
    local keys = assert(showGeneral(inst, nil), "the General page drew no tab strip")
    assertEqual(keys[1], inst.NS.Helpers.MASTER_GROUP, "Master controls stays first")
    assertEqual(keys[#keys], "Keybindings", "the Keybindings tab is the last")
    assertEqual(#inst.mocks.__printed(), 0, "a render printed: " .. text(inst.mocks))
end)

test("bindings: the tab's rows are NS.BINDINGS in order, labeled as the client labels them", function()
    local inst = T.load()
    local M, NS = inst.mocks, inst.NS
    M.__resetPrinted()
    local _, rows = showGeneral(inst, "Keybindings")
    rows = assert(rows, "the Keybindings tab drew no rows")
    assertEqual(#rows, #NS.BINDINGS)
    for i, row in ipairs(rows) do
        assertEqual(row.command, NS.BINDINGS[i].command)
        assertEqual(row.label:GetText(), M._G["BINDING_NAME_" .. row.command])
        assertEqual(row.label:GetText(), LABELS[row.command])
    end
    assertEqual(#M.__printed(), 0, "a render printed: " .. text(M))
end)

-- The kit's key press reaches the SHARED instance's options library, so this case draws on it.
test("bindings: a key bound in the tab is the client's key", function()
    local inst = { mocks = T.mocks, NS = T.NS }
    local M = inst.mocks
    M.clearBindings()
    local _, rows = showGeneral(inst, "Keybindings")
    rows = assert(rows, "the Keybindings tab drew no rows")
    assertEqual(T.keybindThroughTab(rows[1], 1, "K", { shift = true }), M.KEY_BOUND)
    assertEqual(M.GetBindingKey(HUD), "SHIFT-K")
    assertEqual(M.__savedBindingSets[#M.__savedBindingSets], M.GetCurrentBindingSet(), "saved to the set in force")
    M.clearBindings()
    showGeneral(inst, nil)
end)

test("bindings: each button is plain, named, hidden and down-edge only", function()
    -- The base frame answers RegisterForClicks through its catch-all; record what each button asks.
    local inst = T.load({ mutate = function(m)
        local real = m.CreateFrame
        m.CreateFrame = function(...)
            local f = real(...)
            f.RegisterForClicks = function(self, ...) self.__clicks = { ... }; return self end
            return f
        end
    end })
    local M = inst.mocks
    for _, name in ipairs(buttons()) do
        local b = M.__frameByName[name]
        assertTrue(b ~= nil, name .. " was not created")
        assertFalse(b:IsShown(), name .. " is shown")
        assertTrue(b.__template == nil, name .. " carries a template")
        assertEqual(table.concat(b.__clicks or {}, ","), "AnyDown", name .. " registers the down edge only")
    end
end)

test("bindings: the HUD key runs the launcher's Show window handler", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    local calls = 0
    local real = NS.ToggleHud
    NS.ToggleHud = function(...) calls = calls + 1; return real(...) end
    local was = NS.IsHudShown()
    M.__frameByName.CombatTrailToggleHud:__fire("OnClick", "LeftButton")
    NS.ToggleHud = real
    assertEqual(calls, 1, "the press ran the shared handler once")
    assertEqual(NS.IsHudShown(), not was, "the HUD toggled")
end)

test("bindings: the Results key shows and hides the Results window", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    assertFalse(NS.Results.IsShown())
    M.__frameByName.CombatTrailToggleResults:__fire("OnClick", "LeftButton")
    assertTrue(NS.Results.IsShown(), "the window opened")
    M.__frameByName.CombatTrailToggleResults:__fire("OnClick", "LeftButton")
    assertFalse(NS.Results.IsShown(), "the window closed")
end)

test("bindings: the lanes key turns the lanes off and back on as they were", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.SetByPath("lanes.pet.enabled", false)
    local key = M.__frameByName.CombatTrailToggleLanes
    key:__fire("OnClick", "LeftButton")
    assertEqual(NS.GetSetting("lanes.player.enabled"), false, "the Player lane went off")
    assertEqual(NS.GetSetting("lanes.pet.enabled"), false)
    key:__fire("OnClick", "LeftButton")
    assertEqual(NS.GetSetting("lanes.player.enabled"), true, "the Player lane came back")
    assertEqual(NS.GetSetting("lanes.pet.enabled"), false, "the Pet lane stays as it was")
    -- Both off from the start: the key turns both on.
    NS.SetByPath("lanes.player.enabled", false)
    key:__fire("OnClick", "LeftButton")
    assertEqual(NS.GetSetting("lanes.player.enabled"), true)
    assertEqual(NS.GetSetting("lanes.pet.enabled"), true)
end)

test("bindings: stood down, each key answers the refusal line and changes nothing", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("disable")
    local refusal = NS.StoodDownRefusal()
    for _, name in ipairs(buttons()) do
        M.__resetPrinted()
        M.__frameByName[name]:__fire("OnClick", "LeftButton")
        assertEqual(#M.__printed(), 1, name .. ": " .. text(M))
        assertTrue(M.__printed()[1]:find(refusal, 1, true) ~= nil, name .. " answers the refusal line")
    end
    assertFalse(NS.IsHudShown(), "the HUD stayed shut")
    assertFalse(NS.Results.wanted == true, "the Results window stayed shut")
    assertEqual(NS.GetSetting("lanes.player.enabled"), true, "the lanes key wrote nothing")
end)

test("bindings: the General Defaults tooltip says it leaves key bindings alone", function()
    local tip = T.mocks.__subcategories["General"].defaultsTooltip
    assertEqual(type(tip), "string", "no Defaults tooltip on the General page")
    assertTrue(tip:find(T.NS.Helpers.KEYBINDS_UNCHANGED, 1, true) ~= nil, tip)
end)
