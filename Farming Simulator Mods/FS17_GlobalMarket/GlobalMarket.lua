GlobalMarket = {};
GlobalMarket.activePlayer = nil;

function GlobalMarket:loadMap(name)
	self.initialized = false;
end;

function GlobalMarket:deleteMap()
end;

function GlobalMarket:keyEvent(unicode, sym, modifier, isDown)
end;

function GlobalMarket:mouseEvent(posX, posY, isDown, isUp, button)
end;

function preInit(self)
	GlobalMarket.activePlayer = nil;
	if g_dedicatedServerInfo == nil and g_server ~= nil then
		--singleplayer session
		--print("Well, since I am the server, I will be the GM Controller")
		GlobalMarket.activePlayer = g_currentMission.player;
	end;
	if g_dedicatedServerInfo == nil and g_server == nil then
		--mp session (client)
		--print("Lets ask the server if I should be the GM Controller")
		GlobalMarketControllerEvent:sendEvent(true, g_currentMission.player);
	end;

	GlobalMarket.enteringChatMessage  = false;
	GlobalMarket.chatMessage = "";
	GlobalMarket.chatMessageToSend = "";
	GlobalMarket.receivedChatMessage = "";
	GlobalMarket.receivedChatMessageTimer = 5000;

	GlobalMarket.Hud = {};
	GlobalMarket.Hud.Background = {};

	GlobalMarket.Hud.posX = 0.60468750145519;
	GlobalMarket.Hud.posY = 0.407;
	GlobalMarket.Hud.width = 0.39;
	GlobalMarket.Hud.height = 0.25;
	GlobalMarket.Hud.borderX = 0.004;
	GlobalMarket.Hud.borderY = GlobalMarket.Hud.borderX * (g_screenWidth / g_screenHeight);

	local img1 = Utils.getNoNil("img/Background.dds", "empty.dds" )

	local path = getUserProfileAppPath() .. '/mods/FS17_GlobalMarket/';

	local state, result = pcall( Utils.getFilename, img1, path )
	if not state then
		print("ERROR: "..tostring(result).." (img1: "..tostring(img1)..")")
		return
	end
	GlobalMarket.Hud.Background.img = result;
	GlobalMarket.Hud.Background.ov = Overlay:new(nil, result, GlobalMarket.Hud.posX, GlobalMarket.Hud.posY , GlobalMarket.Hud.width, GlobalMarket.Hud.height);
	GlobalMarket.Hud.Background.posX = GlobalMarket.Hud.posX;
	GlobalMarket.Hud.Background.posY = GlobalMarket.Hud.posY;
	GlobalMarket.Hud.Background.width = GlobalMarket.Hud.width;
	GlobalMarket.Hud.Background.height = GlobalMarket.Hud.height;

	self.preInitialized = true;

end

function init(self)

	if GlobalMarket.activePlayer ~= nil then

		self.commodities = {};
		self.storage = {};
		local commodityList = {"wheat","barley","rape","sunflower","soybean","maize","potato","sugarBeet","grass","dryGrass_windrow","forage","chaff","silage","straw","pigFood","grass_windrow","seeds","fertilizer","liquidManure","manure","milk"};
		local counter = 1;
		for _,item in pairs(commodityList) do
			self.commodities[FillUtil.fillTypeNameToInt[item]] = item;
			self.storage[FillUtil.fillTypeNameToInt[item]] = {name=item, price=500,amount=0,id=counter, bought=0,sold=0 };
			counter = counter + 1;
		end;

		--DebugUtil.printTableRecursively(FillUtil.fillTypeNameToInt, ":",0,3);

		if g_dedicatedServerInfo == nil then
			--load xml file
			self.ecoXml = nil;
			local path = getUserProfileAppPath() .. '/globalMarket';
			local file = path .. "/economy_data.xml";
			if fileExists(file) then
				--print("GM: Importing xml file from " .. file);
				self.ecoXml = loadXMLFile("economy_data", file);

				self.hub = getXMLString(self.ecoXml, "data.hub");
				self.useMoney = getXMLString(self.ecoXml, "data.useMoney");
				if self.useMoney == "1" then
					self.useMoney = true;
				elseif self.useMoney == "0" then
					self.useMoney = false;
				end;

				for index, name in pairs(FillUtil.fillTypeNameToInt) do
					--print("index: " .. index .. " name: " .. name);
				end;

				local counter = 1;
				local commodity = getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".name");

				while commodity ~= nil do
					local commodityPrice = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".price"));
					local commodityAmount = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".amount"));
					local commodityBought = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".bought"));
					local commoditySold = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".sold"));
					self.storage[FillUtil.fillTypeNameToInt[commodity]] = { name=commodity, price=commodityPrice, amount=commodityAmount, id=counter, bought=commodityBought, sold=commoditySold};
					self.commodities[FillUtil.fillTypeNameToInt[commodity]] = commodity;
					counter = counter + 1;
					commodity = getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".name");

				end;
			end;
			--print("GM: Finished importing XML");


			self.difficultyMulitplier = 1;
			if g_currentMission.missionInfo.difficulty == 2 then
				self.difficultyMulitplier = 2;
			end;
			if g_currentMission.missionInfo.difficulty == 1 then
				self.difficultyMulitplier = 2.5;
			end;
			if self.useMoney == false and self.hub ~= "global" then
				self.difficultyMulitplier = 0;
			end;
		end;

		self.globalTipTrigger = nil;
		self.globalSiloTrigger = nil;
		self.globalTipTarget = nil;
		self.foundTip = false;
		self.foundSilo = false;
		--print("GM: Loading TipTriggers");
		--DebugUtil.printTableRecursively(g_currentMission.tipTriggers, ":",0,3);
		for _,trigger in pairs(g_currentMission.tipTriggers) do
			if trigger.stationName == "station_GlobalMarket" then
				if self.foundTip ~= true then
					self.globalTipTrigger = trigger;
					local firstTarget = true;
					for target, index in pairs(trigger.tipTriggerTargets) do
						if firstTarget == true then
							self.globalTipTarget = target;
							firstTarget = false;
						end;
					end;
					--table.insert(self.globalTipTriggers, trigger)
					--DebugUtil.printTableRecursively(g_currentMission.economyManager, ":",0,3);
					--DebugUtil.printTableRecursively(trigger, ":",0,3);
				end;
				self.foundTip = true;
			end
		end
		--print("GM: Finished loading TipTriggers");

		--print("GM: Loading SiloTriggers");
		for _,trigger in pairs(g_currentMission.siloTriggers) do
			if trigger.globalMarket == true then
				--print("GM: Found matching tipTriggers");
				if self.foundSilo ~= true then
					--table.insert(self.globalSiloTriggers, trigger)
					self.globalSiloTrigger = trigger;
					self.foundSilo = true;
				end
			end
		end
		--print("GM: Finished Loading SiloTriggers")



		--print("GM: Initializing trigger.gM.savedFillLevels and changes")
		if self.foundTip then
			updateTipTriggerContent(self);
			self.globalTipTrigger.gM = {};
			self.globalTipTrigger.gM.savedFillLevels = {};
			self.globalTipTrigger.gM.storedFillLevels = {};
			self.globalTipTrigger.gM.changed = {};
			for fillType, name in pairs(self.commodities) do
				self.globalTipTrigger.gM.savedFillLevels[fillType] = self.globalTipTarget.fillLevels[fillType];
				self.globalTipTrigger.gM.storedFillLevels[fillType] = self.globalTipTarget.fillLevels[fillType];
				self.globalTipTrigger.gM.changed[fillType] = {amount=0, timer=0};
			end;
		end;

		if self.foundTip then
			print("GM: Found Tip Trigger")
			--DebugUtil.printTableRecursively(self.globalTipTriggers[1], ":",0,3);
			--DebugUtil.printTableRecursively(trigger, ":",0,5);
			if self.globalTipTrigger ~= nil and g_dedicatedServerInfo == nil then
				print("GM: Sending Tip Trigger content to server")
				GlobalMarketInputEvent:sendEvent(self.globalTipTrigger, self.globalTipTarget);
			end;
		end;
		if self.foundSilo then
			--print("GM: found Silo Trigger")
		end

		self.printTimer = 5000;
		self.reloadXMLTimer = 5000;
		self.alreadySendDelayedInfo = false

		self.initialized = true;
	end;

end


function GlobalMarket:update(dt)

	if not self.preInitialized then
		preInit(self)
	end;
	if GlobalMarket.activePlayer ~= nil then

		if not self.initialized then
			--print("Seems like I was designated as GM Controller. Let's do this!")
			init(self)
		end;

		if g_dedicatedServerInfo == nil and self.globalTipTrigger ~= nil then
			local hasChanged = false;
			for fillType, name in pairs(self.commodities) do

				local change = self.globalTipTrigger.gM.savedFillLevels[fillType] - self.globalTipTarget.fillLevels[fillType]
				--print("GM: savedLevel for type " .. fillType .. ": " .. trigger.gM.savedFillLevels[fillType] .. " current: " .. target.fillLevels[fillType] );
				if change ~= 0 then
					if self.globalTipTrigger.gM.changed[fillType].timer == 0 then
						self.globalTipTrigger.gM.storedFillLevels[fillType] =  self.globalTipTrigger.gM.savedFillLevels[fillType]
					end;
					self.globalTipTrigger.gM.savedFillLevels[fillType] = self.globalTipTarget.fillLevels[fillType]
					self.globalTipTrigger.gM.changed[fillType].amount = self.globalTipTrigger.gM.changed[fillType].amount + change;

					self.globalTipTrigger.gM.changed[fillType].timer=800;
					hasChanged = true;
					if change < 0 then
						--sold
					else
						--bought commodity
					end;
				end;
			end;


			self.changeTimerExpired = false;
			self.changeTimerActive = false;

			for fillType, name in pairs(self.commodities) do
				if self.globalTipTrigger.gM.changed[fillType].timer > 0 then
					self.changeTimerActive = true;
					self.globalTipTrigger.gM.changed[fillType].timer = self.globalTipTrigger.gM.changed[fillType].timer - dt;
					if self.globalTipTrigger.gM.changed[fillType].timer < 0 then
						self.globalTipTrigger.gM.changed[fillType].timer = 0;
						self.globalTipTrigger.gM.changed[fillType].amount = self.globalTipTrigger.gM.storedFillLevels[fillType] - self.globalTipTarget.fillLevels[fillType];
						self.changeTimerExpired = true;
					end;
				end;
			end;

			if self.changeTimerExpired == true then
				print("GM: Writing change to XML - Sending information to server");
				if self.globalTipTrigger ~= nil then
					GlobalMarketInputEvent:sendEvent(self.globalTipTrigger, self.globalTipTarget);
				end;
				writeChangeToXML(self);
			end;


			self.reloadXMLTimer = self.reloadXMLTimer -dt;
			if self.reloadXMLTimer < 0 then
				self.reloadXMLTimer = 5000;
				reloadXML(self);
				updateTipTriggerContent(self);
				checkServerHandled(self);
			end;
		end;

		if g_dedicatedServerInfo ~= nil then
			--print("Lets see if the GM Controller is still there")
			if networkGetObjectId(GlobalMarket.activePlayer) == nil then
				--print("I dont have an active GM Controller. Let's request one")
				GlobalMarketControllerEvent:sendEvent(false, nil);
			end;
		end;

		self.printTimer = self.printTimer -dt;
		if self.printTimer < 0 then
			self.printTimer = 12000;
			if self.globalTipTrigger ~= nil and g_dedicatedServerInfo == nil and self.alreadySendDelayedInfo == false then
				self.alreadySendDelayedInfo = true;
				GlobalMarketInputEvent:sendEvent(self.globalTipTrigger, self.globalTipTarget);
			end;
			--DebugUtil.printTableRecursively(g_currentMission.tipTriggers, ":",0,3);
		end;
	end;

	if InputBinding.hasEvent(InputBinding.GMChat) then
		if GlobalMarket.enteringChatMessage == false then
			GlobalMarket.enteringChatMessage  = true;
			GlobalMarket.chatMessage = "";
			g_currentMission.isPlayerFrozen = true;
			if g_currentMission.controlledVehicle ~= nil then
				g_currentMission.controlledVehicle.isBroken = true;
			end;
		end;
	end;

	if GlobalMarket.receivedChatMessage ~= "" then

		if GlobalMarket.receivedChatMessageTimer >= 0 then
			GlobalMarket.receivedChatMessageTimer = GlobalMarket.receivedChatMessageTimer - dt;
		end;
	end;

end;

function GlobalMarket:keyEvent(unicode, sym, modifier, isDown)

	if isDown and GlobalMarket.enteringChatMessage then
		if sym == 13 then
			GlobalMarket.enteringChatMessage = false;
			if g_currentMission.controlledVehicle ~= nil then
				g_currentMission.controlledVehicle.isBroken = false
			end;
			g_currentMission.isPlayerFrozen = false;

			GlobalMarket.chatMessageToSend = GlobalMarket.chatMessage;
			GlobalMarket.chatMessage = "";

			reloadXML(self);
			writeChangeToXML(self);
		else
			if sym == 8 then
				GlobalMarket.chatMessage = string.sub(GlobalMarket.chatMessage,1,string.len(GlobalMarket.chatMessage)-1)
			else
				if unicode ~= 0 then
					--print("GM: Entered unicode: " .. unicode);
					local new_char = string.char(unicode);
					if unicode ~= 32 then
						new_char = new_char:gsub('%W','')
					end;
					GlobalMarket.chatMessage = GlobalMarket.chatMessage .. new_char;
				end;
			end;
		end;
	end;
end;

function writeChangeToXML(self)
	--print("GM: Writing change to XML");

	setXMLString(self.ecoXml, "data.username", g_currentMission.missionInfo.playerName );

	local enteredOneChange = false;

	for fillType, name in pairs(self.commodities) do
		if self.globalTipTrigger.gM.changed[fillType].amount ~= 0 and enteredOneChange == false then
			enteredOneChange = true;
			if self.globalTipTrigger.gM.changed[fillType].amount > 0 then
				setXMLString(self.ecoXml, "data.commodities.commodity_" .. self.storage[fillType].id .. ".bought", "" .. math.floor(math.abs(self.globalTipTrigger.gM.changed[fillType].amount) ));
			else
				setXMLString(self.ecoXml, "data.commodities.commodity_" .. self.storage[fillType].id .. ".sold", "" .. math.floor(math.abs(self.globalTipTrigger.gM.changed[fillType].amount)) );
			end;
		end;
	end;

	if GlobalMarket.chatMessageToSend ~= "" then
		--print("GM: Writing chatMessage to xml: " .. GlobalMarket.chatMessageToSend);
		setXMLString(self.ecoXml, "data.chatMessageOut", GlobalMarket.chatMessageToSend );
		GlobalMarket.chatMessageToSend = "";
	end;

	saveXMLFile(self.ecoXml);
end

function checkServerHandled(self)

	for fillType, name in pairs(self.commodities) do
		if self.globalTipTrigger.gM.changed[fillType].amount ~= 0 then
			if self.storage[fillType].bought == 0 and self.storage[fillType].sold == 0 and self.changeTimerActive == false then
				local money = self.globalTipTrigger.gM.changed[fillType].amount * self.storage[fillType].price * -0.001 * self.difficultyMulitplier;
				if money < 0 then
					money = money * 1.1;
				end;
				if g_server ~= nil then
					g_currentMission:addSharedMoney(money, "other");
					g_currentMission:addMoneyChange(money, FSBaseMission.MONEY_TYPE_SINGLE, true, g_i18n:getText("finance_other"));
					g_currentMission:showMoneyChange(FSBaseMission.MONEY_TYPE_SINGLE);
				else
					GlobalMarketMoneyEvent:sendEvent(self.globalTipTrigger,money);
				end;
				print("added money: " .. money);
				self.globalTipTrigger.gM.changed[fillType].amount = 0;
			end;
		end;
	end;
end

function reloadXML(self)
	if g_dedicatedServerInfo == nil then
		--load xml file
		self.commodities = {};
		self.ecoXml = nil;
		local path = getUserProfileAppPath() .. '/globalMarket';
		local file = path .. "/economy_data.xml";
		if fileExists(file) then
			--print("GM: Importing xml file from " .. file);
			self.ecoXml = loadXMLFile("economy_data", file);

			self.hub = getXMLString(self.ecoXml, "data.hub");

			local counter = 1;
			local commodity = getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".name");
			self.storage = {};
			while commodity ~= nil do
				local commodityPrice = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".price"));
				local commodityAmount = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".amount"));
				local commodityBought = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".bought"));
				local commoditySold = tonumber(getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".sold"));

				self.storage[FillUtil.fillTypeNameToInt[commodity]] = { name=commodity, price=commodityPrice, amount=commodityAmount, id=counter, bought=commodityBought, sold=commoditySold};
				self.commodities[FillUtil.fillTypeNameToInt[commodity]] = commodity;
				counter = counter + 1;
				commodity = getXMLString(self.ecoXml, "data.commodities.commodity_" .. counter .. ".name");
			end;

			local receivedChatMessage = getXMLString(self.ecoXml, "data.chatMessageIn");
			if receivedChatMessage ~= "" and receivedChatMessage ~= nil and receivedChatMessage ~= GlobalMarket.receivedChatMessage then
				GlobalMarket.receivedChatMessage = receivedChatMessage
				GlobalMarket.receivedChatMessageTimer = 5000;
				--print("GM: Received chat message: " .. GlobalMarket.receivedChatMessage);
			end;

		end;
	end;
end

function updateTipTriggerContent(self)
	--print("GM: Updating Tip Triggers")
	local updatedContent = false;
	for fillType, name in pairs(self.commodities) do
		--dont reload fill levels unless current change has been applied
		if self.storage[fillType].bought == 0 and self.storage[fillType].sold == 0 then
			if self.globalTipTrigger.gM ~= nil then
				if self.globalTipTrigger.gM.changed[fillType].timer > 0 then
					--print("Returning because of timer > 0");
					return;
				else
					--print("Updating fill level of: " .. fillType .. " to amount: " .. self.storage[fillType].amount);
					if self.globalTipTarget.fillLevels[fillType] ~= self.storage[fillType].amount then
						updatedContent = true;
					end;
					self.globalTipTarget.fillLevels[fillType] = self.storage[fillType].amount;
					if self.globalTipTrigger.gM ~= nil then
						self.globalTipTrigger.gM.savedFillLevels[fillType] = self.storage[fillType].amount;
					end;
				end;
			else
				--print("Updating fill level of: " .. fillType .. " to amount: " .. self.storage[fillType].amount);
				self.globalTipTarget.fillLevels[fillType] = self.storage[fillType].amount;
				if self.globalTipTrigger.gM ~= nil then
					self.globalTipTrigger.gM.savedFillLevels[fillType] = self.storage[fillType].amount;
				end;
			end;
		else
			--print("dont reload fill levels unless current change has been applied");
		end;
	end;

	if updatedContent then
		--print("GM: Writing change to XML - Sending information to server");
		GlobalMarketInputEvent:sendEvent(self.globalTipTrigger, self.globalTipTarget);
	end;

end

function GlobalMarket:draw()
	if GlobalMarket.Hud ~= nil then

		if GlobalMarket.enteringChatMessage then
			GlobalMarket.Hud.Background.ov:render();
			local adFontSize = 0.02;
			local adPosX = GlobalMarket.Hud.posX + 0.04
			local adPosY = GlobalMarket.Hud.posY + 0.09
			renderText(adPosX, adPosY, adFontSize, "Enter Chat Message, then press 'Enter'");
		end;

		if (GlobalMarket.receivedChatMessage ~= nil and GlobalMarket.receivedChatMessage ~= "" and GlobalMarket.receivedChatMessageTimer > 0) then
			GlobalMarket.Hud.Background.ov:render();
		end;

		if GlobalMarket.chatMessage ~= nil and GlobalMarket.chatMessage ~= "" then
			local adFontSize = 0.03;
			local adPosX = GlobalMarket.Hud.posX + 0.04
			local adPosY = GlobalMarket.Hud.posY + 0.04
			setTextColor(1,1,1,1);
			renderText(adPosX, adPosY, adFontSize, GlobalMarket.chatMessage);
		end;

		if GlobalMarket.receivedChatMessage ~= nil and GlobalMarket.receivedChatMessage ~= "" and GlobalMarket.receivedChatMessageTimer > 0 then
			local adFontSize = 0.03;
			local adPosX = GlobalMarket.Hud.posX + 0.04
			local adPosY = GlobalMarket.Hud.posY + 0.13
			setTextColor(1,1,1,1);
			renderText(adPosX, adPosY, adFontSize, GlobalMarket.receivedChatMessage);

			adPosY = GlobalMarket.Hud.posY + 0.17
			adFontSize = 0.02;
			renderText(adPosX, adPosY, adFontSize, "Global Market Chat");

		end;
	end;

end;

addModEventListener(GlobalMarket);


--InputEvent%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
--InputEvent%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
--InputEvent%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


GlobalMarketInputEvent = {};
GlobalMarketInputEvent_mt = Class(GlobalMarketInputEvent, Event);

InitEventClass(GlobalMarketInputEvent, "GlobalMarketInputEvent");

function GlobalMarketInputEvent:emptyNew()
	local self = Event:new(GlobalMarketInputEvent_mt);
	self.className="GlobalMarketInputEvent";
	return self;
end;

function GlobalMarketInputEvent:new(trigger,target)
	local self = GlobalMarketInputEvent:emptyNew()
	self.trigger = trigger;
	self.target = target;

	self.counter = 0;
	self.fillLevels = {};

	for fillType, fillLevel in pairs(target.fillLevels) do
		self.fillLevels[fillType] = fillLevel;
		self.counter = self.counter + 1;
	end;
	--print("event new")
	return self;
end;

function GlobalMarketInputEvent:writeStream(streamId, connection)
	streamWriteInt32(streamId, networkGetObjectId(self.trigger));
	streamWriteInt32(streamId, networkGetObjectId(self.target));

	streamWriteInt32(streamId, self.counter);
	for fillType, fillLevel in pairs(self.fillLevels) do
		streamWriteInt32(streamId, fillType);
		streamWriteInt32(streamId, fillLevel);
	end;
	--print("event writeStream")
end;

function GlobalMarketInputEvent:readStream(streamId, connection)
	--print("Received Event");
	if g_dedicatedServerInfo ~= nil then
		local id = streamReadInt32(streamId);
		local trigger = networkGetObject(id);
		local idTarget = streamReadInt32(streamId);
		local target = networkGetObject(idTarget);

		local counter = streamReadInt32(streamId);
		while counter > 0 do
			local fillType = streamReadInt32(streamId);
			local fillLevel = streamReadInt32(streamId);
			counter = counter - 1;
			if target ~= nil then
				target.fillLevels[fillType] = fillLevel;
			else
				print("No target found");
			end;
		end;


		g_server:broadcastEvent(GlobalMarketInputEvent:new(trigger,target), nil, nil, trigger);
		-- print("broadcasting")
	end;
end;

function GlobalMarketInputEvent:sendEvent(trigger,target)
	if g_server ~= nil then
		--g_server:broadcastEvent(GlobalMarketInputEvent:new(trigger), nil, nil, trigger);
		-- print("broadcasting")
	else
		g_client:getServerConnection():sendEvent(GlobalMarketInputEvent:new(trigger,target));
		-- print("sending event to server...")
	end;
end;


GlobalMarketMoneyEvent = {};
GlobalMarketMoneyEvent_mt = Class(GlobalMarketMoneyEvent, Event);

InitEventClass(GlobalMarketMoneyEvent, "GlobalMarketMoneyEvent");

function GlobalMarketMoneyEvent:emptyNew()
	local self = Event:new(GlobalMarketMoneyEvent_mt);
	self.className="GlobalMarketMoneyEvent";
	return self;
end;

function GlobalMarketMoneyEvent:new(trigger, money)
	local self = GlobalMarketMoneyEvent:emptyNew()
	self.money = money
	self.trigger = trigger
	--print("event new")
	return self;
end;

function GlobalMarketMoneyEvent:writeStream(streamId, connection)
	streamWriteInt32(streamId, networkGetObjectId(self.trigger));

	streamWriteInt32(streamId, self.money);
	--print("event writeStream")
end;

function GlobalMarketMoneyEvent:readStream(streamId, connection)
	--print("Received Event");
	if g_dedicatedServerInfo ~= nil then
		local id = streamReadInt32(streamId);
		local trigger = networkGetObject(id);
		local money = streamReadInt32(streamId);

		g_currentMission:addSharedMoney(money, "other");
		g_currentMission:addMoneyChange(money, FSBaseMission.MONEY_TYPE_SINGLE, true, g_i18n:getText("finance_other"));
		g_currentMission:showMoneyChange(FSBaseMission.MONEY_TYPE_SINGLE);

	end;
end;

function GlobalMarketMoneyEvent:sendEvent(trigger,money)
	if g_server ~= nil then
		--g_server:broadcastEvent(GlobalMarketMoneyEvent:new(trigger), nil, nil, trigger);
		-- print("broadcasting")
	else
		g_client:getServerConnection():sendEvent(GlobalMarketMoneyEvent:new(trigger,money));
		-- print("sending event to server...")
	end;
end;


GlobalMarketControllerEvent = {};
GlobalMarketControllerEvent_mt = Class(GlobalMarketControllerEvent, Event);

InitEventClass(GlobalMarketControllerEvent, "GlobalMarketControllerEvent");

function GlobalMarketControllerEvent:emptyNew()
	local self = Event:new(GlobalMarketControllerEvent_mt);
	self.className="GlobalMarketControllerEvent";
	return self;
end;

function GlobalMarketControllerEvent:new(clientActive, player)
	local self = GlobalMarketControllerEvent:emptyNew()
	self.clientActive = clientActive;
	self.client = networkGetObjectId(player);
	if self.client == nil then
		--print ("No networkObjectId found. Setting it to 0 to prevent an error while sending");
		self.client = 0;
		self.clientActive = false;
	else
		--print("Found matching objectID: " .. self.client);
	end;
	--print("event new")
	return self;
end;

function GlobalMarketControllerEvent:writeStream(streamId, connection)
	streamWriteInt32(streamId, self.client);

	streamWriteBool(streamId, self.clientActive);
	--print("event writeStream")
end;

function GlobalMarketControllerEvent:readStream(streamId, connection)
	--print("Received Controller Event");
	local player_id = streamReadInt32(streamId);
	self.sendPlayer = nil;
	if player_id ~= 0 then
		self.sendPlayer = networkGetObject(player_id);
		if self.sendPlayer == nil then
			--print("Found no matching objectID while reading the event. ID : " .. player_id);
		end;
	end;
	local active = streamReadBool(streamId);
	if g_dedicatedServerInfo == nil then
		if active then
			if g_currentMission.player == self.sendPlayer then
				--print("Correct player received. setting myself as active")
				GlobalMarket.activePlayer = self.sendPlayer;
			else
				--print("I am no longer the cool kid on the block. GM Controller is another player")
				GlobalMarket.activePlayer = nil;
			end;
		else
			--print("Server seems to be missing an active GM Controller. Let's apply for the job! Fingers crossed :D")
			GlobalMarketControllerEvent:sendEvent(true, g_currentMission.player);
		end;

	else
		if	GlobalMarket.activePlayer == nil or networkGetObjectId(GlobalMarket.activePlayer) == nil then
			--print( "New player received. Setting him as GM Controller since nobody else seems to be responsible");
			GlobalMarket.activePlayer = self.sendPlayer;
			g_server:broadcastEvent(GlobalMarketControllerEvent:new(true,self.sendPlayer), nil, nil, self.sendPlayer);
		end;

	end;
end;

function GlobalMarketControllerEvent:sendEvent(clientActive, player)
	if g_server ~= nil then
		g_server:broadcastEvent(GlobalMarketControllerEvent:new(clientActive, player), nil, nil, player);
		-- print("broadcasting")
	else
		g_client:getServerConnection():sendEvent(GlobalMarketControllerEvent:new(clientActive,player));
		-- print("sending event to server...")
	end;
end;
