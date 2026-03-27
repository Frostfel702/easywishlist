-- EasyWishlist - UI.lua
-- Main window: header, scrolling item list, tooltips

local WINDOW_W  = 540
local WINDOW_H  = 440   -- slightly taller to fit group buttons
local ROW_H     = 32
local HEADER_H  = 22
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
local rowPool        = {}
local activeRows     = {}
local groupHdrPool   = {}
local activeGroupHdrs = {}

-- ─── Group state ─────────────────────────────────────────────────────────

local groupMode  = "none"   -- "none" | "source" | "slot"
local slotCache  = {}       -- itemID -> display slot name

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
    row:SetWidth(WINDOW_W - 20)

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
        -- Cache slot from invType if not already cached
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
    if result.dropLoc == "Dungeon" then
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
    if result.dropLoc == "Dungeon" then
        return name .. " Mythic+"
    elseif result.dropLoc == "Raid" and result.dropDifficulty then
        local diffNames = { [0]="LFR",[1]="LFR",[2]="Normal",[3]="Normal",[4]="Heroic",[5]="Heroic",[6]="Mythic",[7]="Mythic" }
        local diff = diffNames[result.dropDifficulty]
        return diff and (name .. " " .. diff) or name
    end
    return name
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
        local f = CreateFrame("Frame", nil, contentFrame)
        f:SetPoint("TOPLEFT", 20, -10)
        f:SetPoint("BOTTOMRIGHT", -20, 10)
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
            labelStr:SetWidth(440)
            labelStr:SetText(step.label)
            labelStr:SetJustifyH("LEFT")
            labelStr:SetTextColor(1, 1, 1)

            local descStr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            descStr:SetPoint("TOPLEFT", numStr, "BOTTOMLEFT", 0, -2)
            descStr:SetWidth(440)
            descStr:SetText(step.desc)
            descStr:SetJustifyH("LEFT")
            descStr:SetTextColor(0.7, 0.7, 0.7)

            yOffset = yOffset - 52

            if step.url then
                local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                copyBtn:SetSize(80, 22)
                copyBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, yOffset)
                copyBtn:SetText("Copy Link")

                local urlBox = CreateFrame("EditBox", nil, f)
                urlBox:SetPoint("TOPLEFT", copyBtn, "TOPRIGHT", 6, -1)
                urlBox:SetWidth(350)
                urlBox:SetHeight(20)
                urlBox:SetFont(STANDARD_TEXT_FONT, 12)
                urlBox:SetTextColor(0.2, 0.6, 1)
                urlBox:SetText(step.url)
                urlBox:SetAutoFocus(false)
                urlBox:SetScript("OnEditFocusGained", function(self) self:SelectAll() end)
                urlBox:SetScript("OnMouseUp", function(self) self:SetFocus(); self:SelectAll() end)
                urlBox:SetScript("OnChar", function(self) self:SetText(step.url); self:SelectAll() end)
                urlBox:SetScript("OnKeyDown", function(self, key)
                    if key == "ESCAPE" then self:ClearFocus() end
                end)

                copyBtn:SetScript("OnClick", function()
                    urlBox:SetFocus()
                    urlBox:SelectAll()
                    copyBtn:SetText("Ctrl+C!")
                    C_Timer.After(2, function() copyBtn:SetText("Copy Link") end)
                end)

                yOffset = yOffset - 30
            end
        end
    end
    contentFrame.tutorialFrame:SetShown(show)
end

-- ─── Refresh list ────────────────────────────────────────────────────────

local function RefreshList(scrollChild)
    for _, row in ipairs(activeRows)     do ReleaseRow(row)      end
    for _, h   in ipairs(activeGroupHdrs) do ReleaseGroupHdr(h)  end
    wipe(activeRows)
    wipe(activeGroupHdrs)
    wipe(pendingItems)

    local report = EWL.GetCurrentReport()
    ShowEmptyState(scrollChild, not report or not report.results or #report.results == 0)
    if not report or not report.results then return end

    local displayList = BuildDisplayList(report.results)

    local totalH = 0
    for _, entry in ipairs(displayList) do
        totalH = totalH + (entry.type == "header" and HEADER_H or ROW_H)
    end
    scrollChild:SetHeight(math.max(totalH, 1))

    local yOffset = 0
    for _, entry in ipairs(displayList) do
        if entry.type == "header" then
            local h = GetGroupHdr(scrollChild)
            h:SetWidth(WINDOW_W - 20)
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

-- ─── Header info ─────────────────────────────────────────────────────────

local function UpdateHeader(infoLabel)
    local report = EWL.GetCurrentReport()
    if not report then infoLabel:SetText(""); return end
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

    -- Title
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cff00ff96Easy|rWishlist")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- Import button
    local importBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -4, -4)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", EWL.OpenImportDialog)

    -- Sim info line
    local infoLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 16, -38)
    infoLabel:SetPoint("TOPRIGHT", -110, -38)
    infoLabel:SetJustifyH("LEFT")
    win.infoLabel = infoLabel

    -- ── Group toggle buttons ──────────────────────────────────────────────
    local groupBtns = {}

    local groupLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupLabel:SetPoint("TOPLEFT", 16, -60)
    groupLabel:SetText("Group:")
    groupLabel:SetTextColor(0.5, 0.5, 0.5)

    local function MakeGroupBtn(label, mode, xLeft)
        local btn = CreateFrame("Button", nil, win)
        btn:SetSize(72, 18)
        btn:SetPoint("TOPLEFT", win, "TOPLEFT", xLeft, -58)

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

    -- Divider
    local divider = win:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 14, -80)
    divider:SetPoint("TOPRIGHT", -14, -80)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, win)
    headerFrame:SetPoint("TOPLEFT", 14, -84)
    headerFrame:SetPoint("TOPRIGHT", -14, -84)
    headerFrame:SetHeight(20)
    CreateHeaders(headerFrame)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -108)
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
    if not mainWindow then mainWindow = CreateMainWindow() end
    if mainWindow:IsShown() then
        mainWindow:Hide()
    else
        mainWindow:Show()
    end
end

function EWL.RefreshMainWindow()
    if mainWindow and mainWindow:IsShown() then
        if mainWindow.infoLabel then UpdateHeader(mainWindow.infoLabel) end
        if mainWindow.scrollChild then RefreshList(mainWindow.scrollChild) end
    end
end

-- ─── ITEM_DATA_LOAD_RESULT ───────────────────────────────────────────────

local itemEventFrame = CreateFrame("Frame")
itemEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
itemEventFrame:SetScript("OnEvent", function(self, event, itemID, success)
    if not success then return end
    if not pendingItems[itemID] then return end
    if not mainWindow or not mainWindow:IsShown() then return end

    pendingItems[itemID] = nil

    -- Slot grouping: if the slot wasn't cached yet, re-render to place item correctly
    if groupMode == "slot" and not slotCache[itemID] then
        RefreshList(mainWindow.scrollChild)
        return
    end

    -- Otherwise just repaint the affected rows
    for _, row in ipairs(activeRows) do
        if row.itemID == itemID then
            PopulateRow(row, row.result, row.rank, row.isEven)
        end
    end
end)
