-- EasyWishlist - UI.lua
-- Main window: sidebar, item list, tooltips

-- ─── Layout constants ─────────────────────────────────────────────────────

local WINDOW_W  = 730
local WINDOW_H  = 464
local SIDEBAR_W = 180
local RP_X      = 204   -- right panel x offset from window left (14 + SIDEBAR_W + 10)
local RP_W      = 510   -- right panel width (WINDOW_W - RP_X - 16)
local ROW_H     = 32
local HEADER_H  = 22
local ICON_SIZE = 24
local DROW_H    = 40    -- dungeon sidebar row height
local COL = {
    rank   = { x = 14,  w = 24  },
    icon   = { x = 42,  w = 26  },
    name   = { x = 72,  w = 200 },
    ilvl   = { x = 276, w = 40  },
    pct    = { x = 320, w = 52  },
    source = { x = 376, w = 110 },
}

local mainWindow
local rowPool         = {}
local activeRows      = {}
local groupHdrPool    = {}
local activeGroupHdrs = {}

-- ─── State ───────────────────────────────────────────────────────────────

local groupMode      = "none"   -- "none" | "source" | "slot" | "boss"
local dungeonFilter  = nil      -- sourceName string or nil
local viewingCharKey = nil      -- nil = current logged-in character

local function GetViewKey()
    return viewingCharKey or EWL.GetCharacterKey()
end
local slotCache         = {}   -- itemID -> display slot name
local statCache         = {}   -- itemID -> { statKey=true, ... }
local pendingStats      = {}   -- itemID -> ilvl awaiting ITEM_DATA_LOAD_RESULT for stat caching
local activeStatFilters = {}   -- statKey -> true (AND logic)
local statFilterBtns    = {}

local STAT_DEFS = {
    { key = "ITEM_MOD_HASTE_RATING",      label = "Haste"   },
    { key = "ITEM_MOD_MASTERY_RATING",    label = "Mastery" },
    { key = "ITEM_MOD_CRIT_STRIKE_RATING", label = "Crit"   },
    { key = "ITEM_MOD_VERSATILITY",       label = "Vers"    },
}

local SLOT_FROM_SIM = {
    head="Head", neck="Neck", shoulder="Shoulders", back="Back",
    chest="Chest", wrist="Wrists", hands="Hands", waist="Waist",
    legs="Legs", feet="Feet",
    finger="Finger", finger1="Finger", finger2="Finger",
    trinket="Trinket", trinket1="Trinket", trinket2="Trinket",
    mainhand="Weapon", offhand="Off Hand",
}

local SLOT_FROM_INVTYPE = {
    INVTYPE_HEAD="Head",      INVTYPE_NECK="Neck",       INVTYPE_SHOULDER="Shoulders",
    INVTYPE_CHEST="Chest",    INVTYPE_ROBE="Chest",      INVTYPE_WAIST="Waist",
    INVTYPE_LEGS="Legs",      INVTYPE_FEET="Feet",       INVTYPE_WRIST="Wrists",
    INVTYPE_HAND="Hands",     INVTYPE_FINGER="Finger",   INVTYPE_TRINKET="Trinket",
    INVTYPE_BACK="Back",      INVTYPE_CLOAK="Back",
    INVTYPE_WEAPON="Weapon",  INVTYPE_2HWEAPON="Two-Hand",
    INVTYPE_WEAPONMAINHAND="Weapon", INVTYPE_WEAPONOFFHAND="Off Hand",
    INVTYPE_SHIELD="Off Hand", INVTYPE_RANGED="Ranged",
}

local SLOT_ORDER = {
    "Head","Neck","Shoulders","Back","Chest","Wrists",
    "Hands","Waist","Legs","Feet","Finger","Trinket",
    "Weapon","Two-Hand","Off Hand","Ranged","Other",
}

local function GetItemSlot(result)
    if slotCache[result.item] then return slotCache[result.item] end
    if result.slot then
        local s = SLOT_FROM_SIM[result.slot:lower()]
        if s then slotCache[result.item] = s; return s end
    end
    local _, _, _, _, _, _, _, _, invType = C_Item.GetItemInfo(result.item)
    if invType and invType ~= "" then
        local s = SLOT_FROM_INVTYPE[invType] or invType
        slotCache[result.item] = s
        return s
    end
    return nil
end

-- ─── Colour helpers ──────────────────────────────────────────────────────

local function QualityColor(quality)
    local r, g, b = GetItemQualityColor(quality or 1)
    return r, g, b
end

local function PctColor(pct)
    if pct >= 1.0 then return 0.0, 1.0, 0.4
    elseif pct >= 0.5 then return 1.0, 0.85, 0.0
    else return 0.8, 0.8, 0.8 end
end

-- ─── Group header pool ───────────────────────────────────────────────────

local function GetGroupHdr(parent)
    local h = table.remove(groupHdrPool)
    if h then h:SetParent(parent); h:Show(); return h end

    h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HEADER_H)

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 0.82, 0, 0.07)

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.25)

    local lbl = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 10, 0)
    lbl:SetTextColor(1, 0.82, 0)
    h.lbl = lbl

    local count = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("RIGHT", -10, 0)
    count:SetTextColor(0.55, 0.55, 0.55)
    h.count = count

    return h
end

local function ReleaseGroupHdr(h)
    h:Hide()
    h:SetParent(nil)
    groupHdrPool[#groupHdrPool + 1] = h
end

-- ─── Row pool ────────────────────────────────────────────────────────────

local function GetRow(parent)
    local row = table.remove(rowPool)
    if row then row:SetParent(parent); row:Show(); return row end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("LEFT", COL.rank.x, 0)
    rankText:SetWidth(COL.rank.w)
    rankText:SetJustifyH("RIGHT")
    rankText:SetTextColor(0.6, 0.6, 0.6)
    row.rankText = rankText

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", COL.icon.x, 0)
    row.icon = icon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", COL.name.x, 0)
    nameText:SetWidth(COL.name.w)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlText:SetPoint("LEFT", COL.ilvl.x, 0)
    ilvlText:SetWidth(COL.ilvl.w)
    ilvlText:SetJustifyH("CENTER")
    ilvlText:SetTextColor(0.7, 0.9, 1)
    row.ilvlText = ilvlText

    local pctText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctText:SetPoint("LEFT", COL.pct.x, 0)
    pctText:SetWidth(COL.pct.w)
    pctText:SetJustifyH("CENTER")
    row.pctText = pctText

    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("LEFT", COL.source.x, 0)
    sourceText:SetWidth(COL.source.w)
    sourceText:SetJustifyH("LEFT")
    sourceText:SetTextColor(0.7, 0.7, 0.7)
    row.sourceText = sourceText

    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ilvl = self.result and self.result.level
            if ilvl then
                GameTooltip:SetItemKey(self.itemID, ilvl, 0)
            else
                GameTooltip:SetItemByID(self.itemID)
            end
            if self.result then
                local r = self.result
                local pctR, pctG, pctB = PctColor(r.percDiff or 0)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(
                    "Upgrade:",
                    string.format("+%.2f%%", r.percDiff or 0),
                    pctR, pctG, pctB,
                    pctR, pctG, pctB
                )
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:SetParent(nil)
    row.itemID = nil
    rowPool[#rowPool + 1] = row
end

-- ─── Populate a row ──────────────────────────────────────────────────────

local pendingItems = {}

local function PopulateRow(row, result, rank, isEven)
    row.itemID  = result.item
    row.result  = result
    row.rank    = rank
    row.isEven  = isEven
    row:SetWidth(RP_W - 14)

    if isEven then
        row.bg:SetColorTexture(1, 1, 1, 0.04)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    row.rankText:SetText(rank)

    local name, _, quality, _, _, _, _, _, invType, texture = C_Item.GetItemInfo(result.item)
    if name then
        local r, g, b = QualityColor(quality)
        row.nameText:SetText(name)
        row.nameText:SetTextColor(r, g, b)
        row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        if invType and invType ~= "" and not slotCache[result.item] then
            slotCache[result.item] = SLOT_FROM_INVTYPE[invType] or invType
        end
    else
        row.nameText:SetText("|cff888888Loading...|r")
        row.nameText:SetTextColor(0.5, 0.5, 0.5)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        C_Item.RequestLoadItemDataByID(result.item)
        pendingItems[result.item] = true
    end

    row.ilvlText:SetText(result.level or "?")

    local pct = result.percDiff or 0
    local r, g, b = PctColor(pct)
    row.pctText:SetText(string.format("+%.2f%%", pct))
    row.pctText:SetTextColor(r, g, b)

    local locLabel = result.sourceName or result.dropLoc or "?"
    local diffLabel = ""
    if result.dropLoc == "Dungeon" and locLabel ~= "Mythic+" then
        diffLabel = " Mythic+"
    elseif result.dropLoc == "Raid" and result.dropDifficulty then
        local diffNames = { [0]="LFR",[1]="LFR",[2]="Normal",[3]="Normal",[4]="Heroic",[5]="Heroic",[6]="Mythic",[7]="Mythic" }
        diffLabel = " " .. (diffNames[result.dropDifficulty] or "")
    end
    row.sourceText:SetText(locLabel .. diffLabel)
end

-- ─── Build display list (flat or grouped) ────────────────────────────────

local function SourceKey(result)
    local name = result.sourceName or result.dropLoc or "Unknown"
    if result.dropLoc == "Dungeon" and name ~= "Mythic+" then
        return name .. " Mythic+"
    elseif result.dropLoc == "Raid" and result.dropDifficulty then
        local diffNames = { [0]="LFR",[1]="LFR",[2]="Normal",[3]="Normal",[4]="Heroic",[5]="Heroic",[6]="Mythic",[7]="Mythic" }
        local diff = diffNames[result.dropDifficulty]
        return diff and (name .. " " .. diff) or name
    end
    return name
end

local function BossKey(result)
    if result.dropBoss and result.dropBoss ~= "" then
        return result.dropBoss
    end
    return result.sourceName or result.dropLoc or "Unknown"
end

local function BuildDisplayList(results)
    if groupMode == "none" then
        local list = {}
        for i, r in ipairs(results) do
            list[#list + 1] = { type = "item", result = r, rank = i, isEven = (i % 2 == 0) }
        end
        return list
    end

    local groupMap   = {}
    local groupOrder = {}

    for i, r in ipairs(results) do
        local key = (groupMode == "source") and SourceKey(r)
                 or (groupMode == "boss")   and BossKey(r)
                 or (GetItemSlot(r) or "Other")
        if not groupMap[key] then
            groupMap[key] = {}
            groupOrder[#groupOrder + 1] = key
        end
        local g = groupMap[key]
        g[#g + 1] = { result = r, rank = i }
    end

    if groupMode == "slot" then
        local orderMap = {}
        for i, s in ipairs(SLOT_ORDER) do orderMap[s] = i end
        table.sort(groupOrder, function(a, b)
            return (orderMap[a] or 99) < (orderMap[b] or 99)
        end)
    else
        table.sort(groupOrder)
    end

    local list = {}
    for _, key in ipairs(groupOrder) do
        local g = groupMap[key]
        list[#list + 1] = { type = "header", label = key, count = #g }
        for j, entry in ipairs(g) do
            list[#list + 1] = { type = "item", result = entry.result, rank = entry.rank, isEven = (j % 2 == 0) }
        end
    end
    return list
end

-- ─── Column headers ──────────────────────────────────────────────────────

local function CreateHeaders(parent)
    local headerData = {
        { x = COL.rank.x,   w = COL.rank.w,   label = "#",       align = "RIGHT"  },
        { x = COL.name.x,   w = COL.name.w,   label = "Item",    align = "LEFT"   },
        { x = COL.ilvl.x,   w = COL.ilvl.w,   label = "ilvl",    align = "CENTER" },
        { x = COL.pct.x,    w = COL.pct.w,    label = "Upgrade", align = "CENTER" },
        { x = COL.source.x, w = COL.source.w, label = "Source",  align = "LEFT"   },
    }
    for _, h in ipairs(headerData) do
        local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOPLEFT", h.x, 0)
        t:SetWidth(h.w)
        t:SetJustifyH(h.align)
        t:SetText(h.label)
        t:SetTextColor(1, 0.82, 0)
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 10, -16)
    line:SetPoint("TOPRIGHT", -10, -16)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)
end

-- ─── Empty state ─────────────────────────────────────────────────────────

local function ShowEmptyState(contentFrame, show)
    if not contentFrame.tutorialFrame then
        local win = contentFrame.mainWin
        local rightPanel = contentFrame.rightPanel
        local f = CreateFrame("Frame", nil, win)
        -- Anchor to the scroll area within the right panel
        f:SetPoint("TOPLEFT",     rightPanel, "TOPLEFT",     14, -56)
        f:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -6,   0)
        f:SetFrameStrata("MEDIUM")
        contentFrame.tutorialFrame = f

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -14)
        title:SetText("|cff00ff96Getting Started|r")
        title:SetJustifyH("CENTER")

        local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
        subtitle:SetText("Follow these steps to import your first sim report")
        subtitle:SetJustifyH("CENTER")
        subtitle:SetTextColor(0.7, 0.7, 0.7)

        local steps = {
            { num = "1", label = "Run your sim",
              desc = "|cffffd700Raidbots:|r Run a Droptimizer sim and copy the report URL.\n|cffffd700Questionably Epic:|r Run the Upgrade Finder and copy the report URL." },
            { num = "2", label = "Process it in the EasyWishlist web app",
              desc = "Paste your report URL and generate your import string:",
              url  = "https://frostfel702.github.io/easywishlist_app/" },
            { num = "3", label = "Copy the result string",
              desc = "Copy the import string generated by the web app." },
            { num = "4", label = "Import into the addon",
              desc = "Click |cffffd700Import|r (top-right), paste the string and confirm." },
        }

        local yOffset = -20
        for _, step in ipairs(steps) do
            local numStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            numStr:SetPoint("TOPLEFT", f, "TOPLEFT", 10, yOffset)
            numStr:SetText("|cffffd700[" .. step.num .. "]|r")

            local labelStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            labelStr:SetPoint("TOPLEFT", numStr, "TOPRIGHT", 6, 0)
            labelStr:SetWidth(RP_W - 60)
            labelStr:SetText(step.label)
            labelStr:SetJustifyH("LEFT")
            labelStr:SetTextColor(1, 1, 1)

            local descStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            descStr:SetPoint("TOPLEFT", numStr, "BOTTOMLEFT", 0, -2)
            descStr:SetWidth(RP_W - 60)
            descStr:SetText(step.desc)
            descStr:SetJustifyH("LEFT")
            descStr:SetTextColor(0.7, 0.7, 0.7)

            yOffset = yOffset - 52

            if step.url then
                local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                copyBtn:SetSize(100, 22)
                copyBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, yOffset)
                copyBtn:SetText("Copy Link")
                copyBtn:SetScript("OnClick", function() EWL.OpenUrlDialog() end)
                yOffset = yOffset - 30
            end
        end
    end
    contentFrame.tutorialFrame:SetShown(show)
end

-- ─── Stat cache ──────────────────────────────────────────────────────────

local function TryCacheStats(itemID, ilvl)
    local link = string.format("item:%d:::::::::%d:0:0:0", itemID, ilvl or 0)
    local stats = C_Item.GetItemStats(link)
    if not stats or not next(stats) then
        stats = C_Item.GetItemStats("item:" .. itemID)
    end
    if not stats then return false end
    local found = {}
    for k, v in pairs(stats) do
        if v and v > 0 then found[k] = true end
    end
    statCache[itemID] = found
    return true
end

local function RefreshStatBtns()
    for _, btn in ipairs(statFilterBtns) do
        if btn.Refresh then btn.Refresh() end
    end
end

-- ─── Refresh list ────────────────────────────────────────────────────────

local function RefreshList(scrollChild)
    for _, row in ipairs(activeRows)      do ReleaseRow(row)     end
    for _, h   in ipairs(activeGroupHdrs) do ReleaseGroupHdr(h)  end
    wipe(activeRows)
    wipe(activeGroupHdrs)
    wipe(pendingItems)
    wipe(pendingStats)

    local report = EWL.GetReportForKey(GetViewKey())
    ShowEmptyState(scrollChild, not report or not report.results or #report.results == 0)
    if not report or not report.results then return end

    -- Apply dungeon filter
    local results = report.results
    if dungeonFilter then
        local filtered = {}
        for _, r in ipairs(results) do
            if (r.sourceName or r.dropLoc or "Unknown") == dungeonFilter then
                filtered[#filtered + 1] = r
            end
        end
        results = filtered
    end

    -- Request stat data for any uncached items
    for _, r in ipairs(results) do
        if not statCache[r.item] then
            pendingStats[r.item] = r.level or 0
            C_Item.RequestLoadItemDataByID(r.item)
        end
    end

    -- Apply stat filter (AND logic: item must have ALL selected stats)
    if next(activeStatFilters) then
        local filtered = {}
        for _, r in ipairs(results) do
            local itemStats = statCache[r.item]
            if itemStats then
                local match = true
                for statKey in pairs(activeStatFilters) do
                    if not itemStats[statKey] then match = false; break end
                end
                if match then filtered[#filtered + 1] = r end
            else
                -- Stats not yet loaded — include tentatively, re-filters when loaded
                filtered[#filtered + 1] = r
            end
        end
        results = filtered
    end

    local displayList = BuildDisplayList(results)

    local totalH = 0
    for _, entry in ipairs(displayList) do
        totalH = totalH + (entry.type == "header" and HEADER_H or ROW_H)
    end
    scrollChild:SetHeight(math.max(totalH, 1))

    local yOffset = 0
    for _, entry in ipairs(displayList) do
        if entry.type == "header" then
            local h = GetGroupHdr(scrollChild)
            h:SetWidth(RP_W - 14)
            h:SetPoint("TOPLEFT", 0, -yOffset)
            h.lbl:SetText(entry.label)
            h.count:SetText(entry.count .. " items")
            activeGroupHdrs[#activeGroupHdrs + 1] = h
            yOffset = yOffset + HEADER_H
        else
            local row = GetRow(scrollChild)
            row:SetPoint("TOPLEFT", 0, -yOffset)
            PopulateRow(row, entry.result, entry.rank, entry.isEven)
            activeRows[#activeRows + 1] = row
            yOffset = yOffset + ROW_H
        end
    end
end

-- ─── URL copy dialog ─────────────────────────────────────────────────────

local urlDialog

local function CreateUrlDialog()
    local dialog = CreateFrame("Frame", "EWLUrlDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(480, 140)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("EasyWishlist — Web App")

    local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", 0, -44)
    instructions:SetText("Select the link below and press Ctrl+C to copy:")
    instructions:SetTextColor(0.8, 0.8, 0.8)

    local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 20, -68)
    editBox:SetPoint("TOPRIGHT", -20, -68)
    editBox:SetHeight(24)
    editBox:SetAutoFocus(true)
    editBox:SetText("https://frostfel702.github.io/easywishlist_app/")
    editBox:SetScript("OnShow", function(self) self:SetFocus(); self:SelectAll() end)
    editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)

    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 24)
    closeBtn:SetPoint("BOTTOM", 0, 14)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)

    tinsert(UISpecialFrames, "EWLUrlDialog")
    dialog:Hide()
    return dialog
end

function EWL.OpenUrlDialog()
    if not urlDialog then
        urlDialog = CreateUrlDialog()
    end
    urlDialog:Show()
end

-- ─── Wishlist popup ───────────────────────────────────────────────────────

local wishlistPopup

local function CloseWishlistPopup()
    if wishlistPopup then wishlistPopup:Hide() end
end

local function OpenWishlistPopup(anchor)
    local currentKey    = EWL.GetCharacterKey()
    local viewKey       = GetViewKey()
    local wishlists, activeWishlist = EWL.GetWishlistsForKey(viewKey)

    if not wishlistPopup then
        wishlistPopup = CreateFrame("Frame", "EWLWishlistPopup", UIParent, "BackdropTemplate")
        wishlistPopup:SetFrameStrata("TOOLTIP")
        wishlistPopup:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        wishlistPopup.rows = {}
    end

    -- Hide/recycle existing rows
    for _, r in ipairs(wishlistPopup.rows) do r:Hide() end
    wipe(wishlistPopup.rows)

    local PROW_H = 22
    local PAD    = 8
    local WIDTH  = SIDEBAR_W - 4
    local yOff   = -PAD

    -- ── Current viewing character's wishlists ────────────────────────────
    for _, name in ipairs(wishlists) do
        local row = CreateFrame("Button", nil, wishlistPopup)
        row:SetHeight(PROW_H)
        row:SetPoint("TOPLEFT",  PAD,  yOff)
        row:SetPoint("TOPRIGHT", -PAD, yOff)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        local dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dot:SetPoint("LEFT", 0, 0)
        dot:SetWidth(14)
        dot:SetJustifyH("CENTER")

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", 14, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(name)

        if name == activeWishlist then
            dot:SetText("|cff00ff96●|r")
            lbl:SetTextColor(1, 1, 1)
        else
            dot:SetText("")
            lbl:SetTextColor(0.7, 0.7, 0.7)
        end

        local capturedName = name
        local capturedKey  = viewKey
        row:SetScript("OnClick", function()
            EWL.SetActiveWishlistForKey(capturedKey, capturedName)
            viewingCharKey = (capturedKey ~= currentKey) and capturedKey or nil
            dungeonFilter  = nil
            CloseWishlistPopup()
            EWL.RefreshMainWindow()
        end)

        row:Show()
        wishlistPopup.rows[#wishlistPopup.rows + 1] = row
        yOff = yOff - PROW_H
    end

    -- Delete current wishlist option
    if #wishlists >= 1 then
        -- Separator
        local sep = CreateFrame("Frame", nil, wishlistPopup)
        sep:SetHeight(9)
        sep:SetPoint("TOPLEFT",  PAD,  yOff - 2)
        sep:SetPoint("TOPRIGHT", -PAD, yOff - 2)
        local sepLine = sep:CreateTexture(nil, "ARTWORK")
        sepLine:SetPoint("TOPLEFT",  0, -4)
        sepLine:SetPoint("TOPRIGHT", 0, -4)
        sepLine:SetHeight(1)
        sepLine:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        sep:Show()
        wishlistPopup.rows[#wishlistPopup.rows + 1] = sep
        yOff = yOff - 11

        local delRow = CreateFrame("Button", nil, wishlistPopup)
        delRow:SetHeight(PROW_H)
        delRow:SetPoint("TOPLEFT",  PAD,  yOff)
        delRow:SetPoint("TOPRIGHT", -PAD, yOff)

        local delHl = delRow:CreateTexture(nil, "HIGHLIGHT")
        delHl:SetAllPoints()
        delHl:SetColorTexture(1, 0.3, 0.3, 0.12)

        local delLbl = delRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delLbl:SetPoint("LEFT", 0, 0)
        delLbl:SetJustifyH("LEFT")
        local shortName = activeWishlist and (activeWishlist:sub(1, 16) .. (activeWishlist:len() > 16 and "..." or "")) or "?"
        delLbl:SetText("|cffff6666Delete \"" .. shortName .. "\"|r")

        local capturedKey  = viewKey
        local capturedName = activeWishlist
        delRow:SetScript("OnClick", function()
            if capturedName then
                CloseWishlistPopup()
                local dialog = StaticPopup_Show("EWL_CONFIRM_DELETE_WISHLIST", capturedName)
                if dialog then
                    dialog.data = { key = capturedKey, name = capturedName }
                end
            end
        end)

        delRow:Show()
        wishlistPopup.rows[#wishlistPopup.rows + 1] = delRow
        yOff = yOff - PROW_H - 4
    end

    -- ── Other characters ─────────────────────────────────────────────────
    local allKeys = EWL.GetAllCharacterKeys()
    local otherKeys = {}
    for _, k in ipairs(allKeys) do
        if k ~= viewKey then otherKeys[#otherKeys + 1] = k end
    end

    if #otherKeys > 0 then
        -- Separator + header
        local sep2 = CreateFrame("Frame", nil, wishlistPopup)
        sep2:SetHeight(9)
        sep2:SetPoint("TOPLEFT",  PAD,  yOff - 2)
        sep2:SetPoint("TOPRIGHT", -PAD, yOff - 2)
        local sep2Line = sep2:CreateTexture(nil, "ARTWORK")
        sep2Line:SetPoint("TOPLEFT",  0, -4)
        sep2Line:SetPoint("TOPRIGHT", 0, -4)
        sep2Line:SetHeight(1)
        sep2Line:SetColorTexture(0.4, 0.4, 0.4, 0.4)
        sep2:Show()
        wishlistPopup.rows[#wishlistPopup.rows + 1] = sep2
        yOff = yOff - 11

        local otherHdr = wishlistPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        otherHdr:SetPoint("TOPLEFT", PAD, yOff)
        otherHdr:SetText("|cff888888Other Characters|r")
        wishlistPopup.rows[#wishlistPopup.rows + 1] = otherHdr
        yOff = yOff - PROW_H

        for _, k in ipairs(otherKeys) do
            local charName = k:match("^(.-)%-") or k
            local otherWishlists, otherActive = EWL.GetWishlistsForKey(k)

            -- Character name label
            local charLbl = wishlistPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            charLbl:SetPoint("TOPLEFT", PAD, yOff)
            charLbl:SetText("|cffffaa00" .. charName .. "|r")
            wishlistPopup.rows[#wishlistPopup.rows + 1] = charLbl
            yOff = yOff - PROW_H

            for _, wname in ipairs(otherWishlists) do
                local wrow = CreateFrame("Button", nil, wishlistPopup)
                wrow:SetHeight(PROW_H)
                wrow:SetPoint("TOPLEFT",  PAD + 10, yOff)
                wrow:SetPoint("TOPRIGHT", -PAD,     yOff)

                local whl = wrow:CreateTexture(nil, "HIGHLIGHT")
                whl:SetAllPoints()
                whl:SetColorTexture(1, 1, 1, 0.08)

                local wlbl = wrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                wlbl:SetPoint("LEFT",  0,   0)
                wlbl:SetPoint("RIGHT", -20, 0)
                wlbl:SetJustifyH("LEFT")
                wlbl:SetText(wname)
                if wname == otherActive then
                    wlbl:SetTextColor(0.9, 0.9, 0.9)
                else
                    wlbl:SetTextColor(0.55, 0.55, 0.55)
                end

                -- Trash button
                local wtrash = CreateFrame("Button", nil, wrow)
                wtrash:SetSize(18, 18)
                wtrash:SetPoint("RIGHT", -1, 0)

                local wtrashHl = wtrash:CreateTexture(nil, "HIGHLIGHT")
                wtrashHl:SetAllPoints()
                wtrashHl:SetColorTexture(1, 0.2, 0.2, 0.25)

                local wtrashLbl = wtrash:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                wtrashLbl:SetPoint("CENTER")
                wtrashLbl:SetText("|cffaa3333x|r")

                local capturedKey  = k
                local capturedName = wname
                wtrash:SetScript("OnClick", function()
                    CloseWishlistPopup()
                    local dialog = StaticPopup_Show("EWL_CONFIRM_DELETE_WISHLIST", capturedName)
                    if dialog then
                        dialog.data = { key = capturedKey, name = capturedName }
                    end
                end)

                wrow:SetScript("OnClick", function()
                    EWL.SetActiveWishlistForKey(capturedKey, capturedName)
                    viewingCharKey = capturedKey
                    dungeonFilter  = nil
                    CloseWishlistPopup()
                    EWL.RefreshMainWindow()
                end)

                wrow:Show()
                wishlistPopup.rows[#wishlistPopup.rows + 1] = wrow
                yOff = yOff - PROW_H
            end
        end
    end

    local totalH = PAD + (-yOff)
    wishlistPopup:SetSize(WIDTH, totalH)
    wishlistPopup:ClearAllPoints()
    wishlistPopup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    wishlistPopup:Show()
end

-- ─── Sidebar refresh ─────────────────────────────────────────────────────

local function RefreshSidebar()
    if not mainWindow then return end
    local win = mainWindow

    -- Update wishlist dropdown label
    local viewKey = GetViewKey()
    local wishlists, activeWishlist = EWL.GetWishlistsForKey(viewKey)
    if win.wishlistDropBtn then
        if activeWishlist then
            local short = activeWishlist:len() > 18 and activeWishlist:sub(1, 16) .. "..." or activeWishlist
            if viewKey ~= EWL.GetCharacterKey() then
                local charShort = viewKey:match("^(.-)%-") or viewKey
                if charShort:len() > 10 then charShort = charShort:sub(1, 8) .. ".." end
                win.wishlistDropBtn:SetText("|cffffaa00" .. charShort .. "|r: " .. short .. " v")
            else
                win.wishlistDropBtn:SetText(short .. " v")
            end
        else
            win.wishlistDropBtn:SetText("None v")
        end
    end

    -- Update "All Sources" pinned row
    if win.allSourcesRow then
        local report     = EWL.GetReportForKey(viewKey)
        local totalCount = report and report.results and #report.results or 0
        local isAll      = (dungeonFilter == nil)
        if isAll then
            win.allSourcesRow.bg:SetColorTexture(1, 0.82, 0, 0.10)
            win.allSourcesRow.bar:Show()
            win.allSourcesRow.nameText:SetTextColor(1, 0.9, 0.4)
        else
            win.allSourcesRow.bg:SetColorTexture(0, 0, 0, 0)
            win.allSourcesRow.bar:Hide()
            win.allSourcesRow.nameText:SetTextColor(0.85, 0.85, 0.85)
        end
        win.allSourcesRow.countText:SetText("|cff666666" .. totalCount .. "|r")
        win.allSourcesRow:SetScript("OnClick", function()
            dungeonFilter = nil
            RefreshSidebar()
            RefreshList(win.scrollChild)
        end)
    end

    -- Rebuild dungeon rows
    local dungeons   = EWL.GetDungeonListForKey(viewKey)
    local listFrame  = win.dungeonListFrame
    if not listFrame then return end

    win.dungeonRows = win.dungeonRows or {}

    -- Ensure enough pooled row frames exist
    while #win.dungeonRows < #dungeons do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetHeight(DROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        row.bg = bg

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)

        -- Active filter indicator bar on the left
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(2)
        bar:SetPoint("TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", 0, 0)
        bar:SetColorTexture(1, 0.82, 0, 0.9)
        row.bar = bar

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("TOPLEFT", 8, -5)
        nameText:SetPoint("TOPRIGHT", -24, -5)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("TOPLEFT", 8, -19)
        dateText:SetPoint("TOPRIGHT", -24, -19)
        dateText:SetJustifyH("LEFT")
        row.dateText = dateText

        -- Trash button
        local trashBtn = CreateFrame("Button", nil, row)
        trashBtn:SetSize(18, 18)
        trashBtn:SetPoint("RIGHT", -3, 0)

        local trashBg = trashBtn:CreateTexture(nil, "BACKGROUND")
        trashBg:SetAllPoints()
        trashBg:SetColorTexture(0.6, 0.1, 0.1, 0)
        trashBtn.bg = trashBg

        local trashHl = trashBtn:CreateTexture(nil, "HIGHLIGHT")
        trashHl:SetAllPoints()
        trashHl:SetColorTexture(1, 0.2, 0.2, 0.25)

        local trashLbl = trashBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        trashLbl:SetPoint("CENTER")
        trashLbl:SetText("|cffaa3333x|r")
        trashBtn:SetScript("OnEnter", function() trashBg:SetColorTexture(0.6, 0.1, 0.1, 0.4) end)
        trashBtn:SetScript("OnLeave", function() trashBg:SetColorTexture(0.6, 0.1, 0.1, 0) end)
        row.trashBtn = trashBtn

        -- Separator line below row
        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT",  2, 0)
        sep:SetPoint("BOTTOMRIGHT", -2, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.4)

        win.dungeonRows[#win.dungeonRows + 1] = row
    end

    -- Hide all rows
    for _, r in ipairs(win.dungeonRows) do
        r:Hide()
        r:SetScript("OnClick", nil)
        r.trashBtn:SetScript("OnClick", nil)
    end

    -- Populate visible rows
    local yOff = 0
    for i, dungeon in ipairs(dungeons) do
        local row = win.dungeonRows[i]
        local isActive = (dungeonFilter == dungeon.name)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  0, -yOff)
        row:SetPoint("TOPRIGHT", 0, -yOff)
        row:Show()

        if isActive then
            row.bg:SetColorTexture(1, 0.82, 0, 0.10)
            row.bar:Show()
            row.nameText:SetTextColor(1, 0.9, 0.4)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
            row.bar:Hide()
            row.nameText:SetTextColor(0.85, 0.85, 0.85)
        end

        row.nameText:SetText(dungeon.name)

        local dateDisplay = (dungeon.lastUpdated ~= "" and dungeon.lastUpdated) or "imported"
        row.dateText:SetText("|cff666666" .. dateDisplay .. "|r")

        local capturedName = dungeon.name
        row:SetScript("OnClick", function()
            dungeonFilter = (dungeonFilter == capturedName) and nil or capturedName
            RefreshSidebar()
            RefreshList(win.scrollChild)
        end)

        local capturedKey = GetViewKey()
        row.trashBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("EWL_CONFIRM_DELETE_DUNGEON", capturedName)
            if dialog then
                dialog.data = { sourceName = capturedName, key = capturedKey }
            end
        end)

        yOff = yOff + DROW_H
    end

    listFrame:SetHeight(math.max(#dungeons * DROW_H, 1))
end

-- ─── Confirmation dialogs ────────────────────────────────────────────────

StaticPopupDialogs["EWL_CONFIRM_DELETE_WISHLIST"] = {
    text      = "Remove wishlist \"%s\"?",
    button1   = "Remove",
    button2   = "Cancel",
    OnAccept  = function(self)
        local d = self.data
        if not d or not d.key or not d.name then return end
        EWL.DeleteWishlistForKey(d.key, d.name)
        if viewingCharKey == d.key then
            local remaining = EWL.GetWishlistsForKey(d.key)
            if #remaining == 0 then
                viewingCharKey = nil
                dungeonFilter  = nil
            end
        end
        EWL.RefreshMainWindow()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EWL_CONFIRM_DELETE_DUNGEON"] = {
    text      = "Remove all \"%s\" items from this wishlist?",
    button1   = "Remove",
    button2   = "Cancel",
    OnAccept  = function(self)
        local d = self.data
        if not d or not d.sourceName then return end
        EWL.DeleteDungeonForKey(d.key or EWL.GetCharacterKey(), d.sourceName)
        if dungeonFilter == d.sourceName then dungeonFilter = nil end
        EWL.RefreshMainWindow()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ─── Main window ─────────────────────────────────────────────────────────

local function CreateMainWindow()
    local win = CreateFrame("Frame", "EWLMainWindow", UIParent, "BackdropTemplate")
    win:SetSize(WINDOW_W, WINDOW_H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("MEDIUM")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)

    win:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- ── Title bar ────────────────────────────────────────────────────────
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cff00ff96Easy|rWishlist")

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    local importBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -4, -4)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", EWL.OpenImportDialog)

    -- ── Sidebar ──────────────────────────────────────────────────────────
    local sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT",    14, -38)
    sidebar:SetPoint("BOTTOMLEFT", 14,  14)
    sidebar:SetWidth(SIDEBAR_W)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(0, 0, 0, 0.12)

    -- "Selected Wishlist" label
    local wishlistLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistLabel:SetPoint("TOPLEFT", 8, -8)
    wishlistLabel:SetText("Selected Wishlist")
    wishlistLabel:SetTextColor(1, 0.82, 0)

    -- Wishlist dropdown button
    local wishlistDropBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    wishlistDropBtn:SetPoint("TOPLEFT",  8, -24)
    wishlistDropBtn:SetPoint("TOPRIGHT", -8, -24)
    wishlistDropBtn:SetHeight(22)
    wishlistDropBtn:SetText("None v")
    wishlistDropBtn:SetScript("OnClick", function()
        if wishlistPopup and wishlistPopup:IsShown() then
            CloseWishlistPopup()
        else
            OpenWishlistPopup(wishlistDropBtn)
        end
    end)
    win.wishlistDropBtn = wishlistDropBtn

    -- Separator below wishlist selector
    local sidebarSep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetPoint("TOPLEFT",  4, -52)
    sidebarSep:SetPoint("TOPRIGHT", -4, -52)
    sidebarSep:SetHeight(1)
    sidebarSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

    -- "Imports" sub-label
    local dungeonLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dungeonLabel:SetPoint("TOPLEFT", 8, -58)
    dungeonLabel:SetText("Imports")
    dungeonLabel:SetTextColor(0.5, 0.5, 0.5)

    -- "All Sources" pinned row (always visible, not scrolled)
    local allSourcesRow = CreateFrame("Button", nil, sidebar)
    allSourcesRow:SetPoint("TOPLEFT",  0, -70)
    allSourcesRow:SetPoint("TOPRIGHT", 0, -70)
    allSourcesRow:SetHeight(DROW_H)

    local asBg = allSourcesRow:CreateTexture(nil, "BACKGROUND")
    asBg:SetAllPoints()
    allSourcesRow.bg = asBg

    local asHl = allSourcesRow:CreateTexture(nil, "HIGHLIGHT")
    asHl:SetAllPoints()
    asHl:SetColorTexture(1, 1, 1, 0.06)

    local asBar = allSourcesRow:CreateTexture(nil, "ARTWORK")
    asBar:SetWidth(2)
    asBar:SetPoint("TOPLEFT", 0, 0)
    asBar:SetPoint("BOTTOMLEFT", 0, 0)
    asBar:SetColorTexture(1, 0.82, 0, 0.9)
    allSourcesRow.bar = asBar

    local asName = allSourcesRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    asName:SetPoint("TOPLEFT", 8, -5)
    asName:SetJustifyH("LEFT")
    asName:SetText("All Sources")
    allSourcesRow.nameText = asName

    local asCount = allSourcesRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    asCount:SetPoint("TOPRIGHT", -6, -5)
    asCount:SetJustifyH("RIGHT")
    allSourcesRow.countText = asCount

    local asSep = allSourcesRow:CreateTexture(nil, "ARTWORK")
    asSep:SetPoint("BOTTOMLEFT",  2, 0)
    asSep:SetPoint("BOTTOMRIGHT", -2, 0)
    asSep:SetHeight(1)
    asSep:SetColorTexture(0.3, 0.3, 0.3, 0.4)

    win.allSourcesRow = allSourcesRow

    -- Scrollable dungeon list below "All Sources"
    local dungeonScrollFrame = CreateFrame("ScrollFrame", nil, sidebar)
    dungeonScrollFrame:SetPoint("TOPLEFT",     0, -(70 + DROW_H))
    dungeonScrollFrame:SetPoint("BOTTOMRIGHT", 0,  0)
    dungeonScrollFrame:EnableMouseWheel(true)
    dungeonScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max     = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, current - delta * DROW_H)))
    end)

    local dungeonListFrame = CreateFrame("Frame", nil, dungeonScrollFrame)
    dungeonListFrame:SetWidth(dungeonScrollFrame:GetWidth())
    dungeonListFrame:SetHeight(1)
    dungeonScrollFrame:SetScrollChild(dungeonListFrame)

    win.dungeonListFrame  = dungeonListFrame
    win.dungeonRows = {}

    -- ── Vertical divider ─────────────────────────────────────────────────
    local vDivider = win:CreateTexture(nil, "ARTWORK")
    vDivider:SetWidth(1)
    vDivider:SetPoint("TOPLEFT",    14 + SIDEBAR_W + 5, -36)
    vDivider:SetPoint("BOTTOMLEFT", 14 + SIDEBAR_W + 5,  14)
    vDivider:SetColorTexture(0.35, 0.35, 0.35, 0.7)

    -- ── Right panel ───────────────────────────────────────────────────────
    local rightPanel = CreateFrame("Frame", nil, win)
    rightPanel:SetPoint("TOPLEFT",     RP_X, -38)
    rightPanel:SetPoint("BOTTOMRIGHT", -16,   14)
    win.rightPanel = rightPanel

    -- Group toggle buttons
    local groupBtns = {}

    local groupLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupLabel:SetPoint("TOPLEFT", 14, -6)
    groupLabel:SetText("Group:")
    groupLabel:SetTextColor(0.5, 0.5, 0.5)

    local function MakeGroupBtn(label, mode, xLeft)
        local btn = CreateFrame("Button", nil, rightPanel)
        btn:SetSize(72, 18)
        btn:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", xLeft, -4)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(label)
        btn.t = t

        local function Refresh()
            if groupMode == mode then
                btn.bg:SetColorTexture(1, 0.82, 0, 0.14)
                t:SetTextColor(1, 0.82, 0)
            else
                btn.bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                t:SetTextColor(0.55, 0.55, 0.55)
            end
        end
        btn.Refresh = Refresh
        Refresh()

        btn:SetScript("OnClick", function()
            groupMode = (groupMode == mode) and "none" or mode
            wipe(slotCache)
            for _, b in ipairs(groupBtns) do b.Refresh() end
            RefreshList(win.scrollChild)
        end)

        groupBtns[#groupBtns + 1] = btn
        return btn
    end

    MakeGroupBtn("By Source", "source", 68)
    MakeGroupBtn("By Slot",   "slot",   146)
    MakeGroupBtn("By Boss",   "boss",   224)

    -- Stat filter row
    local statsLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLabel:SetPoint("TOPLEFT", 14, -27)
    statsLabel:SetText("Stats:")
    statsLabel:SetTextColor(0.5, 0.5, 0.5)

    wipe(statFilterBtns)
    local statBtnX = 60
    for _, def in ipairs(STAT_DEFS) do
        local btn = CreateFrame("Button", nil, rightPanel)
        btn:SetSize(60, 18)
        btn:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", statBtnX, -25)
        statBtnX = statBtnX + 64

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(def.label)
        btn.t = t

        local capturedKey = def.key
        local function Refresh()
            if activeStatFilters[capturedKey] then
                btn.bg:SetColorTexture(0.1, 0.55, 0.35, 0.40)
                t:SetTextColor(0.2, 1.0, 0.65)
            else
                btn.bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                t:SetTextColor(0.55, 0.55, 0.55)
            end
        end
        btn.Refresh = Refresh
        Refresh()

        btn:SetScript("OnClick", function()
            activeStatFilters[capturedKey] = activeStatFilters[capturedKey] and nil or true
            Refresh()
            RefreshList(win.scrollChild)
        end)

        statFilterBtns[#statFilterBtns + 1] = btn
    end

    -- Divider
    local rpDivider = rightPanel:CreateTexture(nil, "ARTWORK")
    rpDivider:SetPoint("TOPLEFT",  14, -50)
    rpDivider:SetPoint("TOPRIGHT", -6, -50)
    rpDivider:SetHeight(1)
    rpDivider:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, rightPanel)
    headerFrame:SetPoint("TOPLEFT",  14, -54)
    headerFrame:SetPoint("TOPRIGHT", -6, -54)
    headerFrame:SetHeight(20)
    CreateHeaders(headerFrame)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     14, -78)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6,   0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Store references for ShowEmptyState and RefreshSidebar
    scrollChild.mainWin    = win
    scrollChild.rightPanel = rightPanel

    win.scrollChild = scrollChild
    win.scrollFrame = scrollFrame

    tinsert(UISpecialFrames, "EWLMainWindow")

    win:SetScript("OnShow", function()
        RefreshSidebar()
        RefreshList(scrollChild)
    end)

    win:SetScript("OnHide", function()
        CloseWishlistPopup()
        viewingCharKey = nil
        dungeonFilter  = nil
        wipe(activeStatFilters)
        wipe(pendingStats)
        RefreshStatBtns()
    end)

    win:Hide()
    return win
end

-- ─── Public API ──────────────────────────────────────────────────────────

function EWL.ToggleMainWindow()
    if not mainWindow then mainWindow = CreateMainWindow() end
    if mainWindow:IsShown() then
        mainWindow:Hide()
    else
        mainWindow:Show()
    end
end

function EWL.RefreshMainWindow()
    if mainWindow and mainWindow:IsShown() then
        RefreshSidebar()
        if mainWindow.scrollChild then RefreshList(mainWindow.scrollChild) end
    end
end

-- ─── Global item tooltip hook ────────────────────────────────────────────

local ok, err = pcall(function()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local owner = tooltip:GetOwner()
        if owner and owner.result then return end

        local link = data and data.id and ("item:" .. data.id) or select(2, tooltip:GetItem())
        if not link then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID then return end

        local upgrades = EWL.GetItemUpgradeAllWishlists(itemID)
        if not upgrades or #upgrades == 0 then return end

        tooltip:AddLine(" ")
        local limit = math.min(#upgrades, 3)
        for i = 1, limit do
            local u = upgrades[i]
            local r, g, b = PctColor(u.pct)
            tooltip:AddDoubleLine(
                "|cff00ff96EWL|r " .. u.name .. ":",
                string.format("+%.2f%%", u.pct),
                r, g, b, r, g, b
            )
        end
        if #upgrades > 3 then
            tooltip:AddLine(string.format("|cff888888  ...and %d more|r", #upgrades - 3))
        end
        tooltip:Show()
    end)
end)
if not ok then
    print("|cffff4444EasyWishlist|r: Failed to register tooltip hook: " .. tostring(err))
end

-- ─── ITEM_DATA_LOAD_RESULT ───────────────────────────────────────────────

local itemEventFrame = CreateFrame("Frame")
itemEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemEventFrame:SetScript("OnEvent", function(self, event, itemID, success)
    if not success then return end

    -- Populate stat cache if this item was requested for filtering
    if pendingStats[itemID] ~= nil then
        local ilvl = pendingStats[itemID]
        pendingStats[itemID] = nil
        TryCacheStats(itemID, ilvl)
        -- Re-filter list now that we have this item's stats
        if next(activeStatFilters) and mainWindow and mainWindow:IsShown() then
            RefreshList(mainWindow.scrollChild)
            return
        end
    end

    if not pendingItems[itemID] then return end
    if not mainWindow or not mainWindow:IsShown() then return end

    pendingItems[itemID] = nil

    if groupMode == "slot" and not slotCache[itemID] then
        RefreshList(mainWindow.scrollChild)
        return
    end

    for _, row in ipairs(activeRows) do
        if row.itemID == itemID then
            PopulateRow(row, row.result, row.rank, row.isEven)
        end
    end
end)
