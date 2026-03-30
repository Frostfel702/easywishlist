-- EasyWishlist - Core.lua
-- Global namespace, SavedVariables init, data model, slash commands

EWL = {}

local ADDON_NAME = "EasyWishlist"

-- ─── SavedVariables Init ───────────────────────────────────────────────────

local function InitDB()
    if not EasyWishlistDB then
        EasyWishlistDB = {}
    end
    if not EasyWishlistDB.reports then
        EasyWishlistDB.reports = {}
    end
    if not EasyWishlistDB.minimapPos then
        EasyWishlistDB.minimapPos = { angle = 225 }
    end
end

-- ─── Character Key ────────────────────────────────────────────────────────

function EWL.GetCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    realm = realm:gsub("[%s%-]", "")
    return name .. "-" .. realm
end

-- ─── Migration ────────────────────────────────────────────────────────────

-- Handles both old formats:
--   v1: reports[key] = { results, spec, ... }       (single report directly)
--   v2: reports[key] = { activeIndex, list = {...} } (previous multi-report attempt)
-- Both are migrated into v3: { activeSpec, bySpec = { [spec] = { spec, lastUpdated, results } } }
local function MigrateIfNeeded(key)
    local data = EasyWishlistDB.reports[key]
    if not data then return end
    if data.bySpec then return end  -- already v3

    local report
    if data.results then
        -- v1
        report = data
    elseif data.list and data.list[1] then
        -- v2: use the active entry or first
        report = data.list[data.activeIndex or 1]
    end

    if report and report.spec then
        local spec = report.spec
        EasyWishlistDB.reports[key] = {
            activeSpec = spec,
            bySpec = {
                [spec] = {
                    spec        = spec,
                    lastUpdated = report.dateCreated or "",
                    results     = report.results or {},
                }
            }
        }
    else
        EasyWishlistDB.reports[key] = nil
    end
end

-- ─── Data Access ──────────────────────────────────────────────────────────

function EWL.GetCurrentReport()
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.activeSpec then return nil end
    return wrapper.bySpec[wrapper.activeSpec]
end

-- Returns sorted list of spec names and the currently active spec name.
function EWL.GetSpecList()
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.bySpec then return {}, nil end
    local specs = {}
    for specName in pairs(wrapper.bySpec) do
        specs[#specs + 1] = specName
    end
    table.sort(specs)
    return specs, wrapper.activeSpec
end

function EWL.SetActiveSpec(spec)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.bySpec[spec] then return end
    wrapper.activeSpec = spec
end

function EWL.DeleteSpec(spec)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.bySpec then return end
    local count = 0
    for _ in pairs(wrapper.bySpec) do count = count + 1 end
    if count <= 1 then return end
    wrapper.bySpec[spec] = nil
    if wrapper.activeSpec == spec then
        local remaining = {}
        for s in pairs(wrapper.bySpec) do remaining[#remaining + 1] = s end
        table.sort(remaining)
        wrapper.activeSpec = remaining[1]
    end
end

function EWL.SaveReport(data)
    if not data.results or type(data.results) ~= "table" then
        return false, "Missing or invalid 'results' field"
    end
    if not data.spec then
        return false, "Missing 'spec' field"
    end
    if not data.playername then
        return false, "Missing 'playername' field"
    end
    if data.realm == nil then
        data.realm = ""
    end
    if #data.results == 0 then
        return false, "Results list is empty"
    end

    -- Filter zero-or-negative upgrades
    local newResults = {}
    for _, r in ipairs(data.results) do
        if r.percDiff and r.percDiff > 0 and r.item then
            newResults[#newResults + 1] = r
        end
    end

    local spec = data.spec
    local key  = EWL.GetCharacterKey()
    MigrateIfNeeded(key)

    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then
        wrapper = { activeSpec = spec, bySpec = {} }
        EasyWishlistDB.reports[key] = wrapper
    end

    -- Get or create spec bucket
    if not wrapper.bySpec[spec] then
        wrapper.bySpec[spec] = { spec = spec, lastUpdated = "", results = {} }
    end
    local bucket = wrapper.bySpec[spec]

    -- Collect the set of sourceIds and item IDs present in the incoming data
    local incomingSourceIds = {}
    local incomingItemIds   = {}
    for _, r in ipairs(newResults) do
        if r.sourceId then
            incomingSourceIds[r.sourceId] = true
        end
        incomingItemIds[r.item] = true
    end

    if next(incomingSourceIds) then
        -- Source-replacement: drop existing items that match an incoming sourceId OR an
        -- incoming itemID (the itemID check handles old-format items that have no sourceId).
        local kept = {}
        for _, r in ipairs(bucket.results) do
            local drop = (r.sourceId and incomingSourceIds[r.sourceId]) or incomingItemIds[r.item]
            if not drop then
                kept[#kept + 1] = r
            end
        end
        for _, r in ipairs(newResults) do
            kept[#kept + 1] = r
        end
        bucket.results = kept
    else
        -- Legacy merge: update existing item by itemID or append
        local byItemID = {}
        for i, r in ipairs(bucket.results) do
            byItemID[r.item] = i
        end
        for _, r in ipairs(newResults) do
            local idx = byItemID[r.item]
            if idx then
                bucket.results[idx] = r
            else
                bucket.results[#bucket.results + 1] = r
                byItemID[r.item] = #bucket.results
            end
        end
    end

    -- Re-sort descending by percDiff
    table.sort(bucket.results, function(a, b)
        return (a.percDiff or 0) > (b.percDiff or 0)
    end)

    bucket.lastUpdated = data.dateCreated or ""
    wrapper.activeSpec  = spec

    return true
end

-- ─── Item Upgrade Lookup ──────────────────────────────────────────────────

function EWL.GetItemUpgrade(itemID)
    local report = EWL.GetCurrentReport()
    if not report or not report.results then return nil end
    for _, r in ipairs(report.results) do
        if r.item == itemID then
            return r.percDiff
        end
    end
    return nil
end

-- ─── Difficulty Label ─────────────────────────────────────────────────────

function EWL.GetDifficultyLabel(report)
    if not report or not report.ufSettings then return "" end
    local ct = report.contentType
    if ct == "Dungeon" then
        return "Mythic+"
    elseif ct == "Raid" then
        local raid = report.ufSettings.raid
        if type(raid) == "table" then
            local labels = { [0]="LFR", [1]="LFR", [2]="Normal", [3]="Normal", [4]="Heroic", [5]="Heroic", [6]="Mythic", [7]="Mythic" }
            local parts = {}
            for _, v in ipairs(raid) do
                parts[#parts + 1] = labels[v] or ("Diff " .. v)
            end
            return table.concat(parts, "/")
        end
        return "Raid"
    end
    return ct or ""
end

-- ─── ADDON_LOADED ─────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        -- Character name/realm are available after PLAYER_LOGIN
        -- Nothing to do here for now
    end
end)

-- ─── Slash Commands ───────────────────────────────────────────────────────

SLASH_EASYWISHLIST1 = "/ewl"
SLASH_EASYWISHLIST2 = "/easywishlist"
SlashCmdList["EASYWISHLIST"] = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if msg == "import" then
        EWL.OpenImportDialog()
    else
        EWL.ToggleMainWindow()
    end
end
