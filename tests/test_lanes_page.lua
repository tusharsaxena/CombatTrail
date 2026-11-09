-- tests/test_lanes_page.lua — the Lanes settings page (plan Task 1.4, spec §4): the band's lane
-- picker rebinding every control, the seven tabs, Copy from and Reset lane, the Retail-only Where
-- rows, the Layer rows, the ignore list (tab and verb), the `lane` verb, the page's Defaults, the
-- preview and the class-color companions the lanes now draw.

local T = _G.CT_TEST
local test, assertEqual, assertTrue, assertFalse = T.test, T.assertEqual, T.assertTrue, T.assertFalse

local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")
local installIds = dofile(T.root .. "/tests/_kit/mock_ids.lua")

local function anyLine(M, needle)
    for _, l in ipairs(M.__printed()) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end

--- The Lanes page, built and on screen.
local function shownPage(opts)
    local inst = T.load(opts)
    inst.mocks.__subcategories["Lanes"]:__fire("OnShow")
    local ctx = inst.NS.pageCtx.lanes
    ctx.panel:Show()
    return inst, ctx
end

--- Every widget under `w`, depth first.
local function walk(w, out)
    for _, child in ipairs(w.children or {}) do
        out[#out + 1] = child
        walk(child, out)
    end
    return out
end

local function widget(inst, ctx, label)
    for _, w in ipairs(walk(ctx.scroll, {})) do
        if w.labelText == inst.NS.L[label] or w.text == inst.NS.L[label] then return w end
    end
end

local function lane(inst, key) return inst.NS.db.profile.lanes[key] end

-- Every leaf of a lane's defaults that a row should hold: all but the ignore set and the dock target.
local function leaves(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix == "" and k or (prefix .. "." .. k)
        if path ~= "ignore" and path ~= "anchor.target" then
            if type(v) == "table" and v.r == nil then leaves(v, path, out) else out[#out + 1] = path end
        end
    end
    return out
end

test("lanes page: all seven tabs exist, General first and Ignored spells last", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    local want = {}
    for i, key in ipairs(NS.LANES_TAB_ORDER) do want[i] = NS.LANES_TABS[key] end
    assertEqual(#want, 7)
    local _, keys = NS.Helpers.RenderTabbedSchema(ctx, "lanes", nil, nil, { tabs = NS.LanesPage.HOST_TABS })
    assertEqual(table.concat(keys or {}, ","), table.concat(want, ","))
end)

test("lanes page: every lane setting has a row for each lane", function()
    local NS = T.load().NS
    for _, key in ipairs({ "player", "pet" }) do
        for _, rel in ipairs(leaves(NS.defaults.profile.lanes[key], "", {})) do
            local row = NS.FindSchemaRow("lanes." .. key .. "." .. rel)
            assertTrue(row ~= nil, "no row for lanes." .. key .. "." .. rel)
            assertEqual(row.lane, key)
            assertEqual(row.page, "lanes")
        end
    end
    local errors, _, missing = NS.ValidateSchema()
    assertEqual(errors, 0)
    assertEqual(missing, 0)
end)

test("lanes page: switching dropdown rebinds every control to lanes.pet.*", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    assertEqual(NS.LanesPage.Selected(), "player")
    assertEqual(ctx.unit, "player")
    for _, row in ipairs(NS.SchemaForPage("lanes", "pet")) do
        if row.path then assertTrue(row.path:find("^lanes%.pet%.") ~= nil, row.path) end
    end
    -- The band's picker, as a player picks from it.
    local dd = ctx.__bannerDropdown
    assertTrue(dd ~= nil, "the band draws the lane picker")
    dd:__fire("OnValueChanged", "pet")
    assertEqual(NS.LanesPage.Selected(), "pet")
    NS.Helpers.RefreshPanel(ctx, true)
    assertEqual(ctx.unit, "pet")
    -- The General tab's Enable box now writes the Pet lane.
    local box = widget(inst, ctx, "Enable this lane")
    assertTrue(box ~= nil, "the Enable box is drawn")
    box:__fire("OnValueChanged", false)
    assertEqual(lane(inst, "pet").enabled, false)
    assertEqual(lane(inst, "player").enabled, true, "the Player lane is untouched")
end)

test("lanes page: a pick keeps the open tab", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.Helpers.SelectTab("lanes", NS.LANES_TABS.icons)
    NS.LanesPage.Select("pet")
    assertEqual(ctx.activeTab, NS.LANES_TABS.icons)
    assertTrue(widget(inst, ctx, "Mark interrupted casts") ~= nil)
end)

test("lanes page: copy from player copies everything but anchor and label", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("lanes.player.tooltip", false)
    NS.SetByPath("lanes.player.iconSize", 40)
    NS.SetByPath("lanes.player.borderColor", { r = 0.1, g = 0.2, b = 0.3, a = 1 })
    NS.SetByPath("lanes.player.visibility.show", "combat")
    NS.SetByPath("lanes.player.anchor.x", 99)
    NS.SetByPath("lanes.player.labelText", "Me")
    NS.SetByPath("lanes.player.enabled", false)
    assertTrue(NS.LanesPage.CopyFrom("player", "pet"))
    local pet = lane(inst, "pet")
    assertEqual(pet.tooltip, false)
    assertEqual(pet.iconSize, 40)
    assertEqual(pet.borderColor.b, 0.3)
    assertEqual(pet.visibility.show, "combat")
    assertEqual(pet.anchor.x, 0, "the anchor stays the lane's own")
    assertEqual(pet.anchor.mode, "dock")
    assertEqual(pet.labelText, "", "the label text stays the lane's own")
    assertEqual(pet.enabled, true, "the switch stays the lane's own")
    -- A copied color is the lane's own table, not the source's.
    NS.SetByPath("lanes.player.borderColor", { r = 1, g = 1, b = 1, a = 1 })
    assertEqual(pet.borderColor.b, 0.3)
end)

test("lanes page: reset lane restores defaults for that lane only", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("lanes.pet.width", 300)
    NS.SetByPath("lanes.pet.anchor.mode", "free")
    NS.SetByPath("lanes.player.width", 600)
    NS.LaneIgnore.Add("pet", 2649)
    NS.LaneIgnore.Remove("pet", 6603)
    assertTrue(NS.LanesPage.AcceptReset("pet"))
    local pet, D = lane(inst, "pet"), NS.defaults.profile.lanes.pet
    assertEqual(pet.width, D.width)
    assertEqual(pet.anchor.mode, "dock")
    assertEqual(pet.anchor.point, "TOP")
    assertEqual(pet.strata, "LOW")
    assertEqual(pet.ignore[2649], nil, "the ignore list is back to its seed")
    assertEqual(pet.ignore[6603], true)
    assertEqual(lane(inst, "player").width, 600, "the Player lane is untouched")
end)

test("lanes page: forever profile: no delve or arena rows on the Visibility tab", function()
    local NS = T.load().NS
    local delve = NS.FindSchemaRow("lanes.player.visibility.where.delve")
    local arena = NS.FindSchemaRow("lanes.pet.visibility.where.arena")
    assertTrue(NS.FindSchemaRow("lanes.player.visibility.where.raid") ~= nil)
    if NS.Compat.IsForever() then
        assertEqual(delve, nil)
        assertEqual(arena, nil)
    else
        assertTrue(delve ~= nil and arena ~= nil)
        assertEqual(table.concat(delve.clients, ","), "retail")
        assertEqual(table.concat(arena.clients, ","), "retail")
    end
end)

test("lanes page: Size and position has Frame strata (BACKGROUND to HIGH, + Match host in unit-frame mode) and Frame level 0-50", function()
    local NS = T.load().NS
    local strata = NS.FindSchemaRow("lanes.player.strata")
    assertEqual(strata.group, NS.LANES_TABS.size)
    local function offered()
        local out = {}
        for _, v in ipairs(strata.values()) do out[#out + 1] = v.value end
        return table.concat(out, ",")
    end
    assertEqual(offered(), "BACKGROUND,LOW,MEDIUM,HIGH")
    NS.SetByPath("lanes.player.anchor.mode", "unit")
    assertEqual(offered(), "BACKGROUND,LOW,MEDIUM,HIGH,HOST")
    assertEqual(NS.GetSetting("lanes.player.strata"), "HOST", "unit mode takes Match host by default")
    assertFalse(NS.SetByPath("lanes.player.strata", "DIALOG"), "DIALOG is not a player strata (frame-layering-§1)")
    assertTrue(NS.SetByPath("lanes.player.strata", "MEDIUM"))
    local level = NS.FindSchemaRow("lanes.pet.levelOffset")
    assertEqual(level.group, NS.LANES_TABS.size)
    assertEqual(level.min, 0)
    assertEqual(level.max, 50)
end)

test("lanes page: the dock gap and the frame name show only in the modes that use them", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.Helpers.SelectTab("lanes", NS.LANES_TABS.size)
    assertFalse(widget(inst, ctx, "Gap") ~= nil, "a free lane has no gap")
    NS.SetByPath("lanes.player.anchor.mode", "unit")
    NS.Helpers.RefreshPanel(ctx, true)
    assertTrue(widget(inst, ctx, "Gap") ~= nil)
    assertTrue(widget(inst, ctx, "Frame by name") ~= nil)
    NS.LanesPage.Select("pet")
    assertTrue(widget(inst, ctx, "Gap") ~= nil, "the Pet lane docks")
    assertFalse(widget(inst, ctx, "Frame by name") ~= nil)
end)

test("lanes page: ignore tab add by ID, by name, remove, reset to seed", function()
    local inst, ctx = shownPage({ mutate = installIds })
    local NS, M = inst.NS, inst.mocks
    M.addIdRecord("spell", 2649, "Growl", 132270)
    NS.LanesPage.Select("pet")
    NS.Helpers.SelectTab("lanes", NS.LANES_TABS.ignore)
    local LI = NS.LaneIgnore
    assertEqual(table.concat(LI.Entries("pet"), ","), "6603")
    assertEqual(LI.Resolve("2649"), 2649)
    assertEqual(LI.Resolve("Growl"), 2649, "by name")
    assertTrue(LI.Add("pet", 2649))
    assertTrue(NS.LaneCasts.IsIgnored("pet", 2649))
    assertFalse(NS.LaneCasts.IsIgnored("player", 2649), "per lane")
    assertTrue(LI.Remove("pet", 6603))
    assertEqual(lane(inst, "pet").ignore[6603], false, "a removed seed is stored false")
    assertTrue(LI.Remove("pet", 2649))
    assertEqual(lane(inst, "pet").ignore[2649], nil)
    LI.ResetToSeed("pet")
    assertEqual(table.concat(LI.Entries("pet"), ","), "6603")
    -- The tab draws the list's add box.
    assertTrue(widget(inst, ctx, "Add a spell") ~= nil, "the add box is drawn")
end)

test("lanes page: slash: /kct lane pet off disables the pet lane", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("lane pet off")
    assertEqual(lane(inst, "pet").enabled, false)
    assertTrue(anyLine(M, "Pet lane"))
    NS.Slash:OnSlash("lane pet on")
    assertEqual(lane(inst, "pet").enabled, true)
    NS.Slash:OnSlash("lane player")
    assertEqual(lane(inst, "player").enabled, false, "no on or off flips it")
    M.__resetPrinted()
    NS.Slash:OnSlash("lane cat off")
    assertTrue(anyLine(M, "Usage"))
end)

test("lanes page: slash: /kct ignore add 2649 pet", function()
    local inst = T.load()
    local NS, M = inst.NS, inst.mocks
    NS.Slash:OnSlash("ignore add 2649 pet")
    assertEqual(lane(inst, "pet").ignore[2649], true)
    assertEqual(lane(inst, "player").ignore[2649], nil)
    NS.Slash:OnSlash("ignore add 2649")
    assertEqual(lane(inst, "player").ignore[2649], true, "the Player lane by default")
    NS.Slash:OnSlash("ignore remove 2649 pet")
    assertEqual(lane(inst, "pet").ignore[2649], nil)
    M.__resetPrinted()
    NS.Slash:OnSlash("ignore list player")
    assertTrue(anyLine(M, "2649"))
    NS.Slash:OnSlash("ignore reset player")
    assertEqual(lane(inst, "player").ignore[2649], nil)
    M.__resetPrinted()
    NS.Slash:OnSlash("ignore add")
    assertTrue(anyLine(M, "Usage"))
end)

test("lanes page: the lane and ignore verbs answer while the addon is disabled", function()
    local inst = T.load()
    local NS = inst.NS
    NS.SetByPath("general.enabled", false)
    NS.Slash:OnSlash("lane pet off")
    NS.Slash:OnSlash("ignore add 2649 pet")
    assertEqual(lane(inst, "pet").enabled, false)
    assertEqual(lane(inst, "pet").ignore[2649], true)
end)

test("lanes page: the page's Defaults resets both lanes and their ignore lists", function()
    local inst, ctx = shownPage()
    local NS = inst.NS
    NS.SetByPath("lanes.player.seconds", 20)
    NS.SetByPath("lanes.pet.seconds", 8)
    NS.LaneIgnore.Add("player", 2649)
    ctx.panel.defaultsOnClick()
    assertEqual(lane(inst, "player").seconds, 12)
    assertEqual(lane(inst, "pet").seconds, 12)
    assertEqual(lane(inst, "player").ignore[2649], nil)
end)

test("lanes page: preview fills the picked lane with sample casts", function()
    local inst = T.load({ mutate = installPaint })
    local NS = inst.NS
    local n = NS.LanesPage.Preview("player")
    assertTrue(n > 0, "icons pushed")
    assertEqual(#NS.LaneRender.__icons("player"), n)
    local marked = 0
    for _, f in ipairs(NS.LaneRender.__icons("player")) do if f.interrupted then marked = marked + 1 end end
    assertEqual(marked, 1, "one sample shows the interrupted mark")
    NS.SetByPath("lanes.pet.enabled", false)
    assertEqual(NS.LanesPage.Preview("pet"), 0)
end)

test("lanes page: a Use class color companion draws the player's class color", function()
    local inst = T.load({ mutate = function(m)
        installPaint(m)
        m.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    end })
    local NS = inst.NS
    NS.SetByPath("lanes.player.labelClassColor", true)
    local fs = NS.LaneRender.__label("player")
    local r, g, b = fs:GetTextColor()
    assertEqual(r, 0.25)
    assertEqual(g, 0.78)
    assertEqual(b, 0.92)
    NS.SetByPath("lanes.player.labelClassColor", false)
    r = fs:GetTextColor()
    assertEqual(r, 1, "off, the swatch again")
end)
