local _, NS = ...
-- modules/RaceTimeline.lua — a race's damage-update timeline (Race mode, plan Task B1): when the damage
-- stopped after the buzzer (the tail) and whether it landed again after a quiet gap (damage
-- restarted). Ported unchanged in behavior from DPS Race @f8078c7 (modules/Timeline.lua); the name
-- keeps it apart from the Results window's ability timeline (modules/Results_Timeline.lua).
--
-- PURE. No WoW API, no meter value: a timeline holds only GetTime() stamps that the race records when
-- a DAMAGE_METER_COMBAT_SESSION_UPDATED arrives for its fight's session (modules/RaceWatchers.lua):
-- decisions come from events and the clock, never from a meter number. One timeline per race, in
-- memory only.

local RaceTimeline = {}
NS.RaceTimeline = RaceTimeline

local methods = {}
local META = { __index = methods }

--- A new, empty timeline.
function RaceTimeline.New()
    return setmetatable({ times = {}, n = 0 }, META)
end

--- Record one damage update at time `t` (GetTime()). Updates normally arrive in order; a late one
--- is placed where it belongs, so the stamps stay sorted. A non-number is ignored.
function methods:AddDamage(t)
    if type(t) ~= "number" then return end
    local times, n = self.times, self.n
    local i = n
    while i > 0 and times[i] > t do
        times[i + 1] = times[i]
        i = i - 1
    end
    times[i + 1] = t
    self.n = n + 1
end

--- The time of the latest damage update, or nil when there is none.
function methods:LastDamage()
    return self.times[self.n]
end

--- Seconds from the buzzer to the last damage update after it; 0 when nothing landed after it.
function methods:Tail(buzzer)
    local last = self.times[self.n]
    if last and last > buzzer then return last - buzzer end
    return 0
end

--- The offset from the buzzer of the first damage update after it that follows a quiet stretch of at
--- least `gap` seconds. The stretch starts at the previous update or the buzzer, whichever is later.
--- With `resumedAt` (a /reload's resume), what landed during the loading screen is unknown, so the
--- first update after it measures its stretch from the resume, never across the reload.
--- nil when the damage never restarted.
function methods:RestartAt(buzzer, gap, resumedAt)
    local prev = buzzer
    local times = self.times
    for i = 1, self.n do
        local t = times[i]
        if t > buzzer then
            local from = prev
            if resumedAt and t >= resumedAt and resumedAt > from then from = resumedAt end
            if t - from >= gap then return t - buzzer end
            prev = t
        end
    end
    return nil
end
