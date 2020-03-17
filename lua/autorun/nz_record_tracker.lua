local global_data = {}
local index_data = {}
local map_data = {}

if SERVER then
	AddCSLuaFile()
	
	file.CreateDir("nz_records/meta")
	resource.AddWorkshop("1930243232")
	util.AddNetworkString("record_tracker_congrats")
	util.AddNetworkString("record_tracker_gui")
	util.AddNetworkString("record_tracker_gui_map")
	
	local current_map = game.GetMap()
	
	local global_path = "nz_records/meta/global.txt"
	local global_read = file.Read(global_path, "DATA")
	local global_record_beaten = false
	local global_wave = 0
	
	local index_path = "nz_records/meta/index.json"
	local index_read = file.Read(index_path, "DATA")
	local kill_threshold = 100
	
	local map_path = "nz_records/" .. current_map .. ".json"
	local map_read = file.Read(map_path, "DATA")
	local map_record_beaten = false
	
	local player_tracker = {}
	local ply_meta = FindMetaTable("Player")
	local pretty_print = true
	
	if global_read then global_wave = tonumber(global_read) 
	else global_wave = 0 end
	
	if map_read then
		--
		map_data = util.JSONToTable(map_read)
	else
		map_data.contributors = {}
		map_data.wave = 0
	end
	
	local function congratulate_players()
		--tells the client side what message to give and to praise them
		net.Start("record_tracker_congrats")
		net.WriteBool(global_record_beaten)
		
		if not global_record_beaten then net.WriteUInt(global_data.wave, 32) end
		
		net.Broadcast()
	end
	
	local function update_data(round, path)
		--save the record
		local data = {}
		data.contributors = table.Copy(player_tracker)
		data.wave = round
		
		--we use their steam id 64 so we can load their avatars for the gui
		--we also concatenate S to their IDs to make sure they are kept as strings when we decode the JSON
		for _, ply in pairs(player.GetHumans()) do
			data.contributors["S" .. ply:SteamID64()] = {["kills"] = math.floor(ply:GetTotalKills()), ["name"] = ply:Nick()}
		end
		
		file.Write(path, util.TableToJSON(data, pretty_print))
		
		return data
	end
	
	local function update_global(round)
		--
		file.Write(global_path, tostring(global_wave))
	end
	
	local function update_index()
		index_data.maps[current_map] = math.floor(map_data.wave)
		
		file.Write(index_path, util.TableToJSON(index_data, pretty_print))
	end
	
	if index_read then
		--
		index_data = util.JSONToTable(index_read)
		
		if not index_data.maps[current_map] then
			update_index()
		end
	else
		--we use the update_index() function here so we have to do it after we declare the function
		index_data.maps = {}
		
		update_index()
	end
	
	concommand.Add("nz_record_tracker_gui", function(ply)
		--send the record data
		net.Start("record_tracker_gui")
		net.WriteTable(index_data)
		net.Send(ply)
	end, nil, "Opens the gloryboard for the highest waves beaten.")
	
	hook.Add("OnRoundCreative", "prog_bar_onroundend_hook", function() player_tracker = {} end)
	hook.Add("OnRoundEnd", "prog_bar_onroundend_hook", function() player_tracker = {} end)
	hook.Add("OnRoundPreparation", "nz_record_tracker_prep_hook", function(round)
		--check if they are making records
		if round > global_wave then
			map_data = update_data(round, map_path)
			
			update_global(round)
			update_index()
			
			if not global_record_beaten then
				map_record_beaten = true
				global_record_beaten = true
				
				congratulate_players()
			end
		elseif round > map_data.wave then
			map_data = update_data(round, map_path)
			
			update_index()
			
			if not map_record_beaten then
				map_record_beaten = true
				
				congratulate_players()
			end
		end
	end)
		hook.Add("PlayerDisconnected", "nz_record_tracker_disc_hook", function(ply)
		print("nzRound.Number " .. nzRound.Number)
		
		local kills = ply:GetTotalKills()
		
		if kills and kills > kill_threshold then
			player_tracker["S" .. ply:SteamID64()] = {["kills"] = ply:GetTotalKills(), ["name"] = ply:Nick(), ["wave"] = nzRound.Number}
		end
	end)
	
	net.Receive("record_tracker_gui_map", function(len, ply)
		local check_map_name = net.ReadString()
		local check_map_path = "nz_records/" .. check_map_name .. ".json"
		local check_map_read = file.Read(check_map_path, "DATA")
		
		if check_map_read then
			local decoded = util.JSONToTable(check_map_read)
			local filtered_data = table.Copy(decoded)
			filtered_data.contributors = {}
			
			for k, v in pairs(decoded.contributors) do
				filtered_data.contributors[string.sub(k, 2)] = v
			end
			
			net.Start("record_tracker_gui_map")
			net.WriteTable(filtered_data)
			net.Send(ply)
		else
			print("[nZombies Record Tracker] CRITICAL ERROR! Could not read '" .. check_map_path .. "'. Request was sent from ")
		end
	end)
elseif CLIENT then
	local function activate_sound()
		--play the celebration sound
		surface.PlaySound("nz_record_tracker/woot_" .. math.random(1, 19) .. ".wav")
	end
	
	local chat_button = nil
	local chosen_map = ""
	local frame_chooser = {}
	local frame_chooser_is_open = false
	local frame_chooser_map_chosen = false
	local frame_h = 0
	local frame_w = 0
	local frame_x = 0
	local frame_y = 0
	local scr_h = 0
	local scr_w = 0
	
	local function calc_vars()
		scr_h = ScrH()
		scr_w = ScrW()
		
		frame_h = 1080 / scr_h * 800
		frame_w = 1920 / scr_w * 400
		frame_x = (scr_w - frame_w) / 2
		frame_y = (scr_h - frame_h) / 2
	end
	
	local function congratulate()
		--play confetti from the center of the player and play celebration sounds
		for i = 1, math.random(5, 8) do
			--play less sounds at a longer delay, and more at a shorter delay
			timer.Simple(math.Rand(0, 1.73205080757) ^ 2, activate_sound)
		end
		
		--no need to do complex toWorld calculations as the players angles do not matter.
		--OBBCenter is just used here to make the particle appear at half height of the player
		ParticleEffect("bday_confetti", LocalPlayer():OBBCenter() + LocalPlayer():GetPos(), Angle(0, 0, 0))
	end
	
	calc_vars()
	
	--cache colors and functions we use for rendering. It saves frames!
	--as a wise man once said, C A C H E   E V E R Y T H I N G
	local color_bright_white = Color(240, 240, 240)
	local color_bright_white_select = Color(232, 232, 232)
	local color_dark_white = Color(208, 208, 208)
	local color_frame_white = Color(224, 224, 224)
	local color_nazi = Color(131, 41, 41)
	local color_nazi_select = Color(115, 32, 32)
	local surf_SetDrawColor = surface.SetDrawColor
	local surf_DrawRect = surface.DrawRect
	
	hook.Add("OnScreenSizeChanged", "prog_bar_screen_res_changed_hook", calc_vars())
	
	net.Receive("record_tracker_congrats", function()
		--when a record is beat, check if it was map or global then congratulate accordingly
		local global_record_beaten = net.ReadBool()
		
		if global_record_beaten then chat.AddText(Color(127, 127, 255), "Congratulations, you beat the server's record for highest wave!")
		else chat.AddText(Color(127, 255, 127), "Congratulations, you beat the map's record for highest wave! Now try to beat the server's all-time record of ", Color(255, 255, 127), net.ReadUInt(32), Color(127, 255, 127), ".") end
		
		congratulate()
	end)
	
	net.Receive("record_tracker_gui", function()
		if frame_chooser_is_open then frame_chooser:Close() end
		
		--the frame that shows the maps and their highest wave
		index_data = net.ReadTable()
		
		--the client requested the GUI to be opened and the info has been recieved.
		frame_chooser = vgui.Create("DFrame")
		frame_chooser_is_open = true
		local map_order = {}
		
		frame_chooser:SetDraggable(false)
		frame_chooser:SetPos(frame_x, frame_y)
		frame_chooser:SetSize(frame_w, frame_h)
		frame_chooser:SetTitle("Gloryboard")
		frame_chooser:SetVisible(true)
		frame_chooser:ShowCloseButton(true)
		frame_chooser.Paint = function(self, w, h)
			surf_SetDrawColor(color_frame_white)
			surf_DrawRect(0, 0, w, h)
			
			surf_SetDrawColor(color_nazi)
			surf_DrawRect(0, 0, w, 24)
		end
		
		frame_chooser.OnClose = function() frame_chooser_is_open = false end
		
		local scroll = vgui.Create("DScrollPanel", frame_chooser)
		local scroll_bar = scroll:GetVBar()
		
		scroll:Dock(FILL)
		scroll_bar:SetHideButtons(true)
		
		for map, wave in SortedPairsByValue(index_data.maps) do
			--
			table.insert(map_order, 1, {map, wave})
		end
		
		function scroll_bar:Paint(w, h)
			surf_SetDrawColor(color_dark_white)
			surf_DrawRect(0, 0, w, h)
		end
		
		function scroll_bar.btnGrip:Paint(w, h)
			surf_SetDrawColor(color_nazi)
			surf_DrawRect(0, 0, w, h)
		end
		
		local scroll_bar_margin = (frame_h * 0.1 + 5) * #map_order + 29 > frame_h and 5 or 0
		
		for _, set in pairs(map_order) do
			local button = scroll:Add("DButton")
			
			button:Dock(TOP)
			button:DockMargin(0, 0, scroll_bar_margin, 5)
			button:SetSize(frame_w - 24, frame_h * 0.1)
			button:SetText(set[1] .. " - Wave " .. set[2])
			button:SetTextColor(color_nazi)
			button.Paint = function(self, w, h)
				if button:IsHovered() then surf_SetDrawColor(color_bright_white_select)
				else surf_SetDrawColor(color_bright_white) end
				
				surf_DrawRect(0, 0, w, h)
			end
			
			button.DoClick = function()
				--keep them from spamming the server
				if not frame_chooser_map_chosen then
					chosen_map = set[1]
					frame_chooser_map_chosen = true
					
					--if they never get a response, allow them to click again
					timer.Create("record_tracker_gui_timer", 2, 1, function() frame_chooser_map_chosen = false end)
					
					net.Start("record_tracker_gui_map")
					net.WriteString(set[1])
					net.SendToServer()
				end
			end
		end
		
		frame_chooser:MakePopup()
	end)
	
	net.Receive("record_tracker_gui_map", function()
		--the frame that shows the players who made the record and their kills
		local frame = vgui.Create("DFrame")
		frame_chooser_map_chosen = false
		local local_player_id = LocalPlayer():SteamID64()
		local player_order = {}
		local player_organizer = {}
		local sent_data = net.ReadTable()
		
		if frame_chooser_is_open then frame_chooser:Close() end
		
		timer.Remove("record_tracker_gui_timer")
		
		frame:SetDraggable(false)
		frame:SetPos(frame_x, frame_y)
		frame:SetSize(frame_w, frame_h)
		frame:SetTitle("Gloryboard - " .. chosen_map)
		frame:SetVisible(true)
		frame:ShowCloseButton(true)
		frame.Paint = function(self, w, h)
			surf_SetDrawColor(color_frame_white)
			surf_DrawRect(0, 0, w, h)
			
			surf_SetDrawColor(color_nazi)
			surf_DrawRect(0, 0, w, 24)
		end
		
		local scroll = vgui.Create("DScrollPanel", frame)
		local scroll_bar = scroll:GetVBar()
		
		scroll:Dock(FILL)
		scroll_bar:SetHideButtons(true)
		
		for id64, info in pairs(sent_data.contributors) do
			--first, create a table that can be sorted
			player_organizer[id64] = info.kills
		end
		
		for id64, kills in SortedPairsByValue(player_organizer) do
			--now create the the odered table
			table.insert(player_order, 1, {id64, sent_data.contributors[id64].name, kills, sent_data.contributors[id64].wave})
		end
		
		function scroll_bar:Paint(w, h)
			surf_SetDrawColor(color_dark_white)
			surf_DrawRect(0, 0, w, h)
		end
		
		function scroll_bar.btnGrip:Paint(w, h)
			surf_SetDrawColor(color_nazi)
			surf_DrawRect(0, 0, w, h)
		end
		
		local scroll_bar_margin = (frame_h * 0.06 + 5) * #player_order + 29 > frame_h and 5 or 0
		
		for _, set in pairs(player_order) do
			local button = scroll:Add("DButton")
			
			button:Dock(TOP)
			button:DockMargin(0, 0, scroll_bar_margin, 5)
			button:SetSize(frame_w - scroll_bar_margin - 5, frame_h * 0.06)
			button:SetText("")
			
			button.DoClick = function()
				--open their profile
				gui.OpenURL("http://steamcommunity.com/profiles/" .. set[1])
			end
			
			local avatar = vgui.Create("AvatarImage", button)
			local button_w, button_h = button:GetSize()
			local avatar_size = button_h - 10
			
			print("Size: " .. button_w .. ", " ..button_h)
			
			--{id64, name, kills, wave}
			
			avatar:SetSteamID(set[1], 64)
			avatar:SetPos(5, 5)
			avatar:SetSize(avatar_size, avatar_size)
			
			label = vgui.Create("DLabel", button)
			label:SetContentAlignment(4)
			label:SetPos(button_h, 0)
			label:SetSize(button_w - button_h, button_h)
			label:SetText(set[4] and (set[2] .. "\nLeft on wave " .. set[4] .. "\n" .. set[3] .. " kills") or (set[2] .. "\n\n" .. set[3] .. " kills"))
			
			if local_player_id == set[1] then
				label:SetTextColor(color_bright_white)
				
				button.Paint = function(self, w, h) 
					if button:IsHovered() or avatar:IsHovered() then surf_SetDrawColor(color_nazi_select)
					else surf_SetDrawColor(color_nazi) end
					
					surf_DrawRect(0, 0, w, h)
				end
			else
				label:SetTextColor(color_nazi)
				
				button.Paint = function(self, w, h) 
					if button:IsHovered() or avatar:IsHovered() then surf_SetDrawColor(color_bright_white_select)
					else surf_SetDrawColor(color_bright_white) end
					
					surf_DrawRect(0, 0, w, h)
				end
			end
		end
		
		frame:MakePopup()
	end)
	
	concommand.Add("nz_record_tracker_congrats", function()
		--allows the client to praise themself
		congratulate()
	end, _, false, "Gives you the confetti and celebration sounds. Client side only.")
	
	hook.Add("FinishChat", "nz_record_tracker_chat_finish", function()
		--
		if chat_button then chat_button:Remove() end
	end)
	
	hook.Add("StartChat", "nz_record_tracker_chat_start", function()
		chat_button = vgui.Create("DButton")
		local chat_w, chat_h = chat.GetChatBoxSize()
		local chat_x, chat_y = chat.GetChatBoxPos()
		
		chat_button:SetPos(chat_x, chat_y + chat_h + 5)
		chat_button:SetText("Record Tracker Glory Board")
		chat_button:SetTextColor(color_bright_white)
		chat_button:SetSize(chat_w, chat_h * 0.1)
		
		chat_button.Paint = function(self, w, h) 
			if chat_button:IsHovered() then surf_SetDrawColor(color_nazi_select)
			else surf_SetDrawColor(color_nazi) end
			
			surf_DrawRect(0, 0, w, h)
		end
		
		--hehehehehe cheeeese
		chat_button.DoClick = function() RunConsoleCommand("nz_record_tracker_gui") end
	end)
end

game.AddParticles("particles/explosion_copy.pcf")
PrecacheParticleSystem("bday_confetti")
