-- EasyWishlist - Import.lua
-- Import dialog: paste QE JSON, pick wishlist name, validate, save

local importDialog

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

    -- ── Wishlist name field ───────────────────────────────────────────────
    local wishlistLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishlistLabel:SetPoint("TOPLEFT", 20, -68)
    wishlistLabel:SetText("Save to wishlist:")
    wishlistLabel:SetTextColor(1, 0.82, 0)

    local wishlistInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    wishlistInput:SetPoint("TOPLEFT",  20, -84)
    wishlistInput:SetPoint("TOPRIGHT", -20, -84)
    wishlistInput:SetHeight(22)
    wishlistInput:SetAutoFocus(false)
    wishlistInput:SetMaxLetters(64)
    wishlistInput:SetScript("OnEscapePressed", function() dialog:Hide() end)
    wishlistInput:SetScript("OnTextChanged", function()
        dialog.errorLabel:SetText("")
    end)
    dialog.wishlistInput = wishlistInput

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
        local wishlistName = wishlistInput:GetText()
        if not wishlistName or wishlistName:match("^%s*$") then
            errorLabel:SetText("Please enter a wishlist name.")
            wishlistInput:SetFocus()
            return
        end
        wishlistName = wishlistName:match("^%s*(.-)%s*$")  -- trim whitespace

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

    -- Pre-fill wishlist name with the currently active wishlist
    local _, activeWishlist = EWL.GetWishlists()
    if activeWishlist then
        importDialog.wishlistInput:SetText(activeWishlist)
    else
        importDialog.wishlistInput:SetText("")
    end

    importDialog:Show()
    importDialog.editBox:SetFocus()
end
