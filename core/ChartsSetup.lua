local _, NS = ...
-- core/ChartsSetup.lua — NS.Charts from LibKa0s-Charts-1.0, and NS.ChartsHost(), the Results window's
-- look as that major's host table (Race mode plan Task D2, from DPS Race @f8078c7's own).
-- modules/Results_Insights.lua draws through both.
--
-- FILE SCOPE resolves the major only; NS.Style, NS.ResultsTable and NS.Skin are read when the host is
-- asked for (the Insights tab's first show), so this file loads among core/ before any module.

--- The major, or nil without the library: there is no drawing stub (anti-pattern #73), so the Insights
--- tab keeps its filters and its count and says the charts are unavailable.
NS.Charts = LibStub and LibStub("LibKa0s-Charts-1.0", true)

-- A gold title over the lines, bulleted from two (Style.AddTipLines), by the cursor.
local function cursorTip(owner, lines, anchor)
    local tip = GameTooltip
    if not tip then return end
    local r, g, b = NS.Style.Rgb("gtip.title")
    tip:SetOwner(owner, anchor)
    tip:SetText(lines[1], r, g, b, 1, true)
    NS.Style.AddTipLines(tip, lines, 2)
    tip:Show()
end

-- The window's flat panel for the list panels and the cards: the skin's Panel over the fight
-- detail's pane wash, so a skin switch repaints it.
local function panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    NS.Skin.Panel(f, { tokens = { bg = "ct.pane.bg", border = "divider" } })
    return f
end

--- The host table for the Results window: NS.Pool, the window's flat panel, its tooltip, its colors
--- (modules/Results_Table.lua's COLORS and the skin's chart tokens, every one a live skin color) and
--- font objects (modules/Style.lua's FONT), its labels painted through the skin (Style.Paint: the
--- skin's faces) and its textures through Style.Fill. The ranked palette is the skin's `chart.series`,
--- read at every draw. The meaning colors (class, content, dummy kind, length) are the rows' own,
--- chosen by the caller. No `owner`: every look here is named, so the window's own seams keep drawing
--- it, and Style's paint already follows a skin switch.
--- @return table
function NS.ChartsHost()
    local Style, Tbl = NS.Style, NS.ResultsTable
    local C, F = Tbl.COLORS, Style.FONT
    return {
        pool = NS.Pool,
        panel = panel,
        tip = cursorTip,
        hideTip = Tbl.HideTip,
        text = Style.PlainText,
        paint = function(fs, c) Style.Paint(fs, c, nil, true) end,
        fill = Style.Fill,
        palette = function() return NS.Skin.Token("chart.series") end,
        colors = {
            body = C.text, value = C.text, muted = C.dim, heading = C.gold, caption = C.dim,
            rule = Style.Tok("section.rule"), bar = Style.Tok("ct.chart.bar"),
            track = Style.Tok("chart.track"), axis = Style.Tok("chart.axis"),
        },
        fonts = {
            label = F.TEXT, axis = F.CAPTION, heading = F.CHART, divider = F.SECTION,
            panelTitle = F.CHART, caption = F.CAPTION, figure = F.FIGURE,
        },
    }
end
