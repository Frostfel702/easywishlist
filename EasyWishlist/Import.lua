-- EasyWishlist - Import.lua
-- Import dialog: paste QE JSON, validate, save

local importDialog

-- Build an auto-suggested title from parsed report data
local function SuggestTitle(data)
    if not data then return "" end
    local spec = data.spec or ""
    local ct   = data.contentType or ""
    if spec ~= "" and ct ~= "" then
        return spec .. " - " .. ct
    elseif spec ~= "" then
        return spec
    end
    return "Imported Report"
end

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

    -- Report name label
    local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 20, -48)
    nameLabel:SetText("Report name:")
    nameLabel:SetTextColor(0.8, 0.8, 0.8)

    -- Report name input
    local nameBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", 100, -44)
    nameBox:SetPoint("TOPRIGHT", -20, -44)
    nameBox:SetHeight(20)
    nameBox:SetAutoFocus(false)
    nameBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.nameBox = nameBox

    -- Instructions
    local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", 0, -76)
    instructions:SetText("Paste your EasyWishlist import string below:")
    instructions:SetTextColor(0.8, 0.8, 0.8)

    -- EditBox scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -100)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 60)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
    editBox:SetScript("OnTextChanged", function(self)
        -- Clear error when user starts editing
        dialog.errorLabel:SetText("")
        -- Auto-suggest title if name box is still empty or has a prior suggestion
        local text = self:GetText()
        if not text or text:match("^%s*$") then return end
        local data = EWL.ParseJSON(text)
        if not data then return end
        if EWL.IsRaidbotsFormat(data) then
            data = EWL.NormalizeRaidbots(data)
        end
        local suggested = SuggestTitle(data)
        if suggested ~= "" and dialog.nameBox:GetText():match("^%s*$") then
            dialog.nameBox:SetText(suggested)
        end
    end)
    scrollFrame:SetScrollChild(editBox)

    -- Scroll frame background
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(scrollFrame)
    scrollBg:SetColorTexture(0, 0, 0, 0.4)

    -- Error label
    local errorLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorLabel:SetPoint("BOTTOMLEFT", 20, 38)
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

        -- Detect format and normalise to the common structure
        if EWL.IsRaidbotsFormat(data) then
            data = EWL.NormalizeRaidbots(data)
        end

        local nameText = dialog.nameBox:GetText()
        if nameText:match("^%s*$") then
            nameText = SuggestTitle(data)
        end

        local ok, saveErr = EWL.SaveReport(data, nameText)
        if not ok then
            errorLabel:SetText("Import failed: " .. (saveErr or "unknown error"))
            return
        end

        editBox:SetText("")
        nameBox:SetText("")
        dialog:Hide()
        EWL.RefreshMainWindow()
        print("|cff00ff96EasyWishlist:|r Report imported successfully for " .. (data.spec or "unknown spec") .. ".")
    end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", importBtn, "BOTTOMLEFT", -8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        editBox:SetText("")
        nameBox:SetText("")
        errorLabel:SetText("")
        dialog:Hide()
    end)

    -- Close on Escape via UISpecialFrames
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
    importDialog.nameBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
end
