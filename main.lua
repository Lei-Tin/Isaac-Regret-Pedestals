-- ORIGINAL SOURCE: https://github.com/seanstertm/Isaac-Regret-Pedestals
-- Forked version

mod = RegisterMod("New Regret Pedestals", 1)

local stopWithHourglass = true

local prevPedestalData = {}                -- {[pickupIndex] = {subtype, position, isBlind, isShop, itemSet}}
local disappearingPedestalItems = {}
local disappearingPedestalItemsFrame = {}
local disappearingShopItems = {}
local disappearingShopItemsFrame = {}
local poofPositions = {}                   -- positions of POOF01 effects this frame

local itemSprite = Sprite()
itemSprite:Load("gfx/005.100_collectible.anm2",true)

local questionMarkSprite = Sprite()
questionMarkSprite:Load("gfx/005.100_collectible.anm2", true)
questionMarkSprite:ReplaceSpritesheet(1, "gfx/items/collectibles/questionmark.png")
questionMarkSprite:LoadGraphics()

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
        Info = {"Disable the apparition when holding Glowing Hourglass"}
    })

end

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------

--- Detect if a pedestal is showing the blind (question mark) sprite
--- by comparing texels against the known question mark graphic.
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

--- Convert an itemSet ({[id]=true, ...}) to a sorted list of IDs.
local function itemSetToSortedList(itemSet)
    local list = {}
    for itemID in pairs(itemSet) do
        table.insert(list, itemID)
    end
    table.sort(list)
    return list
end

---------------------------------------------------------------
-- Helper: check if any player is currently picking up this item
---------------------------------------------------------------

local function isPlayerPickingUp(collectibleID)
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)

        if not player:IsItemQueueEmpty() and player.QueuedItem.Item:IsCollectible() and player.QueuedItem.Item.ID == collectibleID then
            return true
        end
    end
    return false
end

---------------------------------------------------------------
-- Helper: check Glowing Hourglass
---------------------------------------------------------------

local function isGlowingHourglassActive()
    if not stopWithHourglass then return false end
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player:GetActiveItem() == CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS then
            return true
        end
    end
    return false
end

---------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------

function mod:postNewRoom()
    prevPedestalData = {}
    disappearingPedestalItems = {}
    disappearingPedestalItemsFrame = {}
    disappearingShopItems = {}
    disappearingShopItemsFrame = {}
    poofPositions = {}
end

local ITEM_SPACING = 20  -- pixels between each item in a multi-item ghost

local function renderDisappearingList(list, frameList, animName)
    for index = #list, 1, -1 do
        local item = list[index]
        local subtypes = item.subtypes
        if #subtypes > 0 then
            local basePos = Isaac.WorldToScreen(item.position)
            local frame = frameList[index]
            local alpha = 1 - (frame / 60)
            local color = Color(1, 1, 1, alpha)
            local yOffset = -frame / 10

            -- Center the group around the pedestal position
            local totalWidth = (#subtypes - 1) * ITEM_SPACING
            local startX = basePos.X - totalWidth / 2

            for i, subtype in ipairs(subtypes) do
                if subtype ~= 0 then
                    local cfg = Isaac.GetItemConfig():GetCollectible(subtype)
                    if cfg then
                        itemSprite:ReplaceSpritesheet(1, cfg.GfxFileName)
                        itemSprite:LoadGraphics()
                        itemSprite.Color = color
                        itemSprite:SetFrame(animName, 0)

                        local drawPos = Vector(startX + (i - 1) * ITEM_SPACING, basePos.Y + yOffset)
                        itemSprite:Render(drawPos, Vector(0, 0), Vector(0, 0))
                    end
                end
            end

            frameList[index] = frame + 1
            if frameList[index] >= 60 then
                table.remove(list, index)
                table.remove(frameList, index)
            end
        end
    end
end

function mod:postRender()
    renderDisappearingList(disappearingPedestalItems, disappearingPedestalItemsFrame, "Idle")
    renderDisappearingList(disappearingShopItems, disappearingShopItemsFrame, "ShopIdle")
end

---------------------------------------------------------------
-- Poof detection helper
---------------------------------------------------------------
local function hasPoofAtPosition(pos)
    for _, poofPos in ipairs(poofPositions) do
        if pos:Distance(poofPos) < 1.0 then
            return true
        end
    end
    return false
end

function mod:postPoofInit(effect)
    table.insert(poofPositions, Vector(effect.Position.X, effect.Position.Y))
end

function mod:postUpdate()
    if isGlowingHourglassActive() then
        prevPedestalData = {}
        poofPositions = {}
        return
    end

    -- Build Index -> entity lookup from actual room entities
    local pedestals = Isaac.FindByType(5, 100, -1, true, false)
    local currentEntities = {}  -- pickupIndex -> entity
    for _, ped in ipairs(pedestals) do
        if ped.SubType ~= 0 then
            currentEntities[ped.Index] = ped
        end
    end

    -- Check if all previous items are still there
    for pickupIndex, prev in pairs(prevPedestalData) do
        local ped = currentEntities[pickupIndex]

        if not ped then
            local count = 0
            for _ in pairs(prev.itemSet) do count = count + 1 end
            local isCycling = count > 1

            if isCycling and isPlayerPickingUp(prev.subtype) then
                -- Player picked up from a cycling pedestal: show the other options
                local others = {}
                for itemID in pairs(prev.itemSet) do
                    if itemID ~= prev.subtype then
                        table.insert(others, itemID)
                    end
                end
                table.sort(others)
                if #others > 0 then
                    local list = prev.isShop and disappearingShopItems or disappearingPedestalItems
                    local frameList = prev.isShop and disappearingShopItemsFrame or disappearingPedestalItemsFrame
                    table.insert(list, {subtypes = others, position = Vector(prev.position.X, prev.position.Y)})
                    table.insert(frameList, 0)
                end
            elseif prev.isBlind and not isPlayerPickingUp(prev.subtype) then
                -- Blind pedestal disappeared (reroll / despawn)
                local list = prev.isShop and disappearingShopItems or disappearingPedestalItems
                local frameList = prev.isShop and disappearingShopItemsFrame or disappearingPedestalItemsFrame
                table.insert(list, {subtypes = itemSetToSortedList(prev.itemSet), position = Vector(prev.position.X, prev.position.Y)})
                table.insert(frameList, 0)
            end
        else
            -- Item is still there but became different
            if ped.SubType ~= prev.subtype then
                local count = 0
                for _ in pairs(prev.itemSet) do count = count + 1 end
                local isCycling = count > 1

                if hasPoofAtPosition(ped.Position) and prev.isBlind and not isPlayerPickingUp(prev.subtype) then
                    -- Poof + blind + not picking up = reroll: show what was there
                    local isShop = ped:GetSprite():GetAnimation() == "ShopIdle" or prev.isShop
                    local list = isShop and disappearingShopItems or disappearingPedestalItems
                    local frameList = isShop and disappearingShopItemsFrame or disappearingPedestalItemsFrame
                    table.insert(list, {subtypes = itemSetToSortedList(prev.itemSet), position = Vector(ped.Position.X, ped.Position.Y)})
                    table.insert(frameList, 0)
                elseif not hasPoofAtPosition(ped.Position) and isPlayerPickingUp(prev.subtype) then
                    -- No poof + picking up = Tainted Isaac swap: show other cycle options or blind item
                    if isCycling and prev.isBlind then
                        local others = {}
                        for itemID in pairs(prev.itemSet) do
                            if itemID ~= prev.subtype then
                                table.insert(others, itemID)
                            end
                        end
                        table.sort(others)
                        if #others > 0 then
                            local isShop = ped:GetSprite():GetAnimation() == "ShopIdle" or prev.isShop
                            local list = isShop and disappearingShopItems or disappearingPedestalItems
                            local frameList = isShop and disappearingShopItemsFrame or disappearingPedestalItemsFrame
                            table.insert(list, {subtypes = others, position = Vector(ped.Position.X, ped.Position.Y)})
                            table.insert(frameList, 0)
                        end
                    elseif prev.isBlind then
                        local isShop = ped:GetSprite():GetAnimation() == "ShopIdle" or prev.isShop
                        local list = isShop and disappearingShopItems or disappearingPedestalItems
                        local frameList = isShop and disappearingShopItemsFrame or disappearingPedestalItemsFrame
                        table.insert(list, {subtypes = {prev.subtype}, position = Vector(ped.Position.X, ped.Position.Y)})
                        table.insert(frameList, 0)
                    end
                end
            end
        end
    end

    -- Snapshot current state for the next frame
    local newPrevData = {}
    for idx, ped in pairs(currentEntities) do
        local prev = prevPedestalData[idx]

        -- Blind: carry forward from cache; only run the expensive texel check
        -- on first encounter or after a reroll. Clear when player touches it.
        local isBlind
        if prev then
            if isPlayerPickingUp(prev.subtype) then
                isBlind = false
            else
                isBlind = prev.isBlind
            end
        else
            isBlind = isPedestalBlind(ped)
        end

        -- Track cycling items: accumulate on cycle, reset on reroll
        local itemSet = {}
        local rerolledThisFrame = hasPoofAtPosition(ped.Position)

        -- If no poof, it means we are just cycling
        if rerolledThisFrame then
            -- Reroll wipes the cycle history; start fresh with the new item
            itemSet[ped.SubType] = true
        else
            -- Carry forward previously observed items (cycling accumulates)
            if prev then
                for itemID in pairs(prev.itemSet) do
                    itemSet[itemID] = true
                end
            end
            itemSet[ped.SubType] = true
        end

        newPrevData[idx] = {
            subtype  = ped.SubType,
            position = Vector(ped.Position.X, ped.Position.Y),
            isBlind  = isBlind,
            isShop   = (ped:GetSprite():GetAnimation() == "ShopIdle") or (prev and prev.isShop) or false,
            itemSet  = itemSet,
        }
    end
    prevPedestalData = newPrevData

    -- Clear poof positions at end of frame
    poofPositions = {}
end

-- POOF01 is the reroll effect
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.postPoofInit, EffectVariant.POOF01)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.postNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.postUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.postRender)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.SaveStorage)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.SaveStorage)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.LoadStorage)
