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
    if not EasyWishlistDB.migrationWarningShown then
        EasyWishlistDB.migrationWarningShown = {}
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

-- Handles all legacy formats and migrates to v4:
--   v1: reports[key] = { results, spec, ... }
--   v2: reports[key] = { activeIndex, list = {...} }
--   v3: reports[key] = { activeSpec, bySpec = { [spec] = { spec, lastUpdated, results } } }
-- Target v4: { activeWishlist, byWishlist = { [name] = { lastUpdated, results, dungeonImports } } }
local function MigrateIfNeeded(key)
    local data = EasyWishlistDB.reports[key]
    if not data then return end
    if data.byWishlist then return end  -- already v4

    -- v3 → v4: rename bySpec to byWishlist, backfill dungeonImports from results
    if data.bySpec then
        local byWishlist = {}
        for specName, bucket in pairs(data.bySpec) do
            local dungeonImports = {}
            for _, r in ipairs(bucket.results or {}) do
                local src = r.sourceName or r.dropLoc or "Unknown"
                if not dungeonImports[src] then
                    dungeonImports[src] = bucket.lastUpdated or ""
                end
            end
            byWishlist[specName] = {
                lastUpdated    = bucket.lastUpdated or "",
                results        = bucket.results or {},
                dungeonImports = dungeonImports,
            }
        end
        EasyWishlistDB.reports[key] = {
            activeWishlist = data.activeSpec or next(byWishlist),
            byWishlist     = byWishlist,
        }
        return
    end

    -- v1/v2 → v4
    local report
    if data.results then
        report = data
    elseif data.list and data.list[1] then
        report = data.list[data.activeIndex or 1]
    end

    if report and report.spec then
        local spec = report.spec
        local dungeonImports = {}
        for _, r in ipairs(report.results or {}) do
            local src = r.sourceName or r.dropLoc or "Unknown"
            if not dungeonImports[src] then
                dungeonImports[src] = report.dateCreated or ""
            end
        end
        EasyWishlistDB.reports[key] = {
            activeWishlist = spec,
            byWishlist = {
                [spec] = {
                    lastUpdated    = report.dateCreated or "",
                    results        = report.results or {},
                    dungeonImports = dungeonImports,
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
    if not wrapper or not wrapper.activeWishlist then return nil end
    return wrapper.byWishlist[wrapper.activeWishlist]
end

-- Returns sorted list of wishlist names and the currently active one.
function EWL.GetWishlists()
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return {}, nil end
    local names = {}
    for name in pairs(wrapper.byWishlist) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names, wrapper.activeWishlist
end

function EWL.SetActiveWishlist(name)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist[name] then return end
    wrapper.activeWishlist = name
end

function EWL.DeleteWishlist(name)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return end
    local count = 0
    for _ in pairs(wrapper.byWishlist) do count = count + 1 end
    if count <= 1 then return end
    wrapper.byWishlist[name] = nil
    if wrapper.activeWishlist == name then
        local remaining = {}
        for n in pairs(wrapper.byWishlist) do remaining[#remaining + 1] = n end
        table.sort(remaining)
        wrapper.activeWishlist = remaining[1]
    end
end

-- Returns sorted list of {name, lastUpdated} for dungeons imported into the current wishlist.
-- Also lazily backfills dungeonImports for reports migrated before this field existed.
function EWL.GetDungeonList()
    local report = EWL.GetCurrentReport()
    if not report then return {} end

    if not report.dungeonImports then
        report.dungeonImports = {}
    end

    -- Backfill: if dungeonImports is empty but results exist, derive entries from results
    if not next(report.dungeonImports) and report.results and #report.results > 0 then
        for _, r in ipairs(report.results) do
            local src = r.sourceName or r.dropLoc or "Unknown"
            if not report.dungeonImports[src] then
                report.dungeonImports[src] = report.lastUpdated or ""
            end
        end
    end

    local list = {}
    for name, date in pairs(report.dungeonImports) do
        list[#list + 1] = { name = name, lastUpdated = date }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Removes a dungeon's items from the current wishlist and its import tracking entry.
function EWL.DeleteDungeon(sourceName)
    local report = EWL.GetCurrentReport()
    if not report then return end
    if report.results then
        local kept = {}
        for _, r in ipairs(report.results) do
            if (r.sourceName or r.dropLoc or "Unknown") ~= sourceName then
                kept[#kept + 1] = r
            end
        end
        report.results = kept
    end
    if report.dungeonImports then
        report.dungeonImports[sourceName] = nil
    end
end

function EWL.SaveReport(data, wishlistName)
    if not wishlistName or wishlistName:match("^%s*$") then
        return false, "Wishlist name is required"
    end
    if not data.results or type(data.results) ~= "table" then
        return false, "Missing or invalid 'results' field"
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

    local charName = (data.playername and data.playername ~= "" and data.playername ~= "Unknown")
        and data.playername or UnitName("player")
    local realmStr = (data.realm and data.realm ~= "") and data.realm or GetRealmName()
    local charRealm = realmStr:gsub("[%s%-]", "")
    local key = charName .. "-" .. charRealm
    MigrateIfNeeded(key)

    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then
        wrapper = { activeWishlist = wishlistName, byWishlist = {} }
        EasyWishlistDB.reports[key] = wrapper
    end

    if not wrapper.byWishlist[wishlistName] then
        wrapper.byWishlist[wishlistName] = { lastUpdated = "", results = {}, dungeonImports = {} }
    end
    local bucket = wrapper.byWishlist[wishlistName]
    if not bucket.dungeonImports then bucket.dungeonImports = {} end
    bucket.playername = charName
    bucket.realm      = charRealm

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
        -- Source-replacement: drop existing items that match an incoming sourceId OR itemID
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

    -- Track dungeon import timestamps per sourceName
    local importDate = data.dateCreated or ""
    for _, r in ipairs(newResults) do
        local src = r.sourceName or r.dropLoc or "Unknown"
        if importDate ~= "" or not bucket.dungeonImports[src] then
            bucket.dungeonImports[src] = importDate ~= "" and importDate or "imported"
        end
    end

    bucket.lastUpdated = importDate
    wrapper.activeWishlist = wishlistName

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

-- Returns {name, pct} for every wishlist that contains itemID, sorted by pct desc.
function EWL.GetItemUpgradeAllWishlists(itemID)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return {} end
    local results = {}
    for name, bucket in pairs(wrapper.byWishlist) do
        if bucket.results then
            for _, r in ipairs(bucket.results) do
                if r.item == itemID then
                    results[#results + 1] = { name = name, pct = r.percDiff }
                    break
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.pct > b.pct end)
    return results
end

-- ─── Cross-character Data Access ──────────────────────────────────────────

-- Returns all character keys that have stored data, sorted.
function EWL.GetAllCharacterKeys()
    local keys = {}
    for k in pairs(EasyWishlistDB.reports or {}) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- Returns sorted wishlist names and active one for any character key.
function EWL.GetWishlistsForKey(key)
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return {}, nil end
    local names = {}
    for name in pairs(wrapper.byWishlist) do names[#names + 1] = name end
    table.sort(names)
    return names, wrapper.activeWishlist
end

-- Returns the active report for any character key.
function EWL.GetReportForKey(key)
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.activeWishlist then return nil end
    return wrapper.byWishlist[wrapper.activeWishlist]
end

-- Returns dungeon list for any character key.
function EWL.GetDungeonListForKey(key)
    local report = EWL.GetReportForKey(key)
    if not report then return {} end
    if not report.dungeonImports then report.dungeonImports = {} end
    if not next(report.dungeonImports) and report.results and #report.results > 0 then
        for _, r in ipairs(report.results) do
            local src = r.sourceName or r.dropLoc or "Unknown"
            if not report.dungeonImports[src] then
                report.dungeonImports[src] = report.lastUpdated or ""
            end
        end
    end
    local list = {}
    for name, date in pairs(report.dungeonImports) do
        list[#list + 1] = { name = name, lastUpdated = date }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Sets active wishlist for any character key.
function EWL.SetActiveWishlistForKey(key, name)
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist[name] then return end
    wrapper.activeWishlist = name
end

-- Deletes a wishlist for any character key.
-- If it was the last wishlist, removes the character entry entirely.
function EWL.DeleteWishlistForKey(key, name)
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return end
    wrapper.byWishlist[name] = nil
    if not next(wrapper.byWishlist) then
        EasyWishlistDB.reports[key] = nil
        return
    end
    if wrapper.activeWishlist == name then
        local remaining = {}
        for n in pairs(wrapper.byWishlist) do remaining[#remaining + 1] = n end
        table.sort(remaining)
        wrapper.activeWishlist = remaining[1]
    end
end

-- Removes a dungeon's items from any character key's active wishlist.
function EWL.DeleteDungeonForKey(key, sourceName)
    local report = EWL.GetReportForKey(key)
    if not report then return end
    if report.results then
        local kept = {}
        for _, r in ipairs(report.results) do
            if (r.sourceName or r.dropLoc or "Unknown") ~= sourceName then
                kept[#kept + 1] = r
            end
        end
        report.results = kept
    end
    if report.dungeonImports then
        report.dungeonImports[sourceName] = nil
    end
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

-- ─── Migration Warning ────────────────────────────────────────────────────

local function CheckMisplacedWishlists()
    local key = EWL.GetCharacterKey()
    if EasyWishlistDB.migrationWarningShown[key] then return end
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper or not wrapper.byWishlist then return end
    local charName = UnitName("player")
    local hasIssue = false
    for _, bucket in pairs(wrapper.byWishlist) do
        if not bucket.playername or bucket.playername ~= charName then
            hasIssue = true
            break
        end
    end
    if hasIssue then
        EasyWishlistDB.migrationWarningShown[key] = true
        print("|cff00ff96EasyWishlist:|r |cffff6600Warning:|r Some wishlists could not be verified as belonging to this character. Please re-import them to ensure correct data.")
    end
end

-- ─── ADDON_LOADED ─────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        CheckMisplacedWishlists()
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
