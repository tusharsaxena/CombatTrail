-- tests/skin_surfaces.lua — this addon's painted surfaces, declared for the kit's skin-switch test
-- (tests/_kit/test_skin_switch.lua, kit revision 50, skinning-§1 and §9; plan Task 5.2). tests/run.lua
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
-- Not declared: meaning colors (the content chips' data hues, the class color, the over card's gain),
-- game art (spell and item icons), the ticks and the now line (thin flat lines, skinning-§9's Leave
-- class) and the clock, whose mono face never follows (debug-logging-§2's monospace role).

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
            -- The Results window
            { window = "results", name = "the Results window's shell", build = function() return results().frame end },
            { window = "results", name = "the Results footer", build = function() return results().footLeft end },
            { window = "results", name = "the Results test strip", build = function() return results().testStrip end },
            { window = "results", name = "the fight detail's name", build = function() return detail().w.name end },
            { window = "results", name = "the fight detail's Delete button", build = function() return detail().w.delete end },
            -- The ability timeline
            { window = "timeline", name = "the ability timeline's shell", build = function() return timeline().frame end },
            { window = "timeline", name = "the dim cover", build = function() return timeline() and results().cover.dim end },
            -- The compare
            { window = "compare", name = "the compare's shell", build = function() return compare().frame end },
            { window = "compare", name = "the compare's spell header", build = function() return compare().headName end },
            { window = "compare", name = "the compare's usage heading", build = function() return compare().usageTitle end },
            -- The gear view
            { window = "gear", name = "the gear view's shell", build = function() return gear().frame end },
            -- The legend's color is the compared fight's data hue: only its face follows, which Ignore fonts keeps.
            { window = "gear", name = "the gear view's legend", scope = "fonts", build = function() return gear().legendA end },
            -- The lanes
            { window = "lanes", name = "a lane's background", companion = writeSetting("lanes.player.bgColorFromSkin"),
              build = function() return NSof().LaneRender.__bg("player") end },
            { window = "lanes", name = "a lane's label", companion = writeSetting("lanes.player.labelColorFromSkin"),
              build = function() return NSof().LaneRender.__label("player") end },
            { window = "lanes", name = "a lane icon's border", companion = writeSetting("lanes.player.borderColorFromSkin"),
              build = function() return laneIcon().border[1] end },
            { window = "lanes", name = "an interrupted cast's mark", build = interruptedIcon },
            { window = "lanes", name = "a lane's edit overlay", build = overlay },
        },
    }
    if T.NS.Compat.ForClient({ "retail" }) then
        local list = declared.surfaces
        list[#list + 1] = { window = "race", name = "the Race window's shell", build = function() return race().frame end }
        list[#list + 1] = { window = "race", name = "the Race window's footer", build = function() return race().footLeft end }
        list[#list + 1] = { window = "race", name = "the Race window's target card", build = function() return raceBody().w.card.name end }
        list[#list + 1] = { window = "race", name = "the Race window's Arm Race button", build = function() return raceBody().w.arm end }
    end
    return declared
end
