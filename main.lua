-- ORIGINAL SOURCE: https://github.com/seanstertm/Isaac-Regret-Pedestals
-- Forked version

mod = RegisterMod("New Regret Pedestals", 1)

local stopWithHourglass = true

local pedestalItemsInRoom = {}    -- {entity=, subtype=, isBlind=}
local shopItemsInRoom = {}        -- {entity=, subtype=, isBlind=}
local disappearingPedestalItems = {}
local disappearingPedestalItemsFrame = {}
local disappearingShopItems = {}
local disappearingShopItemsFrame = {}

local itemSprite = Sprite()
itemSprite:Load("gfx/005.100_collectible.anm2",true)

local game = Game()

function mod:SaveStorage()
    if game:GetFrameCount() <= 0 then return end
    if stopWithHourglass then
        mod:SaveData("true")
    else
        mod:SaveData("false")
    end
end

function mod:LoadStorage()
    if mod:HasData() then
        savedata = mod:LoadData()
        if savedata == "true" then
            stopWithHourglass = true
        else
            stopWithHourglass = false
        end
    end
end

if ModConfigMenu then

    local function SaveModConfig()
        if stopWithHourglass then
            mod:SaveData("true")
        else
            mod:SaveData("false")
        end
    end

    ModConfigMenu.AddSetting("Regret Pedestals", "Settings", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        Default = true,
        CurrentSetting = function()
            return stopWithHourglass
        end,
        Display = function()
            if stopWithHourglass then return "Disable with Glowing Hourglass: true"
            else return "Disable with Glowing Hourglass: false" end
        end,
        OnChange = function(newvalue)
            stopWithHourglass = newvalue
            SaveModConfig()
        end,
        Info = {"Disable the apparation when holding Glowing Hourglass"}
    })

end

---------------------------------------------------------------
-- Blind detection (question mark sprite check)
---------------------------------------------------------------

local questionMarkSprite = Sprite()
questionMarkSprite:Load("gfx/005.100_collectible.anm2", true)
questionMarkSprite:ReplaceSpritesheet(1, "gfx/items/collectibles/questionmark.png")
questionMarkSprite:LoadGraphics()

local function isPedestalBlind(entity)
    local pedestalSprite = entity:GetSprite()
    local name = pedestalSprite:GetAnimation()

    if name ~= "Idle" and name ~= "ShopIdle" then
        return false
    end

    questionMarkSprite:SetFrame(name, pedestalSprite:GetFrame())

    -- Compare texels along the center column of the sprite
    for i = -70, 0, 2 do
        local qcolor = questionMarkSprite:GetTexel(Vector(0, i), Vector(0, 0), 1, 1)
        local ecolor = pedestalSprite:GetTexel(Vector(0, i), Vector(0, 0), 1, 1)

        if qcolor.Red ~= ecolor.Red or qcolor.Green ~= ecolor.Green or qcolor.Blue ~= ecolor.Blue then
            return false
        end
    end

    -- Check a few extra columns for certainty
    for j = -3, 3, 2 do
        for i = -71, 0, 2 do
            local qcolor = questionMarkSprite:GetTexel(Vector(j, i), Vector(0, 0), 1, 1)
            local ecolor = pedestalSprite:GetTexel(Vector(j, i), Vector(0, 0), 1, 1)

            if qcolor.Red ~= ecolor.Red or qcolor.Green ~= ecolor.Green or qcolor.Blue ~= ecolor.Blue then
                return false
            end
        end
    end

    return true
end

---------------------------------------------------------------
-- Tracking helpers
---------------------------------------------------------------

function findTrackedIndex(trackedList, entity)
    local hash = GetPtrHash(entity)
    for i, tracked in ipairs(trackedList) do
        if GetPtrHash(tracked.entity) == hash then
            return i
        end
    end
    return nil
end

function isTracked(entity)
    return findTrackedIndex(pedestalItemsInRoom, entity) ~= nil
        or findTrackedIndex(shopItemsInRoom, entity) ~= nil
end

---------------------------------------------------------------
-- Helper: check if any player is currently touching this pedestal
---------------------------------------------------------------

local function isPlayerPickingUp(pedestalEntityID)
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)

        if not player:IsItemQueueEmpty() and player.QueuedItem.Item:IsCollectible() and player.QueuedItem.Item.ID == pedestalEntityID then
            return true
        end
    end
    return false
end

---------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------

function mod:postPickupUpdate(entity)
    local addToList = true

    if not isTracked(entity) then
        for i=0, game:GetNumPlayers()-1 do
            local player = Isaac.GetPlayer(i)
            if player:GetActiveItem() == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS and stopWithHourglass then
                addToList = false
            end
        end

        if addToList then
            local entitySprite = entity:GetSprite()
            local name = entitySprite:GetAnimation()
            local blind = isPedestalBlind(entity)

            if name == "Idle" then
                table.insert(pedestalItemsInRoom, {entity = entity, subtype = entity.SubType, isBlind = blind})
            end
            if name == "ShopIdle" then
                table.insert(shopItemsInRoom, {entity = entity, subtype = entity.SubType, isBlind = blind})
            end
        end
    end
end

function mod:postNewRoom()
    pedestalItemsInRoom = {}
    shopItemsInRoom = {}
    disappearingPedestalItems = {}
    disappearingPedestalItemsFrame = {}
    disappearingShopItems = {}
    disappearingShopItemsFrame = {}
end

function mod:postRender()
    -- Iterate backwards so removal doesn't skip elements
    for index = #disappearingPedestalItems, 1, -1 do
        local item = disappearingPedestalItems[index]
        if item.subtype ~= 0 then
            local itemPos = Isaac.WorldToScreen(item.position)
            local spriteFile = Isaac.GetItemConfig():GetCollectible(item.subtype).GfxFileName

            itemSprite:ReplaceSpritesheet(1,spriteFile)
            itemSprite:LoadGraphics()
            local color = Color(1,1,1,(1-(disappearingPedestalItemsFrame[index]/60)))
            itemSprite.Color = color
            itemSprite:SetFrame("Idle", 0)

            itemPos.Y = itemPos.Y - disappearingPedestalItemsFrame[index]/10

            itemSprite:Render(itemPos, Vector(0,0), Vector(0,0))

            disappearingPedestalItemsFrame[index] = disappearingPedestalItemsFrame[index] + 1

            if disappearingPedestalItemsFrame[index] >= 60 then
                table.remove(disappearingPedestalItems, index)
                table.remove(disappearingPedestalItemsFrame, index)
            end
        end
    end
    for index = #disappearingShopItems, 1, -1 do
        local item = disappearingShopItems[index]
        if item.subtype ~= 0 then
            local itemPos = Isaac.WorldToScreen(item.position)
            local spriteFile = Isaac.GetItemConfig():GetCollectible(item.subtype).GfxFileName

            itemSprite:ReplaceSpritesheet(1,spriteFile)
            itemSprite:LoadGraphics()
            local color = Color(1,1,1,(1-(disappearingShopItemsFrame[index]/60)))
            itemSprite.Color = color
            itemSprite:SetFrame("ShopIdle", 0)

            itemPos.Y = itemPos.Y - disappearingShopItemsFrame[index]/10

            itemSprite:Render(itemPos, Vector(0,0), Vector(0,0))

            disappearingShopItemsFrame[index] = disappearingShopItemsFrame[index] + 1

            if disappearingShopItemsFrame[index] >= 60 then
                table.remove(disappearingShopItems, index)
                table.remove(disappearingShopItemsFrame, index)
            end
        end
    end
end

function mod:postUpdate()
    local pedestals = Isaac.FindByType(5, 100, -1, true, false)

    for index = #pedestalItemsInRoom, 1, -1 do
        local tracked = pedestalItemsInRoom[index]
        local stillExists = false
        local trackedPos = tracked.entity.Position
        for _, ped in ipairs(pedestals) do
            if GetPtrHash(ped) == GetPtrHash(tracked.entity) then
                stillExists = true
                if ped.SubType ~= tracked.subtype then
                    if tracked.isBlind and not isPlayerPickingUp(tracked.subtype) then
                        table.insert(disappearingPedestalItems, {subtype = tracked.subtype, position = Vector(trackedPos.X, trackedPos.Y)})
                        table.insert(disappearingPedestalItemsFrame, 0)
                    end
                    tracked.subtype = ped.SubType
                    tracked.isBlind = isPedestalBlind(ped)
                end
                break
            end
        end
        if not stillExists then
            if tracked.isBlind and not isPlayerPickingUp(tracked.subtype) then
                table.insert(disappearingPedestalItems, {subtype = tracked.subtype, position = Vector(trackedPos.X, trackedPos.Y)})
                table.insert(disappearingPedestalItemsFrame, 0)
            end
            table.remove(pedestalItemsInRoom, index)
        end
    end

    for index = #shopItemsInRoom, 1, -1 do
        local tracked = shopItemsInRoom[index]
        local stillExists = false
        local trackedPos = tracked.entity.Position
        for _, ped in ipairs(pedestals) do
            if GetPtrHash(ped) == GetPtrHash(tracked.entity) then
                stillExists = true
                if ped.SubType ~= tracked.subtype then
                    if tracked.isBlind and not isPlayerPickingUp(tracked.subtype) then
                        table.insert(disappearingShopItems, {subtype = tracked.subtype, position = Vector(trackedPos.X, trackedPos.Y)})
                        table.insert(disappearingShopItemsFrame, 0)
                    end
                    tracked.subtype = ped.SubType
                    tracked.isBlind = isPedestalBlind(ped)
                end
                break
            end
        end
        if not stillExists then
            if tracked.isBlind and not isPlayerPickingUp(tracked.subtype) then
                table.insert(disappearingShopItems, {subtype = tracked.subtype, position = Vector(trackedPos.X, trackedPos.Y)})
                table.insert(disappearingShopItemsFrame, 0)
            end
            table.remove(shopItemsInRoom, index)
        end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.postPickupUpdate, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.postNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.postUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.postRender)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.SaveStorage)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.SaveStorage)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.LoadStorage)
