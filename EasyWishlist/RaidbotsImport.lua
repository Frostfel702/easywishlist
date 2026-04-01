-- EasyWishlist - RaidbotsImport.lua
-- Detects and normalises both Raidbots and QE Live compact formats.
-- Both formats share the same sources[].items structure.

-- ── Detection ─────────────────────────────────────────────────────────────

function EWL.IsRaidbotsFormat(data)
    return type(data) == "table" and data.type == "raidbots"
end

function EWL.IsQEFormat(data)
    return type(data) == "table" and data.type == "qe"
end

-- ── Shared normaliser (Raidbots and QE both use sources[].items) ──────────

local function NormalizeSources(data)
    local ufSettings = data.ufSettings or {}

    local results = {}
    if data.sources then
        for _, source in ipairs(data.sources) do
            for _, item in ipairs(source.items or {}) do
                item.sourceId   = source.sourceId
                item.sourceName = source.sourceName
                results[#results + 1] = item
            end
        end
    else
        results = data.results or {}
    end

    if not ufSettings.dungeon and not ufSettings.raid then
        local maxKey   = 0
        local raidDiffs = {}
        for _, r in ipairs(results) do
            if r.dropLoc == "Dungeon" and (r.dropDifficulty or 0) > maxKey then
                maxKey = r.dropDifficulty
            elseif r.dropLoc == "Raid" and r.dropDifficulty then
                raidDiffs[#raidDiffs + 1] = r.dropDifficulty
            end
        end
        if maxKey > 0     then ufSettings.dungeon = maxKey end
        if #raidDiffs > 0 then ufSettings.raid    = raidDiffs end
    end

    return {
        playername  = data.playername or "Unknown",
        realm       = data.realm or "",
        spec        = data.spec or "Unknown",
        contentType = data.contentType or "Dungeon",
        dateCreated = data.date or data.dateCreated or "",
        gameType    = "Retail",
        ufSettings  = ufSettings,
        results     = results,
    }
end

function EWL.NormalizeRaidbots(data)
    return NormalizeSources(data)
end

function EWL.NormalizeQE(data)
    return NormalizeSources(data)
end
