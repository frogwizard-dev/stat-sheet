local _, ns = ...

-- Measures the mana that comes back, to check GetManaRegen against the server: "rest" (5 s or more
-- since mana was spent) and "casting" (within those 5 s). A run is gains with no spending between;
-- its rate counts from its first gain to its last, so where in a tick it started doesn't matter.
-- A gain that fills the bar may be cut short, so it ends the run uncounted; drinks show as outliers.

local Regen = {}
ns.Regen = Regen

local issecret = FrogLib.issecret
local FIVE_SECOND_RULE = 5
local MIN_TICKS = 3
local OUTLIER = 2.5     -- a run this many times over GetManaRegen's rate isn't plain regen

local runs = { rest = {}, casting = {} } -- per kind, the run going on: { started, last, gained, ticks }
local results = {}      -- per kind: { rate = mana per second, ticks, seconds, at }
local lastMana, lastSpend = nil, -FIVE_SECOND_RULE
local castingGain = false

local function Expected(kind)
    if not GetManaRegen then return nil end
    local ok, base, casting = pcall(GetManaRegen)
    if not ok or issecret(base) or issecret(casting) then return nil end
    return kind == "rest" and base or casting
end

local function Finish(kind)
    local run = runs[kind]
    if run.ticks and run.ticks >= MIN_TICKS and run.last > run.started then
        local seconds = run.last - run.started
        local rate = run.gained / seconds
        local expected = Expected(kind)
        if not (expected and expected > 0 and rate > expected * OUTLIER) then
            results[kind] = { rate = rate, ticks = run.ticks, seconds = seconds, at = GetTime() }
        end
    end
    runs[kind] = {}
end

local function OnMana()
    local mana, max = UnitPower("player", 0), UnitPowerMax("player", 0)
    if issecret(mana) or issecret(max) or not max or max <= 0 then
        lastMana = nil
        return
    end
    local now = GetTime()
    if lastMana then
        if mana < lastMana then
            lastSpend = now
            castingGain = false
            Finish("rest")
            Finish("casting")
        elseif mana > lastMana then
            local kind = (now - lastSpend >= FIVE_SECOND_RULE) and "rest" or "casting"
            Finish(kind == "rest" and "casting" or "rest")
            if kind == "casting" then
                castingGain = true
            elseif not castingGain and lastSpend > 0 then
                -- A whole five seconds after spending went by with nothing coming back.
                results.castingNone = now
                castingGain = true
            end
            if mana >= max then
                Finish(kind)
            else
                local run = runs[kind]
                if not run.started then
                    run.started, run.last, run.gained, run.ticks = now, now, 0, 1
                else
                    run.gained, run.last, run.ticks = run.gained + (mana - lastMana), now, run.ticks + 1
                end
            end
        end
    end
    lastMana = mana
end

-- The best reading of a kind: the run going on if it's long enough, else the last one.
function Regen:Rate(kind)
    local run = runs[kind]
    if run.ticks and run.ticks >= MIN_TICKS + 2 and run.last > run.started then
        return run.gained / (run.last - run.started), run.ticks, run.last - run.started
    end
    local result = results[kind]
    if result then return result.rate, result.ticks, result.seconds end
end

-- True when mana was spent and nothing came back during the following five seconds.
function Regen:NoneWhileCasting()
    return results.castingNone ~= nil and not results.casting
end

function Regen:Snapshot()
    return { results = results, runs = runs, expectedRest = Expected("rest"), expectedCasting = Expected("casting") }
end

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:SetScript("OnEvent", function(_, _, _, powerType)
    if powerType == "MANA" then OnMana() end
end)
