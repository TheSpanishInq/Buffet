
----------------------
--      Locals      --
----------------------

local defaults = {macroHP = "#showtooltip\n%MACRO%", macroMP = "#showtooltip\n%MACRO%"}
local ids, dirty = LibStub("tekIDmemo"), false

-----------------------------
--      Event Handler      --
-----------------------------

local Buffet = Buffet or CreateFrame("Frame","Buffet")
Buffet:RegisterEvent("PLAYER_LOGIN")
Buffet:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end)

function Buffet:Print(...) ChatFrame1:AddMessage(string.join(" ", "|cFF33FF99Buffet|r:", ...)) end

function Buffet:PLAYER_LOGIN()
	BuffetDB = setmetatable(BuffetDB or {}, {__index = defaults})
	self.db = BuffetDB

	self:RegisterEvent("PLAYER_LOGOUT")

	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("PLAYER_LEVEL_UP")

--	self:Scan()

	self:UnregisterEvent("PLAYER_LOGIN")
	self.PLAYER_LOGIN = nil
end


function Buffet:PLAYER_LOGOUT()
	for i,v in pairs(defaults) do if self.db[i] == v then self.db[i] = nil end end
end


function Buffet:PLAYER_REGEN_ENABLED()
	if dirty then self:Scan() end
end


function Buffet:BAG_UPDATE_DELAYED()
	dirty = true
	if not InCombatLockdown() then self:Scan() end
end
Buffet.PLAYER_LEVEL_UP = Buffet.BAG_UPDATE_DELAYED

function Buffet:Scan()

	-- Create a separate tooltip to avoid messing with the game one
	CreateFrame( "GameTooltip", "BuffetTooltip", nil, "GameTooltipTemplate" ); -- Tooltip name cannot be nil
	BuffetTooltip:SetOwner( WorldFrame, "ANCHOR_NONE" );

	-- These are initialising our various resources
	local Drink = {0,nil,0}
	local Food = {0,nil,0}
	local ManaPot = {0,nil,0}
	local HealthPot = {0,nil,0}
	local Bandage = {0,nil,0}

	-- Flip through the bags
	for BuffetBagNo = 0,4 do 

		-- Check each slot the bag
		for BuffetSlotNo = 1,GetContainerNumSlots(BuffetBagNo) do

			-- Grab the item ID and the number in that slot
			_, itemCount, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(BuffetBagNo,BuffetSlotNo) 

			-- If we didn't find anything in that slot, move on to the next
			if itemID then

				-- Grab various details about the item in that slot
				itemName, itemLink, _, _, itemMinLevel, itemType, itemSubType, _, _, _, _, _, _, bindType = GetItemInfo(itemID)

				-- No point continueing if it's armour, or junk etc
				if (itemType == "Consumable" or itemSubType == "Reagent") and UnitLevel("player") >= itemMinLevel then

					-- Read the tooltip for the item
					local itemToolTip = ""
					BuffetTooltip:SetBagItem(BuffetBagNo,BuffetSlotNo)
					for k=BuffetTooltip:NumLines(),2,-1 do
						itemToolTip = itemToolTip .. " " .. (_G["BuffetTooltipTextLeft"..k]:GetText() or "")
					end

					-- Not yet included the few items that are listed as 
					-- Use: do the thing with the thing, restoring x amount of y...
					-- due to complexity over total amounts given etc.

					-- Health:
					-- Use: Restores %d+%% of your health and mana per second for $d+ sec.
					-- Use: Restores %d+%% of your health per second for %d+ sec.
					-- Use: Restores %d+%% health and %d+%% mana over $d+ sec.		- Conjured
					-- Use: Restores [%d,]+ health and [%d,]+ mana over $d+ sec.
					-- Use: Restores [%d,]+ health over %d+ sec.
					-- Use: Instantly restores %d+%% health. (1 Min Cooldown)		- Healthstone

					-- Mana:
					-- Use: Restores %d+%% of your health and mana per second for $d+ sec.
					-- Use: Restores %d+%% of your mana per second for $d+ sec.
					-- Use: Restores [%d,]+ health and [%d,]+ mana over $d+ sec.
					-- Use: Restores [%d,]+ mana over %d+ sec.

					-- Get only the output for the types we want
					local Restores = nil
					if itemSubType == "Food & Drink" or itemSubType == "Reagent" then
						Restores = itemToolTip:match("Use: Restores .* %d+ sec.")
					elseif itemSubType == "Potion" then
						Restores = itemToolTip:match("Use: Restores .* Cooldown%)") 
					elseif itemSubType == "Other" then
						Restores = itemToolTip:match("Use: Instantly restores .* Cooldown%)")
					elseif itemSubType == "Bandage" then
						Restores = itemToolTip:match("Use: Heals .* %d+ sec.")
					else
--						Buffet:Print("Failed;", itemLink, itemSubType)
					end

					-- If it buffs a number of people, it's a feast - don't want to use that
					if Restores then

						-- Look through the tooltip for x% health (Second is for conjured)
						local Health = itemToolTip:match("(%d+%%) of your health") or itemToolTip:match("(%d+%%) health")

						-- If you get it, then multiply the % by your max health to find true value
						if Health then
							Health = gsub(Health,"%%","")
							Health = tonumber(Health) * UnitHealthMax("player")
						else
							-- If not, look for a specific health value
							Health = itemToolTip:match("([%d,]+) health")
						end

						-- Nothing to do unless we found a value
						if Health then
						
							-- Is it x amount per sec, or in total?
							local Multiplier = itemToolTip:match("per second for (%d+) sec")
							if not Multiplier then
								Multiplier = 1
							end

							Health = gsub(Health,",","")
							Health = tonumber(Health) * tonumber(Multiplier)

							-- If it's better than the previous best, or the same but we have fewer, this is the new best
							-- Food
							if itemSubType == "Food & Drink" or itemSubType == "Reagent" then
								if Health > Food[1] or (Health == Food[1] and itemCount < Food[3]) then
									Food = {Health,itemID,itemCount}
								end

							-- Health Potion
							elseif itemSubType == "Potion" or itemSubType == "Other" then
								if Health > HealthPot[1] or (Health == HealthPot[1] and itemCount < HealthPot[3]) then
									HealthPot = {Health,itemID,itemCount}
								end
						
							-- Bandage
							elseif itemSubType == "Bandage" then
								if Health > Bandage[1] or (Health == Bandage[1] and itemCount < Bandage[3]) then
									Bandage = {Health,itemID,itemCount}
								end
							end
						end

						-- Look through the tooltip for x% mana
						local Mana = itemToolTip:match("(%d+%%) of your health and mana") or itemToolTip:match("(%d+%%) Mana")

						-- If you get it, then multiply the % by your max mana to find true value
						if Mana then
							Mana = gsub(Mana,"%%","")
							Mana = tonumber(Mana) * UnitPowerMax("player",0)
						else

							-- If not, look for a specific mana value
							Mana = itemToolTip:match("([%d,]+) mana")
						end

						-- Nothing to do unless we found a value
						if Mana then
							Mana = gsub(Mana,",","")
							Mana = tonumber(Mana)

							-- If it's better than the previous best, or the same but we have fewer, this is the new best
							-- Drink
							if itemSubType == "Food & Drink" then
								if Mana > Drink[1] or (Mana == Drink[1] and itemCount < Drink[3]) then
									Drink = {Mana,itemID,itemCount}
								end

							-- Mana Potion
							elseif itemSubType == "Potion" then
								-- Add to MAna Pot table
								if Mana > ManaPot[1] or (Mana == ManaPot[1] and itemCount < ManaPot[3]) then
									ManaPot = {Mana,itemID,itemCount}
								end
							end
						end

						-- Just debug output, basically to let me know if there's another string format for these items.
						if not Mana and not Health then
							Buffet:Print("Unknown Tooltip;", Restores, "on item", itemLink)
						end
					end
				end
			end
		end 
	end

	-- Now rewrite the macros with the values we found on items in our bags
	self:Edit("AutoHP", self.db.macroHP, Food[2], HealthPot[2], Bandage[2])
	self:Edit("AutoMP", self.db.macroMP, Drink[2], ManaPot[2])

	dirty = false
end


function Buffet:Edit(name, substring, food, pot, mod)
	local macroid = GetMacroIndexByName(name)
	if not macroid then return end

	local body = "/use "
	if mod then body = body .. "[mod,target=player] item:"..mod.."; " end
	if pot then body = body .. "[combat] item:"..pot.."; " end
	body = body.."item:"..(food or "6948")

	EditMacro(macroid, name, "INV_Misc_QuestionMark", substring:gsub("%%MACRO%%", body), 1)
end
