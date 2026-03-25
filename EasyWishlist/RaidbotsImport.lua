-- EasyWishlist - RaidbotsImport.lua
-- Detects and normalises the compact Raidbots Droptimizer format
-- produced by the EasyWishlist web extractor tool.

-- ── Detection ─────────────────────────────────────────────────────────────

function EWL.IsRaidbotsFormat(data)
    return type(data) == "table" and data.type == "raidbots"
end

-- ── Normalise to SaveReport-compatible structure ───────────────────────────

function EWL.NormalizeRaidbots(data)
    -- Infer ufSettings for the header difficulty label
    local ufSettings = data.ufSettings or {}
    if not ufSettings.dungeon and not ufSettings.raid then
        -- Fall back: scan results to find the highest key level
        local maxKey = 0
        local raidDiffs = {}
        for _, r in ipairs(data.results or {}) do
            if r.dropLoc == "Dungeon" and (r.dropDifficulty or 0) > maxKey then
                maxKey = r.dropDifficulty
            elseif r.dropLoc == "Raid" and r.dropDifficulty then
                raidDiffs[#raidDiffs + 1] = r.dropDifficulty
            end
        end
        if maxKey > 0  then ufSettings.dungeon = maxKey end
        if #raidDiffs > 0 then ufSettings.raid = raidDiffs end
    end

    return {
        playername  = data.playername or "Unknown",
        realm       = "",   -- Raidbots exports don't include realm; saved under current character
        spec        = data.spec or "Unknown",
        contentType = data.contentType or "Dungeon",
        dateCreated = data.date or "",
        gameType    = "Retail",
        ufSettings  = ufSettings,
        results     = data.results or {},
    }
end
