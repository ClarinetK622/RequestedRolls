--Overrides the function ActionsManger.roll so that the popup roll page can be managed just like manual rolls
--Added original function to fall through if not overridden
local fRollOriginal = nil;
local fonTowerDrop = nil;
local fchatOnDrop = nil;

function onInit()
	fRollOriginal = ActionsManager.roll;
    ActionsManager.roll = rollOverride;

    --New overrides
    fonTowerDrop = DiceTowerManager.onDrop;
    DiceTowerManager.onDrop = towerDropOverride;
    fchatOnDrop = ChatManager.onDrop
    ChatManager.onDrop = chatDropOverride
    ActionsManager.actionDrop = dropOverride;
    ActionsManager.actionRoll = actionRollOverride;
    ActionsManager.applyModifiersAndRoll = applyModifiersAndRollOverride;

	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_APPLYROLL, handleApplyRollRR);
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_ALLROLLS, handleAllRollsRR);
end

---Helper function for if strings start with a certain sequence
---@param String string the string to search
---@param Start string the string it should start with
---@return boolean boolean if string starts with the given sequence
function starts(String,Start)
	return string.sub(String,1,string.len(Start))==Start
end

OOB_MSGTYPE_APPLYROLL = "applyrollRR";
OOB_MSGTYPE_ALLROLLS = "allrollsRR";

--the default roll types that originate on host
local sTypes = {
	["concentration"] = { },
	["death_auto"] = { },
	["stabilization"] = { }
};

--a list of the start of sSaveDesc that should trigger a popup
--[ONGOING SAVE is for Better Combat Effects
local saveDescs = {
	"[SAVE VS","[ONGOING SAVE"
};

---Registers rolls that are created on the host side that need to be sent to the client for popup
---@param newType string the new roll type to be registered
function registerRollType(newType)
	sTypes[newType] = {};
end

---Unregisters rolls added via registerRollType
---@param sType string the roll type to be unregistered
function unregisterRollType(sType)
	if sTypes then
		sTypes[sType] = nil;
	end
end

---Registers rolls that have a sSaveDesc that starts with a specific string as needing to be shown as popup. These can originate on host or client.
---@param newDesc string the new sSaveDesc to be unregistered
function registerSaveDescription(newDesc)
	table.insert(saveDescs, newDesc);
end

---Unregisters rolls added via registerRollDescription
---@param sDesc string the sSaveDesc to be unregistered
function unregisterSaveDescription(sDesc)
	for i,s in ipairs(saveDescs) do
		if s==sDesc then
			table.remove(saveDescs,i);
			return;
		end
	end
end

---Determines whether a given rolls save description is registered as a popup
---@param sDesc string the string to be checked
---@return boolean bool is this is a popup type save
function isPopupSaveDesc(sDesc)
	for i,s in ipairs(saveDescs) do
		if starts(sDesc,s) then
			return true;
		end
	end
	return false;
end

--Set modifiers to false
function resetMods()
	if not ModifierManager.isLocked() then
		ModifierManager.setKey("ADV",false)
		ModifierManager.setKey("DIS",false)
		ModifierManager.setKey("PLUS2",false)
		ModifierManager.setKey("MINUS2",false)
		ModifierManager.setKey("PLUS5",false)
		ModifierManager.setKey("MINUS5",false)
		ModifierStack.reset()
	end
end

--Encode mods in rRoll.sDesc similar to ActionsManager2.encodeDesktopMods but without adding to rRoll.nMod (for SAVE VS rolls this modifies the DC) and adds a call to resetMods
function encodeMods(rRoll)
	local nMod = 0;
	
	if ModifierManager.getKey("PLUS2") then
		nMod = nMod + 2;
	end
	if ModifierManager.getKey("MINUS2") then
		nMod = nMod - 2;
	end
	if ModifierManager.getKey("PLUS5") then
		nMod = nMod + 5;
	end
	if ModifierManager.getKey("MINUS5") then
		nMod = nMod - 5;
	end

	nMod = nMod + ModifierStack.getSum()
	
	resetMods()

	if nMod == 0 then
		return;
	end

	rRoll.sDesc = rRoll.sDesc .. string.format(" [%+d]", nMod);
end

--Transfer host mods from sSaveDesc to sDesc
function transferMods(rRoll)
	if Interface.getRuleset()=="5E" and rRoll.aDice[1] == "d20" then

		local modTotal = 0
		local sDescADV = string.match(rRoll.sDesc, "%[ADV%]")
		local sDescDIS = string.match(rRoll.sDesc, "%[DIS%]")

		if rRoll.sSaveDesc then

			local bADV = string.match(rRoll.sSaveDesc, "%[ADV%]");
			local bDIS = string.match(rRoll.sSaveDesc, "%[DIS%]");
			local bPlusMod = string.match(rRoll.sSaveDesc, "%[%+%d+%]")
			local bMinusMod = string.match(rRoll.sSaveDesc, "%[%-%d+%]")

			if (bADV or bDIS) then
				--If neither ADV nor DIS are pre-encoded and ADV and DIS buttons are not simultaneously pressed add one die
				if (not sDescADV and not sDescDIS) and not (bADV and bDIS) then
					table.insert(rRoll.aDice, 2, rRoll.aDice[1]);
					rRoll.aDice.expr = nil;
				--If contradictory ADV DIS apply, remove die
				elseif (sDescADV and bDIS) or (sDescDIS and bADV) then
					table.remove(rRoll.aDice, 2);
				end
				if bADV then
	                rRoll.sDesc = rRoll.sDesc .. " [ADV]";
	            end
	            if bDIS then
	                rRoll.sDesc = rRoll.sDesc .. " [DIS]";
	            end
			end
			--Handle and encode modifiers
			if (bPlusMod or bMinusMod) then
				if bPlusMod then
					local modNum = tonumber(string.match(bPlusMod, "[^%[%]%+]+"))
					modTotal = modTotal + modNum
	            else
	            	local modNum = tonumber(string.match(bMinusMod, "[^%[%]%-]+"))
					modTotal = modTotal - modNum
	            end
				_,_, rRoll.sDesc = string.find(rRoll.sDesc, "(.*) %[[+-]%d+%]")
			end
		end
		if modTotal ~= 0 then
			if modTotal > 0 then
				rRoll.sDesc = rRoll.sDesc .. " [+" .. tostring(modTotal) .. "]";
			else
				rRoll.sDesc = rRoll.sDesc .. " [" .. tostring(modTotal) .. "]";
			end
        end
		if rRoll.nMod then
			rRoll.nMod = rRoll.nMod + modTotal
		end
	end
end

--Overrides the onDrop function in DiceTowerManager to allow rerouting of roll to standard dropOverride
function towerDropOverride(draginfo)
	if draginfo.bRR then
		draginfo.bTower = true
		dropOverride(draginfo)
		return true
	end
	return fonTowerDrop(draginfo)
end

--Overrides the onDrop function of ChatManager to interrupt and reroute throw to standard dropOverride
function chatDropOverride(draginfo)
	if draginfo.bTower then
		dropOverride(draginfo, rTarget)
		return true
	else
		return fchatOnDrop(draginfo)
	end
end

--Overrides actionDrop function of ActionsManager to appropriately handle dragged RR rolls
function dropOverride(draginfo, rTarget)
	local sDragType = draginfo.getType();
	if not GameSystem.actions[sDragType] then
		return false;
	end
	
	local rSource, rRolls = ActionsManager.decodeActionFromDrag(draginfo, false);

	--Start inserted code
	--Decode RR metadata from draginfo and repopulate global vars
	if draginfo.bRR then
		vRoll = rRolls[1]
		vRoll.bTower = draginfo.bTower
		vSource = draginfo.vSource
		vTargets = draginfo.vTargets

		--Close roll entry window
		if draginfo.window then
			draginfo.window.close();
		end

		if vRoll.bTower then
			RRTowerManager.sendTower(vRoll, vSource, vTargets);
			return true
		end

		--Throw dice if roll is not hidden
		local rThrow = ActionsManager.buildThrow(vSource, vTargets, vRoll, true);
		Comm.throwDice(rThrow);
		return true
	end

	local aTargeting = {};
	if rTarget or ModifierStack.getTargeting() then
		aTargeting = ActionsManager.getTargeting(rSource, rTarget, sDragType, rRolls);
	else
		aTargeting = { { } };
	end

	actionRollOverride(rSource, aTargeting, rRolls, draginfo);
		
	return true;
end

--Overrides actionRoll function of ActionsManager to pass through draginfo with RR metadata and clear modifiers after performing or requesting roll
function actionRollOverride(rSource, vTarget, rRolls, draginfo)
	local bModStackUsed = false;
	ActionsManager.lockModifiers();
	
	for _,vTargetGroup in ipairs(vTarget) do
		for _,vRoll in ipairs(rRolls) do
			if applyModifiersAndRollOverride(rSource, vTargetGroup, true, vRoll, draginfo) then
				bModStackUsed = true;
			end
		end
	end
	
	ActionsManager.unlockModifiers(bModStackUsed);
	resetMods()
end

--Override of applyModifiersAndRoll function of ActionsManager to pass through draginfo with RR metadata
function applyModifiersAndRollOverride(rSource, vTarget, bMultiTarget, rRoll, draginfo)
	
	--Reset mods prior to encoding modifiers if receiving a SAVE VS popup
	if rRoll.sSaveDesc and isPopupSaveDesc(rRoll.sSaveDesc) then
		resetMods()
	end
	
	local rNewRoll = UtilityManager.copyDeep(rRoll);
	local bModStackUsed = false;

	if bMultiTarget then
		if vTarget and #vTarget == 1 then
			bModStackUsed = ActionsManager.applyModifiers(rSource, vTarget[1], rNewRoll);
		else
			-- Only apply non-target specific modifiers before roll
			bModStackUsed = ActionsManager.applyModifiers(rSource, nil, rNewRoll);
		end
	else
		bModStackUsed = ActionsManager.applyModifiers(rSource, vTarget, rNewRoll);
	end

	--If roll originates from an RR drag, trigger draggedRoll function, otherwise pass to overridden ActionsManager.roll
	if draginfo ~= nil and draginfo.bRR then
		draggedRoll(rSource, vTarget, rRoll, bMultiTarget);
	else
		ActionsManager.roll(rSource, vTarget, rNewRoll, bMultiTarget);
	end
	
	return bModStackUsed;
end

function draggedRoll(rSource, vTargets, rRoll, bMultiTarget)
	if ActionsManager.doesRollHaveDice(rRoll) then
		DiceManager.onPreEncodeRoll(rRoll);
		
		local rThrow = ActionsManager.buildThrow(rSource, vTargets, rRoll, bMultiTarget);
		Comm.throwDice(rThrow);
	else
		if bMultiTarget then
			ActionsManager.handleResolution(rRoll, rSource, vTargets);
		else
			ActionsManager.handleResolution(rRoll, rSource, { vTargets });
		end
	end
end 

---Overrides the roll function in ActionManager so that we can add RR rolls after all normal processing has happened
---@param rSource table mirrors original function
---@param vTargets table|nil mirrors original function
---@param rRoll table mirrors original function
---@param bMultiTarget boolean mirrors original function
function rollOverride(rSource, vTargets, rRoll, bMultiTarget)
	--check to see if there is a player connected this should roll to if the host is set to auto-roll
	local sOwner = getControllingClient(rSource);
	local bBypass = false;
	if Session.IsHost == true and DB.getValue("requestsheet.autoroll", 0) == 1 then
		if sOwner then
			bBypass = false;
		else
			bBypass = true;
		end
	end

	--If recieving a tower throw, do not catch and show host popup
	if not bBypass then
		bBypass = rRoll.bReturnTower
	end

	--Transfer host mods from sSaveDesc even if bypassing
	if ActionsManager.doesRollHaveDice(rRoll) then

		--Reset client mods before encoding roll
		resetMods()
		transferMods(rRoll)

		if not bBypass then
			DiceManager.onPreEncodeRoll(rRoll);
			--start where the new code is inserted
			--Checks if this save could be a roll that needs to be added but wasn't generated from console
			--For VS rolls, it is assumed they are already executing on the intended client for PC rolls
			--For NPC VS rolls, we have to send these as popups to the relevant client
			if rRoll.sSaveDesc and isPopupSaveDesc(rRoll.sSaveDesc) then
				if Session.IsHost == true and sOwner then
					rRoll.RR = true;
					rRoll.bPopup = true;
				else
					if Session.IsHost == true then
						if (RR.isManualSaveRollPcOn() and ActorManager.isPC(rSource)) or (RR.isManualSaveRollNpcOn() and not ActorManager.isPC(rSource)) then
							ManualRollManager.addRoll(rRoll, rSource, vTargets);
							return;
						end
					else
						if RR.isManualSaveRollPcOn() then
							ManualRollManager.addRoll(rRoll, rSource, vTargets);
							return;
						end
					end
				end
			end
		end
		--death auto and concentration rolls originate on host. They need to be sent to the players to check for the popup setting
		--stabilization is for 3.5E and PFRPG1 and 2
		if Session.IsHost == true then
			if rRoll.sType and sTypes[rRoll.sType] then 
				rRoll.RR = true; 
				rRoll.bPopup = true;
			end
		end

		--rRoll.RR is only set when generated from the console or caught by an override so we can guarantee it needs to be displayed to user
		if rRoll.RR then
			notifyApplyRoll(rRoll, rSource, vTargets);
			return;
		end
		--end of new code insertion
	end
	--pass through if it wasn't caught to be displayed to user

	--Encode host advantage if there are no dice (SAVE VS)
	if not ActionsManager.doesRollHaveDice(rRoll) then
		ActionsManager2.encodeAdvantage(rRoll,bButtonADV,bButtonDIS)
		encodeMods(rRoll)
	end

	return fRollOriginal(rSource, vTargets, rRoll, bMultiTarget);
end

---Processes console rolls received
---@param msgOOB table the OOB message for adding the roll to manualRolls
function handleApplyRollRR(msgOOB)
	local rRoll, rSource, vTargets = deOOBifyAction(msgOOB);
	--If the roll is being passed because of popup status and the user is set to get the popup rolls, add it to the manual rolls.
	--On clients, NPCs and PCs share the PC setting so only one check is needed
	--Otherwise roll directly
	if Session.IsHost == true then
		if rRoll.bPopup and not ((RR.isManualSaveRollPcOn() and ActorManager.isPC(rSource)) or (RR.isManualSaveRollNpcOn() and not ActorManager.isPC(rSource))) then
			local rThrow = ActionsManager.buildThrow(rSource, vTargets, rRoll, true);
			Comm.throwDice(rThrow);
			return;
		end
	else
		if rRoll.bPopup and not RR.isManualSaveRollPcOn() then
			local rThrow = ActionsManager.buildThrow(rSource, vTargets, rRoll, true);
			Comm.throwDice(rThrow);
			return;
		end
	end
	
	ManualRollManager.addRoll(rRoll, rSource, vTargets);


end

---Takes an action with the three parameters and turns it into an OOB msg
---@param rRoll table the same info to be passed to the manualRolls
---@param rSource table the same info to be passed to the manualRolls
---@param vTargets table the same info to be passed to the manualRolls
---@param sType string the OOB_MSGTYPE to be assigned
---@return table msgOOB
function OOBifyAction(rRoll, rSource, vTargets, sType)
	local msgOOB = {};
	if RR.bDebug then Debug.chat("rRoll", rRoll); end
	if RR.bDebug then Debug.chat("rSource", rSource); end
	if RR.bDebug then Debug.chat("vTargets", vTargets); end
	msgOOB.type = sType;

	msgOOB.rRoll = Utility.encodeJSON(rRoll);
	if rSource then 
		--ongoing save effects codes the actor as a string, this is to catch if other people do that as wellfa
		if type(rSource) ~= "table" then rSource = ActorManager.resolveActor(rSource); end
		msgOOB.rSource = Utility.encodeJSON(rSource);
	 end
	if vTargets then msgOOB.vTargets = Utility.encodeJSON(vTargets); end
	return msgOOB;
end

---Takes an OOB msg of an action and turns it back into tables
---@param msgOOB table the received OOB msg
---@return table rRoll 
---@return table|nil rSource
---@return table|nil vTargets
function deOOBifyAction(msgOOB)
	if RR.bDebug then Debug.chat("postMsgOOB",msgOOB); end
	local rRoll = Utility.decodeJSON(msgOOB.rRoll);
	local rSource = nil;
	if msgOOB.rSource then rSource = Utility.decodeJSON(msgOOB.rSource); end
	local vTargets = nil;
	if msgOOB.vTargets then vTargets = Utility.decodeJSON(msgOOB.vTargets); end;
	if vTargets and #vTargets==0 then
		vTargets=nil;
	end

	--clear client mods
	if rRoll.RR then
		resetMods()
	end

	return rRoll, rSource, vTargets;
end


---Creates the outgoing roll for the user, passes the completed message to needsBroadcast for distribution
---@param rRoll table the same info to be passed to the manualRolls
---@param rSource table the same info to be passed to the manualRolls
---@param vTargets table the same info to be passed to the manualRolls
function notifyApplyRoll(rRoll, rSource, vTargets)
	local msgOOB = OOBifyAction(rRoll, rSource, vTargets, OOB_MSGTYPE_APPLYROLL);

	needsBroadcast(rSource, msgOOB);
end

---Checks if the rSource is connected. If so they player is sent an OOBmsg that processes all the rolls. 
---@param rSource table the database node for the CTNODE
---@param bMakeRoll boolean true to make rolls, false to delete
function notifyAllRolls(rSource, bMakeRoll)
	local sOwner = getControllingClient(rSource);
	if sOwner then
		local msgOOB = {};
		msgOOB.type = OOB_MSGTYPE_ALLROLLS;
		msgOOB.sCTNodeID = ActorManager.getCTNodeName(rSource);
		if bMakeRoll then
			msgOOB.bMakeRoll = "true";
		else
			msgOOB.bMakeRoll = "false";
		end
		Comm.deliverOOBMessage(msgOOB, sOwner);

		local msg = {font = "systemfont", icon = "portrait_gm_token"};
		if bMakeRoll then
			msg.text = Interface.getString("RR_msg_rollAll_GM")..ActorManager.getDisplayName(rSource);
		else
			msg.text = Interface.getString("RR_msg_rollCancel_GM")..ActorManager.getDisplayName(rSource);
		end
		Comm.addChatMessage(msg);
	else
		ChatManager.SystemMessage(Interface.getString("RR_msg_rollNotConnected"));
	end
end

---Opens the manual roll window and makes all the rolls for the given CTNode using the custom control I added
---Also, posts a message so the player knows what happened
---@param msgOOB table the message from notifyMakeAllRolls
function handleAllRollsRR(msgOOB)
	local sCTNodeID = msgOOB.sCTNodeID;
	local bMakeRoll = msgOOB.bMakeRoll == "true";
	local wMain = Interface.openWindow("manualrolls", "");
	local bActioned = false;
	for _,vEntry in pairs(wMain.list.getWindows()) do
		if vEntry.CTNodeID.getValue() == sCTNodeID then
			bActioned = true;
			if bMakeRoll then
				vEntry.processRoll();
			else
				vEntry.processCancel();
			end
		end
	end
	if bActioned then
		local msg = {font = "systemfont", icon = "portrait_gm_token"};
		if bMakeRoll then
			msg.text = Interface.getString("RR_msg_rollAll_player")
		else
			msg.text = Interface.getString("RR_msg_rollCancel_player")
		end
		Comm.addChatMessage(msg);
	end
end

---This determines whether to broadcast or handle the oobmsg locally.
---This is a separate function from the notifyApplyRoll so that I can use the return to end execution early
---@param rSource table	passed through from notifyApplyRoll, determines who the message gets sent to
---@param msgOOB string the message from notifyApplyRoll
function needsBroadcast(rSource, msgOOB)
	
	local sOwner = getControllingClient(rSource);
	if sOwner then
		Comm.deliverOOBMessage(msgOOB, sOwner);
		return;
	end
    handleApplyRollRR(msgOOB);
end

---For a given actor, determines who the owning client is and if they are connected. Returns nil for inactive identities and those owned by the GM
---@param rActor table the actor who the owner needs to be determined for
---@return string|nil sOwner the controlling client if they are connected. otherwise returns nil
function getControllingClient(rActor)
	local isControlled = false;
	local sNode = nil;
	if ActorManager.isPC(rActor) then
		sNode = ActorManager.getCreatureNodeName(rActor);
	else
		if FriendZone and FriendZone.isCohort(rActor) then
			sNode = getRootCommander(rActor);
		end
	end

	--There will be an active identity if the client is connected. If sNode is still nil, nothing will be found
	for _, value in pairs(User.getAllActiveIdentities()) do
		if "charsheet." .. value == sNode then
			isControlled = true;
		end
	end
	
	if isControlled then
		return DB.getOwner(sNode);
	else
		return nil;
	end	
end

---For a given cohort actor, determine the root character node that owns it
---@param rActor table the actor we need the root commander for
---@return string|nil nodePath the root character node of the chain
function getRootCommander(rActor)
	local sRecord = ActorManager.getCreatureNodeName(rActor);
	local sRecordSansModule = StringManager.split(sRecord, "@")[1];
	local aRecordPathSansModule = StringManager.split(sRecordSansModule, ".");
	if aRecordPathSansModule[1] and aRecordPathSansModule[2] then
		return aRecordPathSansModule[1] .. "." .. aRecordPathSansModule[2];
	end
	return nil;
end