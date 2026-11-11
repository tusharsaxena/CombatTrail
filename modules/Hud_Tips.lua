local _, NS = ...
-- modules/Hud_Tips.lua — the words of the DPS HUD's tooltips (plan Task 3.2): each main element of
-- each body says what it is and what it does. Adapted from DPS Race @045f479 (modules/Hud_Tips.lua)
-- without its race (no arm, length, buzzer or late-cast words). Data, and the one hover path the
-- HUD's parts share (HudTips.Attach): a title and its lines in the skin's tooltip colors.
--
-- FIXED WORDS, NO FIGURES. A HUD figure may be secret for the whole fight, and a tooltip reads
-- nothing off the screen: these strings never name a live value, so hovering in combat is as safe as
-- a label.

local L = NS.L

local Tips = {
    clock = { L["Fight clock"], L["How long this fight has run, from your first hit."] },
    target = { L["Target"], L["The boss or target this fight is against, with the instance and difficulty its bests group by."] },
    liveDamage = { L["Damage"], L["Your damage so far this fight, as the damage meter reports it. Your pet's shows beside it."] },
    liveDps = { L["DPS"], L["Your damage per second so far this fight, as the damage meter reports it."] },
    overDamage = { L["Damage"], L["This fight's total damage, yours and your pet's."] },
    overDps = { L["DPS"], L["This fight's damage per second, yours and your pet's."] },
    pace = { L["Pace bar"], L["Your damage against your best's at this point in the fight. The tick in the middle is on pace: red short of it is how far behind you are, green past it how far ahead."] },
    overPace = { L["Pace bar"], L["This fight's final damage against the best it was paced against, at the same length. The tick in the middle is level with that best: red short of it is behind, green past it ahead."] },
    chart = { L["Damage profile"], L["How your damage built up over the fight, one column per slice of time. The line is your best's average pace, and icons mark your long cooldowns."] },
    liveSpells = { L["Spell breakdown"], L["Your spells, then your pet's, in the damage meter's order. Shares appear once the fight is over. The mouse wheel scrolls through more spells than the rows hold."] },
    overSpells = { L["Spell breakdown"], L["This fight's spells, highest damage first, with each one's share. The mouse wheel scrolls through more spells than the rows hold."] },
}

NS.HudTips = Tips

--- Give `frame` the hover for tip `key` (a { title, line, ... } entry above): the frame takes the
--- mouse, and its tooltip sits above it. `frame.tipKey` may be changed later to change its words.
--- @param frame table
--- @param key string
function Tips.Attach(frame, key)
    frame.tipKey = key
    if frame.tipWired then return end
    frame.tipWired = true
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local tip = Tips[self.tipKey]
        if type(tip) ~= "table" or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip[1], NS.Style.Rgb("gtip.title"))
        local r, g, b = NS.Style.Rgb("gtip.body")
        for i = 2, #tip do GameTooltip:AddLine(tip[i], r, g, b, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
