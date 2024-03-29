local global_data = {}
local index_data = {}
local map_data = {}

--[[

[nZombies Wave Record Tracker] lua/autorun/nz_record_tracker.lua:70: attempt to concatenate a nil value
1. update_data - lua/autorun/nz_record_tracker.lua:70
 2. v - lua/autorun/nz_record_tracker.lua:110
  3. Call - lua/includes/modules/hook.lua:84
   4. Prepare - addons/nzombies-master-workshop/gamemodes/nzombies/gamemode/round/sv_round.lua:49
    5. unknown - addons/nzombies-master-workshop/gamemodes/nzombies/gamemode/round/sv_round.lua:16
]]

if SERVER then
	AddCSLuaFile()
	CreateConVar("nz_rectracker_kill_threshold", "100", {FCVAR_ARCHIVE, FCVAR_NEVER_AS_STRING}, "The amount of kills that must be passed for a player to be recorded if they leave before the record is made.", 0, 2147483647)
	file.CreateDir("nz_records/meta")
	resource.AddWorkshop("1930243232")
	util.AddNetworkString("record_tracker_congrats")
	util.AddNetworkString("record_tracker_gui")
	util.AddNetworkString("record_tracker_gui_map")
	
	local current_map = game.GetMap()
	local dictionaries = file.Find("nz_record_tracker_lang/*", "LUA", "nameasc")
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
	local pretty_print = false
	
	for _, dictionary in pairs(dictionaries) do AddCSLuaFile("nz_record_tracker_lang/" .. dictionary) end
	
	if global_read then global_wave = tonumber(global_read)
	else global_wave = 0 end
	
	if map_read then map_data = util.JSONToTable(map_read)
	else
		map_data.contributors = {}
		map_data.wave = 0
	end
	
	local function congratulate_players()
		--tells the client side what message to give and to praise them
		net.Start("record_tracker_congrats")
		net.WriteBool(global_record_beaten)
		
		--if they didn't beat the global record, tell them what it is
		if not global_record_beaten then net.WriteUInt(global_wave, 32) end
		
		net.Broadcast()
	end
	
	local function update_access_index(round)
		--updates the map index
		--the map index keeps track of the record for each map, this is used for the gui
		index_data.maps[current_map] = math.floor(round or 0)
		
		file.Write(index_path, util.TableToJSON(index_data, pretty_print))
	end
	
	local function update_data(round, path)
		--save the record
		local data = {}
		data.contributors = table.Copy(player_tracker)
		data.wave = math.floor(round)
		
		update_access_index(round)
		
		--we use their steam id 64 so we can load their avatars for the gui
		--we also concatenate S to their IDs to make sure they are kept as strings when we decode the JSON
		--should probably be /async/!
		--I added the invalid steam id and Invalid name as single player doesn't like SteamID64
		for _, ply in pairs(player.GetHumans()) do data.contributors["S" .. (ply and ply:SteamID64() or "invalid")] = {
			["kills"] = math.floor(ply:GetTotalKills()),
			["name"] = ply and ply:Nick() or "Invalid"}
		end
		
		file.Write(path, util.TableToJSON(data, pretty_print))
		
		return data
	end
	
	local function update_global(round)
		--saves the highest round reached to a single file
		--we could probably store this in the index to reduce the file count
		file.Write(global_path, tostring(round))
	end
	
	if index_read then
		index_data = util.JSONToTable(index_read)
		
		if not index_data.maps[current_map] then update_access_index() end
	else
		index_data.maps = {}
		
		update_access_index()
	end
	
	concommand.Add("nz_rectracker_gui", function(ply)
		--send the record data
		net.Start("record_tracker_gui")
		net.WriteTable(index_data)
		net.Send(ply)
	end, nil, "Opens the gloryboard for the highest waves beaten.")
	
	cvars.AddChangeCallback("nz_rectracker_kill_threshold", function(name, old_value, new_value)
		--we don't want to read the convar every time a player disconnects, so we will just store the value
		kill_threshold = tonumber(new_value) or 100
	end)
	
	hook.Add("OnRoundCreative", "prog_bar_onroundend_hook", function() player_tracker = {} end)
	hook.Add("OnRoundEnd", "prog_bar_onroundend_hook", function() player_tracker = {} end)
	hook.Add("OnRoundPreparation", "nz_record_tracker_prep_hook", function(round)
		--check if they are making records
		if round > global_wave then
			map_data = update_data(round, map_path)
			
			update_global(round)
			
			if not global_record_beaten then
				map_record_beaten = true
				global_record_beaten = true
				
				congratulate_players()
			end
		elseif round > map_data.wave then
			map_data = update_data(round, map_path)
			
			if not map_record_beaten then
				map_record_beaten = true
				
				congratulate_players()
			end
		end
	end)
	hook.Add("PlayerDisconnected", "nz_record_tracker_disc_hook", function(ply)
		--keep track of players who contributed but left before the record was made
		--they will only be recorded if they had passed the kill_threshold
		local kills = ply:GetTotalKills()
		
		if kills and kills > kill_threshold then player_tracker["S" .. ply:SteamID64()] = {["kills"] = ply:GetTotalKills(), ["name"] = ply:Nick(), ["wave"] = nzRound.Number} end
	end)
	
	net.Receive("record_tracker_gui_map", function(len, ply)
		--recieved when a person selects a map to see the record
		local check_map_name = net.ReadString()
		local check_map_path = "nz_records/" .. check_map_name .. ".json"
		local check_map_read = file.Read(check_map_path, "DATA")
		
		if check_map_read then
			local decoded = util.JSONToTable(check_map_read)
			local filtered_data = table.Copy(decoded)
			filtered_data.contributors = {}
			
			--should probably be /async/!
			for k, v in pairs(decoded.contributors) do
				filtered_data.contributors[string.sub(k, 2)] = v
			end
			
			net.Start("record_tracker_gui_map")
			net.WriteTable(filtered_data)
			net.Send(ply)
		else print("[nZombies Record Tracker] CRITICAL ERROR! Could not read '" .. check_map_path .. "'. Request was sent from \"" .. ply:Nick() .. "\" [" .. ply:SteamID() .. "]\nThis is likely caused by a person trying to view a map's record when one has not yet been made.") end
	end)
elseif CLIENT then
	local function activate_sound()
		--play the celebration sound
		surface.PlaySound("nz_record_tracker/woot_" .. math.random(1, 19) .. ".wav")
	end
	
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
	
	--ghetto language control
	local current_language = string.lower(GetConVar("cl_language"):GetString())
	local language_text = {}
	local language_text_dict = include("nz_record_tracker_lang/_dictionary.lua")
	
	if language_text_dict[current_language] then language_text = include(language_text_dict[current_language])
	else language_text = include(language_text_dict["english"]) end
	
	--local functions
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
	
	local function get_lang_text(key, ...)
		--gets a predefined phrase in the languages scripts and does formatting with varargs
		if ... then return string.format(language_text[key], ...)
		else return language_text[key] or ((key or "INVALID-KEY") .. ":" .. (current_language or "INVALID-LANG")) end
	end
	
	--post function setup
	calc_vars()
	
	--net
	net.Receive("record_tracker_congrats", function()
		--when a record is beat, check if it was map or global then congratulate accordingly
		local global_record_beaten = net.ReadBool()
		
		if global_record_beaten then chat.AddText(Color(127, 127, 255), get_lang_text("CONGRATS_GLOBAL"))
		else chat.AddText(Color(127, 255, 127), get_lang_text("CONGRATS_MAP", net.ReadUInt(32))) end
		
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
		frame_chooser:SetTitle(get_lang_text("GUI_TITLE"))
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
			button:SetText(get_lang_text("GUI_ENTRY", set[1], set[2]))
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
		frame:SetTitle(get_lang_text("GUI_TITLE_MAP", chosen_map))
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
			
			--{id64, name, kills, wave}
			avatar:SetSteamID(set[1], 64)
			avatar:SetPos(5, 5)
			avatar:SetSize(avatar_size, avatar_size)
			
			label = vgui.Create("DLabel", button)
			label:SetContentAlignment(4)
			label:SetPos(button_h, 0)
			label:SetSize(button_w - button_h, button_h)
			label:SetText(set[4] and get_lang_text("GUI_ENTRY_MAP_LEFT", set[2], set[4], set[3]) or get_lang_text("GUI_ENTRY_MAP", set[2], set[3]))
			
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
	
	--concommands
	concommand.Add("nz_record_tracker_congrats", function()
		--allows the client to praise themself
		congratulate()
	end, _, false, get_lang_text("CONGRATS_COMMAND"))
	
	--hooks
	hook.Add("OnScreenSizeChanged", "prog_bar_screen_res_changed_hook", calc_vars)
	
	--list
	list.Set("DesktopWindows", "CryRecordTracker", {
		title		= "Record Tracker",
		icon		= "icon64/nz_cry_record_tracker.png",
		width		= 0,
		height		= 0,
		onewindow	= false,
		init		= function(icon, window)
			print(window)
			
			window:Remove()
			
			RunConsoleCommand("nz_rectracker_gui")
		end
	})
end

game.AddParticles("particles/explosion_copy.pcf")
PrecacheParticleSystem("bday_confetti")