-- EasyWishlist - Import.lua
-- Import dialog: paste QE JSON, pick or create a wishlist, validate, save

local importDialog
local importWishlistPopup

-- ─── Wishlist selector popup ──────────────────────────────────────────────

local function OpenImportWishlistPopup(anchor, onSelect)
    local wishlists, activeWishlist = EWL.GetWishlists()

    if not importWishlistPopup then
        importWishlistPopup = CreateFrame("Frame", "EWLImportWishlistPopup", UIParent, "BackdropTemplate")
        importWishlistPopup:SetFrameStrata("TOOLTIP")
        importWishlistPopup:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        importWishlistPopup.rows = {}
    end

    -- Hide/recycle existing rows
    for _, r in ipairs(importWishlistPopup.rows) do r:Hide() end
    wipe(importWishlistPopup.rows)

    local PROW_H = 22
    local PAD    = 8
    local WIDTH  = anchor:GetWidth()
    local yOff   = -PAD

    -- Existing wishlist rows
    for _, name in ipairs(wishlists) do
        local row = CreateFrame("Button", nil, importWishlistPopup)
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
            dot:SetText("|cff00ff96\226\151\143|r")  -- filled circle
            lbl:SetTextColor(1, 1, 1)
        else
            dot:SetText("")
            lbl:SetTextColor(0.7, 0.7, 0.7)
        end

        local capturedName = name
        row:SetScript("OnClick", function()
            importWishlistPopup:Hide()
            onSelect(capturedName)
        end)

        row:Show()
        importWishlistPopup.rows[#importWishlistPopup.rows + 1] = row
        yOff = yOff - PROW_H
    end

    -- Separator before "New" row (only if there are existing wishlists)
    if #wishlists > 0 then
        local sep = CreateFrame("Frame", nil, importWishlistPopup)
        sep:SetHeight(9)
        sep:SetPoint("TOPLEFT",  PAD,  yOff - 2)
        sep:SetPoint("TOPRIGHT", -PAD, yOff - 2)
        local sepLine = sep:CreateTexture(nil, "ARTWORK")
        sepLine:SetPoint("TOPLEFT",  0, -4)
        sepLine:SetPoint("TOPRIGHT", 0, -4)
        sepLine:SetHeight(1)
        sepLine:SetColorTexture(0.4, 0.4, 0.4, 0.5)
        sep:Show()
        importWishlistPopup.rows[#importWishlistPopup.rows + 1] = sep
        yOff = yOff - 11
    end

    -- "New:" input row
    local newRow = CreateFrame("Frame", nil, importWishlistPopup)
    newRow:SetHeight(PROW_H)
    newRow:SetPoint("TOPLEFT",  PAD,  yOff)
    newRow:SetPoint("TOPRIGHT", -PAD, yOff)

    local newLbl = newRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newLbl:SetPoint("LEFT", 0, 0)
    newLbl:SetText("|cffffd700New:|r")
    newLbl:SetWidth(34)

    local newInput = CreateFrame("EditBox", nil, newRow, "InputBoxTemplate")
    newInput:SetPoint("LEFT",  34, 0)
    newInput:SetPoint("RIGHT", -54, 0)
    newInput:SetHeight(PROW_H)
    newInput:SetAutoFocus(true)
    newInput:SetMaxLetters(64)

    local createBtn = CreateFrame("Button", nil, newRow, "UIPanelButtonTemplate")
    createBtn:SetSize(48, PROW_H)
    createBtn:SetPoint("RIGHT", 0, 0)
    createBtn:SetText("Create")

    local function DoCreate()
        local name = newInput:GetText():match("^%s*(.-)%s*$")
        if name and name ~= "" then
            importWishlistPopup:Hide()
            onSelect(name)
        else
            newInput:SetFocus()
        end
    end

    createBtn:SetScript("OnClick", DoCreate)
    newInput:SetScript("OnEnterPressed", DoCreate)
    newInput:SetScript("OnEscapePressed", function() importWishlistPopup:Hide() end)

    newRow:Show()
    importWishlistPopup.rows[#importWishlistPopup.rows + 1] = newRow
    yOff = yOff - PROW_H

    local totalH = PAD + (-yOff)
    importWishlistPopup:SetSize(WIDTH, totalH)
    importWishlistPopup:ClearAllPoints()
    importWishlistPopup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    importWishlistPopup:Show()

    -- Auto-focus the new name input
    newInput:SetFocus()
end

-- ─── Import dialog ────────────────────────────────────────────────────────

local function CreateImportDialog()
    local dialog = CreateFrame("Frame", "EWLImportDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(520, 420)
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

    -- Title
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("EasyWishlist — Import Report")

    -- Instructions
    local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", 0, -44)
    instructions:SetText("Paste your EasyWishlist import string below:")
    instructions:SetTextColor(0.8, 0.8, 0.8)

    -- ── Wishlist selector ─────────────────────────────────────────────────
    local wishlistLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistLabel:SetPoint("TOPLEFT", 20, -68)
    wishlistLabel:SetText("Save to:")
    wishlistLabel:SetTextColor(1, 0.82, 0)

    -- Dropdown button — full width, shows selected wishlist name
    local dropBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dropBtn:SetPoint("TOPLEFT",  20, -84)
    dropBtn:SetPoint("TOPRIGHT", -20, -84)
    dropBtn:SetHeight(22)
    dropBtn:SetText("Select or create a wishlist... v")

    -- Track the currently selected wishlist name (local to this closure)
    local selectedWishlist = nil

    local function SetSelected(name)
        selectedWishlist = name
        if name and name ~= "" then
            local short = name:len() > 32 and name:sub(1, 30) .. "..." or name
            dropBtn:SetText(short .. " v")
        else
            dropBtn:SetText("Select or create a wishlist... v")
        end
        dialog.errorLabel:SetText("")
    end

    dropBtn:SetScript("OnClick", function()
        if importWishlistPopup and importWishlistPopup:IsShown() then
            importWishlistPopup:Hide()
        else
            OpenImportWishlistPopup(dropBtn, SetSelected)
        end
    end)

    -- Store accessors on dialog so OpenImportDialog can use them
    dialog.setSelected = SetSelected
    dialog.getSelected = function() return selectedWishlist end

    -- EditBox scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     20, -114)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36,  60)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    editBox:SetScript("OnTextChanged", function()
        dialog.errorLabel:SetText("")
    end)
    scrollFrame:SetScrollChild(editBox)

    -- Scroll frame background
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(scrollFrame)
    scrollBg:SetColorTexture(0, 0, 0, 0.4)

    -- Error label
    local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorLabel:SetPoint("BOTTOMLEFT",  20, 38)
    errorLabel:SetPoint("BOTTOMRIGHT", -20, 38)
    errorLabel:SetTextColor(1, 0.3, 0.3)
    errorLabel:SetJustifyH("LEFT")
    errorLabel:SetText("")
    dialog.errorLabel = errorLabel

    -- Import button
    local importBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 24)
    importBtn:SetPoint("BOTTOMRIGHT", -20, 14)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local wishlistName = dialog.getSelected()
        if not wishlistName or wishlistName:match("^%s*$") then
            errorLabel:SetText("Please select or create a wishlist first.")
            return
        end

        local text = editBox:GetText()
        if not text or text:match("^%s*$") then
            errorLabel:SetText("Please paste an import string first.")
            return
        end

        local data, err = EWL.ParseJSON(text)
        if not data then
            errorLabel:SetText("Invalid JSON: " .. (err or "unknown error"))
            return
        end

        if EWL.IsRaidbotsFormat(data) then
            data = EWL.NormalizeRaidbots(data)
        elseif EWL.IsQEFormat(data) then
            data = EWL.NormalizeQE(data)
        end

        local ok, saveErr = EWL.SaveReport(data, wishlistName)
        if not ok then
            errorLabel:SetText("Import failed: " .. (saveErr or "unknown error"))
            return
        end

        editBox:SetText("")
        dialog:Hide()
        EWL.RefreshMainWindow()
        print("|cff00ff96EasyWishlist:|r Merged into wishlist \"" .. wishlistName .. "\".")
    end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", importBtn, "BOTTOMLEFT", -8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        editBox:SetText("")
        errorLabel:SetText("")
        if importWishlistPopup then importWishlistPopup:Hide() end
        dialog:Hide()
    end)

    tinsert(UISpecialFrames, "EWLImportDialog")

    dialog.editBox = editBox
    dialog:Hide()
    return dialog
end

function EWL.OpenImportDialog()
    if not importDialog then
        importDialog = CreateImportDialog()
    end
    importDialog.errorLabel:SetText("")

    -- Pre-select the currently active wishlist
    local _, activeWishlist = EWL.GetWishlists()
    importDialog.setSelected(activeWishlist or nil)

    if importWishlistPopup then importWishlistPopup:Hide() end
    importDialog:Show()
    importDialog.editBox:SetFocus()
end
