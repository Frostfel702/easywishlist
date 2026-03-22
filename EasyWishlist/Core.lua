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
    -- Normalize realm: remove spaces and hyphens for consistency
    realm = realm:gsub("[%s%-]", "")
    return name .. "-" .. realm
end

-- ─── Data Access ──────────────────────────────────────────────────────────

function EWL.GetCurrentReport()
    local key = EWL.GetCharacterKey()
    return EasyWishlistDB.reports[key]
end

function EWL.SaveReport(data)
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
    if not data.realm then
        return false, "Missing 'realm' field"
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

    local key = EWL.GetCharacterKey()
    EasyWishlistDB.reports[key] = {
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

    return true
end

-- ─── Difficulty Label ─────────────────────────────────────────────────────

function EWL.GetDifficultyLabel(report)
    if not report or not report.ufSettings then return "" end
    local ct = report.contentType
    if ct == "Dungeon" then
        return "M+" .. (report.ufSettings.dungeon or "?")
    elseif ct == "Raid" then
        local raid = report.ufSettings.raid
        if type(raid) == "table" then
            local labels = { [4] = "Normal", [5] = "Heroic", [6] = "Mythic" }
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
