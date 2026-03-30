-- EasyWishlist - RaidbotsImport.lua
-- Detects and normalises the compact Raidbots Droptimizer format
-- produced by the EasyWishlist web extractor tool.

-- ── Detection ─────────────────────────────────────────────────────────────

function EWL.IsRaidbotsFormat(data)
    return type(data) == "table" and data.type == "raidbots"
end

-- ── Normalise to SaveReport-compatible structure ───────────────────────────

function EWL.NormalizeRaidbots(data)
    local ufSettings = data.ufSettings or {}

    -- Flatten sources[*].items into a single results list, stamping sourceId onto each item.
    -- Falls back to the old flat data.results field for backward compat.
    local results = {}
    if data.sources then
        for _, source in ipairs(data.sources) do
            for _, item in ipairs(source.items or {}) do
                item.sourceId   = source.sourceId
                item.sourceName = source.sourceName  -- authoritative name from the group
                results[#results + 1] = item
            end
        end
    else
        results = data.results or {}
    end

    -- If ufSettings has no difficulty hint, infer from items
    if not ufSettings.dungeon and not ufSettings.raid then
        local maxKey = 0
        local raidDiffs = {}
        for _, r in ipairs(results) do
            if r.dropLoc == "Dungeon" and (r.dropDifficulty or 0) > maxKey then
                maxKey = r.dropDifficulty
            elseif r.dropLoc == "Raid" and r.dropDifficulty then
                raidDiffs[#raidDiffs + 1] = r.dropDifficulty
            end
        end
        if maxKey > 0    then ufSettings.dungeon = maxKey end
        if #raidDiffs > 0 then ufSettings.raid   = raidDiffs end
    end

    return {
        playername  = data.playername or "Unknown",
        realm       = "",   -- Raidbots exports don't include realm; saved under current character
        spec        = data.spec or "Unknown",
        contentType = data.contentType or "Dungeon",
        dateCreated = data.date or "",
        gameType    = "Retail",
        ufSettings  = ufSettings,
        results     = results,
    }
end
