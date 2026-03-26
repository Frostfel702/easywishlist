-- EasyWishlist - UI.lua
-- Main window: header, scrolling item list, tooltips

local WINDOW_W = 540
local WINDOW_H = 420
local ROW_H    = 32
local ICON_SIZE = 24
local COL = {
    rank   = { x = 14,  w = 24  },
    icon   = { x = 42,  w = 26  },
    name   = { x = 72,  w = 200 },
    ilvl   = { x = 276, w = 40  },
    pct    = { x = 320, w = 52  },
    source = { x = 376, w = 130 },
}

local mainWindow
local rowPool = {}
local activeRows = {}

-- ─── Colour helpers ──────────────────────────────────────────────────────

local function QualityColor(quality)
    local r, g, b = GetItemQualityColor(quality or 1)
    return r, g, b
end

local function PctColor(pct)
    if pct >= 1.0 then return 0.0, 1.0, 0.4      -- green
    elseif pct >= 0.5 then return 1.0, 0.85, 0.0  -- yellow
    else return 0.8, 0.8, 0.8 end                 -- grey
end

-- ─── Row pool ────────────────────────────────────────────────────────────

local function GetRow(parent)
    local row = table.remove(rowPool)
    if row then
        row:SetParent(parent)
        row:Show()
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    -- Alternating background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    -- Highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    -- Rank
    local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("LEFT", COL.rank.x, 0)
    rankText:SetWidth(COL.rank.w)
    rankText:SetJustifyH("RIGHT")
    rankText:SetTextColor(0.6, 0.6, 0.6)
    row.rankText = rankText

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", COL.icon.x, 0)
    row.icon = icon

    -- Item name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", COL.name.x, 0)
    nameText:SetWidth(COL.name.w)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- Item level
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlText:SetPoint("LEFT", COL.ilvl.x, 0)
    ilvlText:SetWidth(COL.ilvl.w)
    ilvlText:SetJustifyH("CENTER")
    ilvlText:SetTextColor(0.7, 0.9, 1)
    row.ilvlText = ilvlText

    -- Upgrade %
    local pctText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctText:SetPoint("LEFT", COL.pct.x, 0)
    pctText:SetWidth(COL.pct.w)
    pctText:SetJustifyH("CENTER")
    row.pctText = pctText

    -- Source
    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("LEFT", COL.source.x, 0)
    sourceText:SetWidth(COL.source.w)
    sourceText:SetJustifyH("LEFT")
    sourceText:SetTextColor(0.7, 0.7, 0.7)
    row.sourceText = sourceText

    -- Tooltip
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
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:SetParent(nil)
    row.itemID = nil
    rowPool[#rowPool + 1] = row
end

-- ─── Populate a row ──────────────────────────────────────────────────────

local pendingItems = {}  -- itemID -> true, waiting for cache

local function PopulateRow(row, result, rank, isEven)
    row.itemID = result.item
    row.result = result
    row:SetWidth(WINDOW_W - 20)

    -- Alternating background
    if isEven then
        row.bg:SetColorTexture(1, 1, 1, 0.04)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    row.rankText:SetText(rank)

    -- Item data from WoW cache
    local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(result.item)
    if name then
        local r, g, b = QualityColor(quality)
        row.nameText:SetText(name)
        row.nameText:SetTextColor(r, g, b)
        row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    else
        row.nameText:SetText("|cff888888Loading...|r")
        row.nameText:SetTextColor(0.5, 0.5, 0.5)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        -- Request item data and flag for refresh
        C_Item.RequestLoadItemDataByID(result.item)
        pendingItems[result.item] = true
    end

    row.ilvlText:SetText(result.level or "?")

    local pct = result.percDiff or 0
    local r, g, b = PctColor(pct)
    row.pctText:SetText(string.format("+%.2f%%", pct))
    row.pctText:SetTextColor(r, g, b)

    -- Source: "Pit of Saron Mythic+" or "The Voidspire Heroic" etc.
    local locLabel = result.sourceName or result.dropLoc or "?"
    local diffLabel = ""
    if result.dropLoc == "Dungeon" then
        diffLabel = " Mythic+"
    elseif result.dropLoc == "Raid" and result.dropDifficulty then
        -- Support both old (4=Normal,5=Heroic,6=Mythic) and new (2=Normal,4=Heroic,6=Mythic) values
        local diffNames = { [0]="LFR", [1]="LFR", [2]="Normal", [3]="Normal", [4]="Heroic", [5]="Heroic", [6]="Mythic", [7]="Mythic" }
        diffLabel = " " .. (diffNames[result.dropDifficulty] or "")
    end
    row.sourceText:SetText(locLabel .. diffLabel)
end

-- ─── Column headers ──────────────────────────────────────────────────────

local function CreateHeaders(parent)
    local headerData = {
        { x = COL.rank.x,   w = COL.rank.w,   label = "#",      align = "RIGHT"  },
        { x = COL.name.x,   w = COL.name.w,   label = "Item",   align = "LEFT"   },
        { x = COL.ilvl.x,   w = COL.ilvl.w,   label = "ilvl",   align = "CENTER" },
        { x = COL.pct.x,    w = COL.pct.w,    label = "Upgrade",align = "CENTER" },
        { x = COL.source.x, w = COL.source.w, label = "Source", align = "LEFT"   },
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

-- ─── Empty state label ───────────────────────────────────────────────────

local function ShowEmptyState(contentFrame, show)
    if not contentFrame.emptyLabel then
        local lbl = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", 0, 0)
        lbl:SetText("No report loaded.\nClick |cffffd700Import|r or right-click the minimap button.")
        lbl:SetJustifyH("CENTER")
        lbl:SetTextColor(0.6, 0.6, 0.6)
        contentFrame.emptyLabel = lbl
    end
    contentFrame.emptyLabel:SetShown(show)
end

-- ─── Refresh list ────────────────────────────────────────────────────────

local function RefreshList(scrollChild)
    -- Release existing rows
    for _, row in ipairs(activeRows) do
        ReleaseRow(row)
    end
    wipe(activeRows)
    wipe(pendingItems)

    local report = EWL.GetCurrentReport()
    ShowEmptyState(scrollChild, not report or not report.results or #report.results == 0)

    if not report or not report.results then return end

    local results = report.results
    local totalH = #results * ROW_H
    scrollChild:SetHeight(math.max(totalH, 1))

    for i, result in ipairs(results) do
        local row = GetRow(scrollChild)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        PopulateRow(row, result, i, (i % 2 == 0))
        activeRows[#activeRows + 1] = row
    end
end

-- ─── Header info ─────────────────────────────────────────────────────────

local function UpdateHeader(infoLabel)
    local report = EWL.GetCurrentReport()
    if not report then
        infoLabel:SetText("")
        return
    end
    local diffLabel = EWL.GetDifficultyLabel(report)
    local text = string.format("|cffffd700%s|r  %s  |cff888888%s|r",
        report.spec or "?",
        report.contentType and (report.contentType .. (diffLabel ~= "" and (" " .. diffLabel) or "")) or "?",
        report.dateCreated or "")
    infoLabel:SetText(text)
end

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

    -- Title bar
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cff00ff96Easy|rWishlist")

    -- Import button (top right)
    local importBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("TOPRIGHT", -16, -12)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", EWL.OpenImportDialog)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", importBtn, "TOPLEFT", -4, 4)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- Sim info line
    local infoLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 16, -38)
    infoLabel:SetPoint("TOPRIGHT", -110, -38)
    infoLabel:SetJustifyH("LEFT")
    win.infoLabel = infoLabel

    -- Divider
    local divider = win:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 14, -52)
    divider:SetPoint("TOPRIGHT", -14, -52)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, win)
    headerFrame:SetPoint("TOPLEFT", 14, -56)
    headerFrame:SetPoint("TOPRIGHT", -14, -56)
    headerFrame:SetHeight(20)
    CreateHeaders(headerFrame)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -80)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 14)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    win.scrollChild = scrollChild
    win.scrollFrame = scrollFrame

    tinsert(UISpecialFrames, "EWLMainWindow")

    win:SetScript("OnShow", function()
        UpdateHeader(win.infoLabel)
        RefreshList(scrollChild)
    end)

    win:Hide()
    return win
end

-- ─── Public API ──────────────────────────────────────────────────────────

function EWL.ToggleMainWindow()
    if not mainWindow then
        mainWindow = CreateMainWindow()
    end
    if mainWindow:IsShown() then
        mainWindow:Hide()
    else
        mainWindow:Show()
    end
end

function EWL.RefreshMainWindow()
    if mainWindow and mainWindow:IsShown() then
        if mainWindow.infoLabel then
            UpdateHeader(mainWindow.infoLabel)
        end
        if mainWindow.scrollChild then
            RefreshList(mainWindow.scrollChild)
        end
    end
end

-- ─── ITEM_DATA_LOAD_RESULT — refresh rows when item data arrives ──────────

local itemEventFrame = CreateFrame("Frame")
itemEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemEventFrame:SetScript("OnEvent", function(self, event, itemID, success)
    if not success then return end
    if pendingItems[itemID] and mainWindow and mainWindow:IsShown() then
        pendingItems[itemID] = nil
        -- Refresh only the rows that need this item
        local report = EWL.GetCurrentReport()
        if not report then return end
        for i, row in ipairs(activeRows) do
            if row.itemID == itemID then
                PopulateRow(row, report.results[i], i, (i % 2 == 0))
            end
        end
    end
end)
