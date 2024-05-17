--[[
* track cooldowns for gathering beastman/kindred seals
--]]

addon.name      = 'sealclub';
addon.author    = 'samsonffxi';
addon.version   = '1.0.0';
addon.desc      = 'Seal farming.';
addon.link      = 'https://github.com/';
addon.commands  = {'/sealclub'};

require('common');
local chat      = require('chat');
local d3d       = require('d3d8');
local ffi       = require('ffi');
local fonts     = require('fonts');
local imgui     = require('imgui');
local prims     = require('primitives');
local scaling   = require('scaling');
local settings  = require('settings');

local C = ffi.C;
local d3d8dev = d3d.get_device();

-- Default Settings
local default_settings = T{
    visible = T{ true, },
    opacity = T{ 1.0, },
    padding = T{ 1.0, },
    scale = T{ 1.0, },
    font_scale = T{ 1.0 },
    x = T{ 100, },
    y = T{ 100, },

	seal_timer_ready_color = {0.0, 1.0, 0.0, 1.0}, --green
	seal_timer_warn_color = {1.0, 0.0, 0.0, 1.0}, --red
	bseal_cooldown = 300,
    kseal_cooldown = 900,
};

-- Variables
local sealclub = T{
    settings = settings.load(default_settings),

    -- screen movement variables..
    move = T{
        dragging = false,
        drag_x = 0,
        drag_y = 0,
        shift_down = false,
    },

    -- Editor variables..
    editor = T{
        is_open = T{ false, },
    },

    sealclub_start = ashita.time.clock()['ms'],

	last_bseal = 0,
	last_kseal = 0,

	bseal_timer = 0,
	kseal_timer = 0,

	bseal_count = 0,
	kseal_count = 0,
    seals_clubbed = 0,

    myname = '',
};

--[[
* Renders the SealClubbing settings editor.
--]]
local function render_editor()
    if (not sealclub.editor.is_open[1]) then
        return;
    end

    imgui.SetNextWindowSize({ 580, 600, });
    imgui.SetNextWindowSizeConstraints({ 560, 600, }, { FLT_MAX, FLT_MAX, });
    if (imgui.Begin('SealClub##Config', sealclub.editor.is_open)) then

        -- imgui.SameLine();
        if (imgui.Button('Save Settings')) then
            settings.save();
            print(chat.header(addon.name):append(chat.message('Settings saved.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reload Settings')) then
            settings.reload();
            print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        end
        imgui.SameLine();
        if (imgui.Button('Reset Settings')) then
            settings.reset();
            print(chat.header(addon.name):append(chat.message('Settings reset to defaults.')));
        end
    end
    render_general_config(settings);
    imgui.End();
end

function render_general_config(settings)
    imgui.Text('General Settings');
    imgui.BeginChild('settings_general', { 0, 200, }, true);
        imgui.ShowHelp('Toggles if SealClub is visible or not.');
        imgui.SliderFloat('Opacity', sealclub.settings.opacity, 0.125, 1.0, '%.3f');
        imgui.ShowHelp('The opacity of the SealClub window.');
        imgui.SliderFloat('Font Scale', sealclub.settings.font_scale, 0.1, 2.0, '%.3f');
        imgui.ShowHelp('The scaling of the font size.');

        local pos = { sealclub.settings.x[1], sealclub.settings.y[1] };
        if (imgui.InputInt2('Position', pos)) then
            sealclub.settings.x[1] = pos[1];
            sealclub.settings.y[1] = pos[2];
        end
        imgui.ShowHelp('The position of SealClub on screen.');

    imgui.EndChild();
end

function split(inputstr, sep)
    if sep == nil then
        sep = '%s';
    end
    local t = {};
    for str in string.gmatch(inputstr, '([^'..sep..']+)') do
        table.insert(t, str);
    end
    return t;
end

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
function format_int(number)
    if (string.len(number) < 4) then
        return number
    end
    if (number ~= nil and number ~= '' and type(number) == 'number') then
        local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)');

        -- we sometimes get a nil int from the above tostring, just return number in those cases
        if (int == nil) then
            return number
        end

        -- reverse the int-string and append a comma to all blocks of 3 digits
        int = int:reverse():gsub("(%d%d%d)", "%1,");
  
        -- reverse the int-string back remove an optional comma and put the 
        -- optional minus and fractional part back
        return minus .. int:reverse():gsub("^,", "") .. fraction;
    else
        return 'NaN';
    end
end

function clear_rewards()
    sealclub.last_kseal = ashita.time.clock()['ms'];
    sealclub.last_bseal = ashita.time.clock()['ms'];
    sealclub.settings.first_attempt = 0;
    sealclub.settings.rewards = { };
    sealclub.settings.item_count = 0;
	sealclub.settings.bucket_count = 0;
end

----------------------------------------------------------------------------------------------------
-- Helper functions borrowed from luashitacast
----------------------------------------------------------------------------------------------------
function GetTimestamp()
    local pVanaTime = ashita.memory.find('FFXiMain.dll', 0, 'B0015EC390518B4C24088D4424005068', 0, 0);
    local pointer = ashita.memory.read_uint32(pVanaTime + 0x34);
    local rawTime = ashita.memory.read_uint32(pointer + 0x0C) + 92514960;
    local timestamp = {};
    timestamp.day = math.floor(rawTime / 3456);
    timestamp.hour = math.floor(rawTime / 144) % 24;
    timestamp.minute = math.floor((rawTime % 144) / 2.4);
    return timestamp;
end

--[[
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        sealclub.settings = s;
    end

    -- Save the current settings..
    settings.save();
end);

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
	sealclub.myname = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    -- Save the current settings..
    settings.save();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/sealclub')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /sealclub - Toggles the sealclub editor.
    -- Handle: /sealclub edit - Toggles the sealclub editor.
    if (#args == 1 or (#args >= 2 and args[2]:any('edit'))) then
        sealclub.editor.is_open[1] = not sealclub.editor.is_open[1];
        return;
    end

    -- Handle: /sealclub save - Saves the current settings.
    if (#args >= 2 and args[2]:any('save')) then
        settings.save();
        print(chat.header(addon.name):append(chat.message('Settings saved.')));
        return;
    end

    -- Handle: /sealclub reload - Reloads the current settings from disk.
    if (#args >= 2 and args[2]:any('reload')) then
        settings.reload();
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')));
        return;
    end

    -- Handle: /sealclub show - Shows the sealclub object.
    if (#args >= 2 and args[2]:any('show')) then
		-- reset last dig on show command to reset timeout counter
		sealclub.settings.visible[1] = true;
        return;
    end

    -- Handle: /sealclub hide - Hides the sealclub object.
    if (#args >= 2 and args[2]:any('hide')) then
		sealclub.settings.visible[1] = false;
        return;
    end
	
end);

--[[
* event: packet_in
* desc : Event called when the addon is processing incoming packets.
--]]
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- reset zone fatigue notification on zone
	if( e.id == 0x00B ) then 
        sealclub.last_kseal = 0;
        sealclub.last_bseal = 0;
    end
end);

----------------------------------------------------------------------------------------------------
-- watch for seal drops
----------------------------------------------------------------------------------------------------
ashita.events.register('text_in', 'text_in_cb', function (e)
    local message = e.message;
    message = string.lower(message);
    message = string.strip_colors(message);

    local kseal = string.match(message, string.lower(sealclub.myname) .. " obtains a kindred's seal.");
    local bseal = string.match(message, string.lower(sealclub.myname) .. " obtains a beastmen's seal.");
    local kills = string.match(message, string.lower(sealclub.myname) .. " defeats the .");
	
	-- Update last seal timestamp when obtained
	if (kseal) then
        sealclub.kseal_count = sealclub.kseal_count + 1;
        sealclub.last_kseal = ashita.time.clock()['ms'];
	end
	if (bseal) then
        sealclub.bseal_count = sealclub.bseal_count + 1;
        sealclub.last_bseal = ashita.time.clock()['ms'];
	end
    if (kills) then
        sealclub.seals_clubbed = sealclub.seals_clubbed + 1;
    end
end);

--[[
* event: d3d_beginscene
* desc : Event called when the Direct3D device is beginning a scene.
--]]
ashita.events.register('d3d_beginscene', 'beginscene_cb', function (isRenderingBackBuffer)
end);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    -- local last_attempt_secs = (ashita.time.clock()['ms'] - sealclub.last_attempt) / 1000.0;
    render_editor();

    -- Hide the sealclub object if not visible..
    if (not sealclub.settings.visible[1]) then
        return;
    end

    -- Hide the sealclub object if Ashita is currently hiding font objects..
    if (not AshitaCore:GetFontManager():GetVisible()) then
        return;
    end

    imgui.SetNextWindowBgAlpha(sealclub.settings.opacity[1]);
    imgui.SetNextWindowSize({ -1, -1, }, ImGuiCond_Always);
    if (imgui.Begin('SealClub##Display', sealclub.settings.visible[1], bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav))) then
		local elapsed_time = ashita.time.clock()['s'] - math.floor(sealclub.sealclub_start / 1000.0);
		local bseal_diff = ashita.time.clock()['s'] - math.floor(sealclub.last_bseal / 1000.0);
		local kseal_diff = ashita.time.clock()['s'] - math.floor(sealclub.last_kseal / 1000.0);
		if (bseal_diff < sealclub.settings.bseal_cooldown) then
			sealclub.bseal_timer = sealclub.settings.bseal_cooldown - bseal_diff;
        elseif (bseal_diff >= sealclub.settings.bseal_cooldown) then
            sealclub.bseal_timer = 0;
		end
		if (kseal_diff < sealclub.settings.kseal_cooldown) then
			sealclub.kseal_timer = sealclub.settings.kseal_cooldown - kseal_diff;
        elseif (kseal_diff >= sealclub.settings.kseal_cooldown) then
            sealclub.kseal_timer = 0;
		end
		
		local btimer_display = sealclub.bseal_timer;
		if (btimer_display <= 0) then
			btimer_display = "Beastman Seal Ready"
		end
		local ktimer_display = sealclub.kseal_timer;
		if (ktimer_display <= 0) then
			ktimer_display = "Kindred Seal Ready"
		end

		imgui.SetWindowFontScale(sealclub.settings.font_scale[1] + 0.1);
		imgui.Text('    %%%  Seal Clubbing  %%%');
		imgui.SetWindowFontScale(sealclub.settings.font_scale[1]);
		imgui.Separator();
		
		imgui.Text('BSeal Timer: ');
		imgui.SameLine();
		if (btimer_display == 'Beastman Seal Ready') then
			imgui.TextColored(sealclub.settings.seal_timer_ready_color, tostring(btimer_display));
		else
			imgui.Text(tostring(btimer_display));
		end
        imgui.Text('Beastman Seal Count: ');
        imgui.SameLine();
		imgui.Text(tostring(sealclub.bseal_count));
		imgui.Separator();

		imgui.Text('KSeal Timer: ');
		imgui.SameLine();
		if (ktimer_display == 'Kindred Seal Ready') then
			imgui.TextColored(sealclub.settings.seal_timer_ready_color, tostring(ktimer_display));
		else
			imgui.Text(tostring(ktimer_display));
		end
        imgui.Text('Kindred Seal Count: ');
        imgui.SameLine();
		imgui.Text(tostring(sealclub.kseal_count));
		imgui.Separator();
		
        imgui.Text('Total Time: ');
        imgui.SameLine();
        imgui.Text(tostring(string.format('%.2f', (elapsed_time / 60)) .. ' minutes'));
        imgui.Text('Seals Clubbed: ');
        imgui.SameLine();
        imgui.Text(tostring(format_int(sealclub.seals_clubbed)) .. ' baby seals (x.x)');
    end
    imgui.End();

end);

--[[
* event: key
* desc : Event called when the addon is processing keyboard input. (WNDPROC)
--]]
ashita.events.register('key', 'key_callback', function (e)
    -- Key: VK_SHIFT
    if (e.wparam == 0x10) then
        sealclub.move.shift_down = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10));
        return;
    end
end);

--[[
* event: mouse
* desc : Event called when the addon is processing mouse input. (WNDPROC)
--]]
ashita.events.register('mouse', 'mouse_cb', function (e)
    -- Tests if the given coords are within the equipmon area.
    local function hit_test(x, y)
        local e_x = sealclub.settings.x[1];
        local e_y = sealclub.settings.y[1];
        local e_w = ((32 * sealclub.settings.scale[1]) * 4) + sealclub.settings.padding[1] * 3;
        local e_h = ((32 * sealclub.settings.scale[1]) * 4) + sealclub.settings.padding[1] * 3;

        return ((e_x <= x) and (e_x + e_w) >= x) and ((e_y <= y) and (e_y + e_h) >= y);
    end

    -- Returns if the equipmon object is being dragged.
    local function is_dragging() return sealclub.move.dragging; end

    -- Handle the various mouse messages..
    switch(e.message, {
        -- Event: Mouse Move
        [512] = (function ()
            sealclub.settings.x[1] = e.x - sealclub.move.drag_x;
            sealclub.settings.y[1] = e.y - sealclub.move.drag_y;

            e.blocked = true;
        end):cond(is_dragging),

        -- Event: Mouse Left Button Down
        [513] = (function ()
            if (sealclub.move.shift_down) then
                sealclub.move.dragging = true;
                sealclub.move.drag_x = e.x - sealclub.settings.x[1];
                sealclub.move.drag_y = e.y - sealclub.settings.y[1];

                e.blocked = true;
            end
        end):cond(hit_test:bindn(e.x, e.y)),

        -- Event: Mouse Left Button Up
        [514] = (function ()
            if (sealclub.move.dragging) then
                sealclub.move.dragging = false;

                e.blocked = true;
            end
        end):cond(is_dragging),

        -- Event: Mouse Wheel Scroll
        [522] = (function ()
            if (e.delta < 0) then
                sealclub.settings.opacity[1] = sealclub.settings.opacity[1] - 0.125;
            else
                sealclub.settings.opacity[1] = sealclub.settings.opacity[1] + 0.125;
            end
            sealclub.settings.opacity[1] = sealclub.settings.opacity[1]:clamp(0.125, 1);

            e.blocked = true;
        end):cond(hit_test:bindn(e.x, e.y)),
    });
end);