-- EasyWishlist - Minimap.lua
-- Manual minimap button (no external library dependency)
-- Left-click: toggle main window | Right-click: open import dialog

local BUTTON_RADIUS = 80  -- distance from minimap center
local ICON_SIZE = 31

local minimapBtn

local function UpdateMinimapButtonPosition(btn, angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * BUTTON_RADIUS
    local y = math.sin(rad) * BUTTON_RADIUS
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "EWLMinimapButton", Minimap)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetFrameLevel(8)
    btn:SetFrameStrata("MEDIUM")

    -- Circle mask so it looks like a proper minimap button
    local mask = btn:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    -- Icon texture (slightly inset so it sits inside the circular border)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(ICON_SIZE - 4, ICON_SIZE - 4)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    icon:AddMaskTexture(mask)

    -- Pushed texture
    local pushed = btn:CreateTexture(nil, "HIGHLIGHT")
    pushed:SetAllPoints()
    pushed:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Border
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Dragging to reposition
    local isDragging = false
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            EasyWishlistDB.minimapPos.angle = angle
            UpdateMinimapButtonPosition(self, angle)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if isDragging then return end
        if button == "LeftButton" then
            EWL.ToggleMainWindow()
        elseif button == "RightButton" then
            EWL.OpenImportDialog()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("EasyWishlist")
        GameTooltip:AddLine("Left-click: Toggle wishlist", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Import report", 1, 1, 1)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

-- Initialize after PLAYER_LOGIN so Minimap frame is ready
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        minimapBtn = CreateMinimapButton()
        local angle = (EasyWishlistDB.minimapPos and EasyWishlistDB.minimapPos.angle) or 225
        UpdateMinimapButtonPosition(minimapBtn, angle)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
