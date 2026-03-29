-- EasyWishlist - Core.lua
-- Global namespace, SavedVariables init, data model, slash commands

EWL = {}

local ADDON_NAME = "EasyWishlist"
local MAX_REPORTS = 20

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
    -- Normalize realm: remove spaces and hyphens for consistency
    realm = realm:gsub("[%s%-]", "")
    return name .. "-" .. realm
end

-- ─── Migration ────────────────────────────────────────────────────────────

-- Migrates a character's data from the old single-report format to the new
-- multi-report wrapper format. Safe to call multiple times.
local function MigrateIfNeeded(key)
    local data = EasyWishlistDB.reports[key]
    if not data then return end
    -- Old format has .results directly on the top-level table
    if data.results then
        data.title = data.spec or "Imported Report"
        EasyWishlistDB.reports[key] = {
            activeIndex = 1,
            list = { data },
        }
    end
end

-- ─── Data Access ──────────────────────────────────────────────────────────

function EWL.GetCurrentReport()
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then return nil end
    return wrapper.list[wrapper.activeIndex]
end

function EWL.GetReportList()
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then return {}, 0 end
    local out = {}
    for i, r in ipairs(wrapper.list) do
        out[i] = {
            title       = r.title or ("Report " .. i),
            spec        = r.spec,
            contentType = r.contentType,
            dateCreated = r.dateCreated,
        }
    end
    return out, wrapper.activeIndex
end

function EWL.SetActiveReport(index)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then return end
    local total = #wrapper.list
    if total == 0 then return end
    wrapper.activeIndex = math.max(1, math.min(index, total))
end

function EWL.DeleteReport(index)
    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then return end
    if #wrapper.list <= 1 then return end -- must keep at least one
    table.remove(wrapper.list, index)
    -- Clamp activeIndex so it stays valid
    wrapper.activeIndex = math.max(1, math.min(wrapper.activeIndex, #wrapper.list))
end

function EWL.SaveReport(data, title)
    -- Validate required fields
    if not data.results or type(data.results) ~= "table" then
        return false, "Missing or invalid 'results' field"
    end
    if not data.spec then
        return false, "Missing 'spec' field"
    end
    if not data.playername then
        return false, "Missing 'playername' field"
    end
    -- realm is optional (Raidbots exports don't include it)
    if data.realm == nil then
        data.realm = ""
    end
    if #data.results == 0 then
        return false, "Results list is empty"
    end

    -- Filter out zero-score items and sort descending by percDiff
    local results = {}
    for _, r in ipairs(data.results) do
        if r.percDiff and r.percDiff > 0 and r.item then
            results[#results + 1] = r
        end
    end
    table.sort(results, function(a, b)
        return (a.percDiff or 0) > (b.percDiff or 0)
    end)

    if not title or title:match("^%s*$") then
        local ct = data.contentType or ""
        title = (data.spec or "Report") .. (ct ~= "" and (" - " .. ct) or "")
    end

    local entry = {
        title       = title,
        id          = data.id,
        dateCreated = data.dateCreated,
        playername  = data.playername,
        realm       = data.realm,
        spec        = data.spec,
        contentType = data.contentType,
        ufSettings  = data.ufSettings,
        gameType    = data.gameType,
        results     = results,
    }

    local key = EWL.GetCharacterKey()
    MigrateIfNeeded(key)
    local wrapper = EasyWishlistDB.reports[key]
    if not wrapper then
        wrapper = { activeIndex = 1, list = {} }
        EasyWishlistDB.reports[key] = wrapper
    end

    -- Cap at MAX_REPORTS: drop the oldest entry if full
    if #wrapper.list >= MAX_REPORTS then
        table.remove(wrapper.list, 1)
    end

    wrapper.list[#wrapper.list + 1] = entry
    wrapper.activeIndex = #wrapper.list

    return true
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
