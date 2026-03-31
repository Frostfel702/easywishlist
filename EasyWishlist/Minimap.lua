-- EasyWishlist - Minimap.lua
-- Minimap button via LibDBIcon-1.0
-- Left-click: toggle main window | Right-click: open import dialog

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("EasyWishlist", {
    type = "launcher",
    text = "EasyWishlist",
    icon = "Interface\\Icons\\INV_Misc_Bag_07",

    OnClick = function(self, button)
        if button == "LeftButton" then
            EWL.ToggleMainWindow()
        elseif button == "RightButton" then
            EWL.OpenImportDialog()
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:AddLine("EasyWishlist")
        tooltip:AddLine("Left-click: Toggle wishlist", 1, 1, 1)
        tooltip:AddLine("Right-click: Import report", 1, 1, 1)
    end,
})

local icon = LibStub("LibDBIcon-1.0")

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Migrate legacy angle storage to LibDBIcon's expected table shape
        if EasyWishlistDB.minimapPos and EasyWishlistDB.minimapPos.angle then
            EasyWishlistDB.minimap = EasyWishlistDB.minimap or {}
            EasyWishlistDB.minimap.minimapPos = EasyWishlistDB.minimapPos.angle
            EasyWishlistDB.minimapPos = nil
        end

        EasyWishlistDB.minimap = EasyWishlistDB.minimap or {}
        icon:Register("EasyWishlist", LDB, EasyWishlistDB.minimap)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
