local _, ns = ...

-- Measures the mana that really comes back, to check GetManaRegen against the server.
-- Two meters: "rest" (5 s or more since mana was last spent) and "casting" (within those 5 s).
-- A run is a series of gains with no spending in between. Its rate is the mana gained after the
-- first gain over the time from the first gain to the last, so it doesn't matter where in a
-- regen tick the run started. A gain that reaches full mana may be cut short, so it ends the
-- run without counting. Drinks, potions and the like show up as gains far above the expected
-- rate; runs like that are thrown away.

local Regen = {}
ns.Regen = Regen

local issecret = issecretvalue or function() return false end
local FSR = 5           -- the five-second rule
local MIN_TICKS = 3
local OUTLIER = 2.5     -- a run this many times over GetManaRegen's rate isn't plain regen

local runs = { rest = {}, casting = {} }
local results = {}      -- per kind: { rate = mana per second, ticks, seconds, at }
local lastMana, lastSpend = nil, -FSR
local castingGain = false

local function Expected(kind)
    if not GetManaRegen then return nil end
    local ok, base, casting = pcall(GetManaRegen)
    if not ok or issecret(base) or issecret(casting) then return nil end
    return kind == "rest" and base or casting
end

local function Finish(kind)
    local r = runs[kind]
    if r.ticks and r.ticks >= MIN_TICKS and r.tLast > r.t0 then
        local rate = r.gained / (r.tLast - r.t0)
        local expected = Expected(kind)
        if not (expected and expected > 0 and rate > expected * OUTLIER) then
            results[kind] = { rate = rate, ticks = r.ticks, seconds = r.tLast - r.t0, at = GetTime() }
        end
    end
    runs[kind] = {}
end

local function OnMana()
    local m, max = UnitPower("player", 0), UnitPowerMax("player", 0)
    if issecret(m) or issecret(max) or not max or max <= 0 then
        lastMana = nil
        return
    end
    local now = GetTime()
    if lastMana then
        if m < lastMana then
            lastSpend = now
            castingGain = false
            Finish("rest")
            Finish("casting")
        elseif m > lastMana then
            local kind = (now - lastSpend >= FSR) and "rest" or "casting"
            Finish(kind == "rest" and "casting" or "rest")
            if kind == "casting" then
                castingGain = true
            elseif not castingGain and lastSpend > 0 then
                -- A whole five seconds after spending went by with nothing coming back.
                results.castingNone = GetTime()
                castingGain = true
            end
            if m >= max then
                Finish(kind)
            else
                local r = runs[kind]
                if not r.t0 then
                    r.t0, r.tLast, r.gained, r.ticks = now, now, 0, 1
                else
                    r.gained, r.tLast, r.ticks = r.gained + (m - lastMana), now, r.ticks + 1
                end
            end
        end
    end
    lastMana = m
end

-- The best reading of a kind: the run in progress if it's long enough, else the last one.
function Regen:Rate(kind)
    local r = runs[kind]
    if r.ticks and r.ticks >= MIN_TICKS + 2 and r.tLast > r.t0 then
        return r.gained / (r.tLast - r.t0), r.ticks, r.tLast - r.t0
    end
    local res = results[kind]
    if res then return res.rate, res.ticks, res.seconds end
end

-- True when mana was spent and nothing came back during the following five seconds.
function Regen:NoneWhileCasting()
    return results.castingNone ~= nil and not results.casting
end

function Regen:Snapshot()
    return { results = results, runs = runs, expectedRest = Expected("rest"), expectedCasting = Expected("casting") }
end

local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
f:SetScript("OnEvent", function(_, _, _, powerType)
    if powerType == "MANA" then OnMana() end
end)
