-- tests/skin_surfaces.lua — this addon's painted surfaces, declared for the kit's skin-switch test
-- (tests/_kit/test_skin_switch.lua, kit revision 58, skinning-§1 and §9; plan Task 5.2). tests/run.lua
-- sets Kit.skinSwitch from it, and tests/test_skin_surfaces.lua holds it to every window: the DPS
-- HUD, the Results window, the ability timeline, the compare, the gear view and the lanes. Ported in
-- shape from DPS Race @045f479 (tests/skin_surfaces.lua). Loaded with dofile (no case of its own).
--
-- THE GRAIN IS ONE PAINTED OBJECT. The kit spies on what `build` answers and on its regions and
-- children, and a surface passes when anything under it changes, so each entry answers the object
-- that draws: a string, a texture or one small frame, or a window's shell.
--
-- ONE RUNNING INSTANCE, IN TEST MODE. Every window needs something to show, and test mode fills them
-- all from the sample history (modules/Preview.lua): the lanes play the sample rotation, the HUD
-- holds a sample fight, the Results window lists the sample fights and opens one in its detail, which
-- the timeline, the compare and the gear view open over. The skin library belongs to one instance, so
-- one is built on the first `build` and shared.
--
-- COMPANIONS. A surface behind a `FromSkin` row names it in `companion`, which excludes it from the
-- kit's ignored pass. The stored defaults have every companion on, so `companion(true)` writes nothing
-- a later surface would see.
--
-- `window` is this file's own field (the kit reads only its own): the window a surface belongs to,
-- which tests/test_skin_surfaces.lua reads to hold the coverage to all six, and on Retail a seventh:
-- the Race window (race plan Task C1), which wears the HUD's skin and is absent on WoW Forever.
--
-- EVERY FAMILY ON ITS OWN (kit revision 58, LibKa0s v1.108.0). Each family a surface draws (texture,
-- color, font, shadow) must move under the probe skin by itself, and every StatusBar under a surface
-- must draw its fill and move it. So each bar family of data is declared as its own surface
-- (`expect = "texture"` where the fill is a Texture), and a surface whose color a ruling keeps holds
-- that family (`hold`), the ruling cited beside it: the bars' fills are skinning-§9's Leave "Combat
-- Trail's bar colors" (A9, the audit's OVERRIDE row), the compare's sides and a class color are
-- meaning colors (skinning-§9).
--
-- Not declared: meaning colors on their own (the content chips' data hues, the class color, the over
-- card's gain), game art (spell and item icons) and the Race window's clocks (skinning-§9's race
-- clocks). The HUD fight clock is declared: it is no race clock (the owner's U-14 of 2026-11-20).

return function(T)
    local fixture

    local function live()
        if fixture then return fixture end
        local installPaint = dofile(T.root .. "/tests/_kit/mock_paint.lua")
        local inst = T.load{ mutate = function(m)
            installPaint(m)
            m.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        end }
        inst.mocks.__now = 1000
        assert(inst.NS.Preview.Start({ mode = "test" }), "test mode did not start")
        fixture = inst
        return inst
    end

    local function NSof() return live().NS end

    local function hud()
        return assert(NSof().Hud.__ui(), "the HUD window was never built")
    end
    local function hudBody()
        local u = hud()
        return u.body[u.current]
    end
    local function redrawHud() NSof().Hud.Refresh() end
    -- The next frame: the timers a switch armed (the Results detail's coalesced restyle) run.
    local function nextFrame() live().mocks.__fireTimers() end
    local function hudParts() return hudBody().parts end
    -- A spell row's paw: every row carries one, shown on a pet row only, and each is tinted the same
    -- (the sample fight has no pet row).
    local function rowPaw() return hudParts().spells.list:Rows()[1].paw end

    -- The Results window on the first sample fight, its detail open.
    local function results()
        local NS = NSof()
        local first = NS.ResultsSource.All()[1]
        assert(first, "no sample fight")
        if NS.Results.Selected() ~= first.id then assert(NS.Results.ShowFight(first.id), "the detail did not open") end
        return assert(NS.Results.__ui(), "the Results window was never built")
    end
    local function detail() return results().detail end

    local function timeline()
        local NS = NSof()
        assert(NS.ResultsTimeline.Open(detail()), "the timeline did not open")
        return NS.ResultsTimeline.__ui()
    end
    local function compare()
        local NS = NSof()
        assert(NS.ResultsCompare.Open(detail()), "the compare did not open")
        return NS.ResultsCompare.__ui()
    end
    local function gear()
        local NS = NSof()
        assert(NS.ResultsGear.Open(detail()), "the gear view did not open")
        return NS.ResultsGear.__ui()
    end

    -- A Results table row's bar (its Damage cell), a compare row's this-fight bar, and an Insights bar
    -- (By Character's first; `reset` puts the Fights tab back).
    local function resultsCell()
        for _, row in ipairs(results().list.list:Visible()) do
            local cell = row.record and row.cells and row.cells.damage
            if cell and cell.bar and cell.bar:IsShown() then return cell.bar end
        end
        error("no fight row draws a Damage bar")
    end
    local function compareBar()
        return compare().rows[1].barA
    end
    local function insightsBar()
        local NS = NSof()
        assert(NS.Results.ShowTab("insights"), "the Insights tab did not open")
        local rows = NS.Results.__ui().insights.ctx:Pool("chars").active
        return assert(rows[1] and rows[1].fill, "By Character draws no bar")
    end

    -- The lanes: built and fed by test mode; one icon is the newest the rotation pushed.
    local function laneIcon()
        local icons = NSof().LaneRender.__icons("player")
        return assert(icons[1], "the Player lane holds no sample cast")
    end
    local function interruptedIcon()
        local NS = NSof()
        NS.LaneRender.Push("player", { texture = 136133, spellID = 133, t = GetTime and GetTime() or 1000,
                                       interrupted = true })
        return NS.LaneRender.__icons("player")[1].mark
    end
    local function overlay()
        local NS = NSof()
        NS.LaneAnchor.SetUnlocked(true)
        return NS.LaneAnchor.__overlay("player")
    end

    -- The Race window (Retail only), opened on its idle body.
    local function race()
        local RW = NSof().RaceWindow
        RW.Show()
        return assert(RW.__ui(), "the Race window was never built")
    end
    local function raceBody()
        local u = race()
        return u.body[u.current]
    end

    local function writeSetting(path)
        return function(on) NSof().SetByPath(path, on) end
    end

    -- A surface that opens something leaves it for `reset` to close.
    local function closeAll()
        if not fixture then return end
        local NS = fixture.NS
        NS.ResultsTimeline.Hide()
        NS.ResultsCompare.Hide()
        NS.ResultsGear.Hide()
        NS.LaneAnchor.SetUnlocked(false)
        if NS.Results.Tab() == "insights" then NS.Results.ShowTab("fights") end
    end

    local declared = {
        owner = "CombatTrail",
        skin = function() return live().mocks.LibStub("LibKa0s-Skin-1.0") end,
        reset = closeAll,
        surfaces = {
            -- The DPS HUD
            { window = "hud", name = "the HUD's window shell", build = function() return hud().frame end },
            { window = "hud", name = "the HUD's footer", build = function() return hud().footLeft end },
            { window = "hud", name = "the HUD's test strip", build = function() return hud().testStrip end },
            { window = "hud", name = "the live figures' text", paint = redrawHud,
              companion = writeSetting("hud.figures.fontColorFromSkin"),
              build = function() return hudBody().w.damage.value end },
            { window = "hud", name = "the target line", build = function() return hudBody().w.target end },
            -- The HUD fight clock (U-14: no race clock, so its face, outline, color and shadow follow).
            { window = "hud", name = "the fight clock", paint = redrawHud,
              companion = writeSetting("hud.clock.fontColorFromSkin"), build = function() return hudBody().w.clock end },
            -- The damage chart's columns and the spell rows' bars: the skin's texture; their color is
            -- held (A9: Combat Trail's bar colors, the owner's call of 2026-10-31).
            { window = "hud", name = "a damage chart column", paint = redrawHud, hold = "color",
              build = function() return hudParts().chart:Columns()[1] end },
            { window = "hud", name = "a spell row's bar", paint = redrawHud, hold = "color",
              build = function() return hudParts().spells.list:Rows()[1].bar end },
            -- The pace bar's ahead half: the skin's texture in the ahead meaning token (ct.ahead).
            { window = "hud", name = "the pace bar's ahead half", paint = redrawHud,
              build = function() return hudParts().pace.ahead end },
            -- The pace line over the chart (SD-SK-CT.4) and the pet row's paw tint (SD-SK-CT.9).
            { window = "hud", name = "the damage chart's pace line", paint = redrawHud,
              companion = writeSetting("hud.chart.bestColorFromSkin"), build = function() return hudParts().chart.line end },
            { window = "hud", name = "a spell row's paw", paint = redrawHud, build = rowPaw },
            -- The Results window
            -- The shell holds the detail's chart columns and spell bars, which a switch redraws on the
            -- next frame (Results.Restyle): `paint` runs that frame, so each bar's fill is read.
            { window = "results", name = "the Results window's shell", paint = nextFrame,
              build = function() return results().frame end },
            { window = "results", name = "the Results footer", build = function() return results().footLeft end },
            { window = "results", name = "the Results test strip", build = function() return results().testStrip end },
            { window = "results", name = "the fight detail's name", build = function() return detail().w.name end },
            { window = "results", name = "the fight detail's Delete button", build = function() return detail().w.delete end },
            -- Bars of data on a Texture (Style.Bar): the skin's texture (expect), the color held (A9).
            { window = "results", name = "a Results row's Damage bar", expect = "texture", hold = "color",
              build = resultsCell },
            -- An Insights bar (SD-SK-CT.1): a class color's bar, so the color is held (a meaning color).
            { window = "results", name = "an Insights bar", expect = "texture", hold = "color", build = insightsBar },
            -- The ability timeline
            { window = "timeline", name = "the ability timeline's shell", build = function() return timeline().frame end },
            { window = "timeline", name = "the dim cover", build = function() return timeline() and results().cover.dim end },
            -- The compare
            { window = "compare", name = "the compare's shell", build = function() return compare().frame end },
            { window = "compare", name = "the compare's spell header", build = function() return compare().headName end },
            { window = "compare", name = "the compare's usage heading", build = function() return compare().usageTitle end },
            -- This fight's bar: the skin's texture in this fight's gold (a meaning color, the owner's
            -- v0.2 feedback), so the color is held.
            { window = "compare", name = "a compare row's bar", expect = "texture", hold = "color", build = compareBar },
            -- The gear view
            { window = "gear", name = "the gear view's shell", build = function() return gear().frame end },
            -- The legend's color is the compared fight's data hue: only its face follows, which Ignore fonts
            -- keeps. `hold`: the color is a meaning color (skinning-§9, the owner's THIS gold / runner-up
            -- blue, the audit's Compare and Timeline side colors row).
            { window = "gear", name = "the gear view's legend", scope = "fonts", hold = "color",
              build = function() return gear().legendA end },
            -- The lanes
            { window = "lanes", name = "a lane's background", companion = writeSetting("lanes.player.bgColorFromSkin"),
              build = function() return NSof().LaneRender.__bg("player") end },
            { window = "lanes", name = "a lane's label", companion = writeSetting("lanes.player.labelColorFromSkin"),
              build = function() return NSof().LaneRender.__label("player") end },
            { window = "lanes", name = "a lane icon's border", companion = writeSetting("lanes.player.borderColorFromSkin"),
              build = function() return laneIcon().border[1] end },
            { window = "lanes", name = "an interrupted cast's mark", build = interruptedIcon },
            { window = "lanes", name = "a lane's edit overlay", build = overlay },
            -- An icon's stack count (SD-SK-CT.7: HUD text), the GCD tick and the now line (SD-SK-CT.6).
            { window = "lanes", name = "a lane icon's count", build = function() return laneIcon().count end },
            { window = "lanes", name = "a lane's GCD tick", companion = writeSetting("lanes.player.tickColorFromSkin"),
              build = function() return assert(NSof().LaneRender.__ticks("player")[1], "no tick") end },
            { window = "lanes", name = "a lane's now line", companion = writeSetting("lanes.player.nowColorFromSkin"),
              build = function() return NSof().LaneRender.__now("player") end },
        },
    }
    if T.NS.Compat.ForClient({ "retail" }) then
        local list = declared.surfaces
        list[#list + 1] = { window = "race", name = "the Race window's shell", build = function() return race().frame end }
        list[#list + 1] = { window = "race", name = "the Race window's footer", build = function() return race().footLeft end }
        list[#list + 1] = { window = "race", name = "the Race window's target card", build = function() return raceBody().w.card.name end }
        list[#list + 1] = { window = "race", name = "the Race window's Arm Race button", build = function() return raceBody().w.arm end }
        -- The running body's time bar (the audit's bar families, SD-SK-CT): the skin's bar texture
        -- (S.BarTexture), its color held: green, yellow and red are the countdown's meaning colors
        -- (RaceWindowBoard.ClockColor). The body is built as showBody builds it, on the window's content.
        list[#list + 1] = { window = "race", name = "the Race window's time bar", expect = "texture", hold = "color",
            build = function()
                local u = race()
                local body = u.body.running or NSof().RaceWindowStates.Build("running", u.content)
                return body.w.bar.fill
            end }
    end
    return declared
end
