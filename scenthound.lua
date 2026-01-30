addon.name      = 'ScentHound';
addon.author    = 'Thorny';
addon.version   = '1.06';
addon.desc      = 'Tracks monster and NPC spawns and provides alerts/onscreen indications.';
addon.link      = 'https://ashitaxi.com/';

require('common');
chat = require('chat');
settings = require('settings');
local gui = require('gui');
local indicator = require('indicator');
local tracker = require('tracker');

local defaultSettings = T{
    AllowPacketSearch = false,
    DefaultColor = 0xFF00FF80,
    IdentifierType = 'Index (Hex)',
    Monitored = T{},
    PacketSearchDelay = 1.5,
    Sound = 'Alert.wav',
};
gSettings = settings.load(defaultSettings);
gPacketList = {};
gZoneList = {};
gUpdate = false;
gUpdateTimer = 0;
gLocationCache = {};

local function TrySaveSettings(force)    
    if (gUpdate) and ((force) or (os.clock() > gUpdateTimer)) then
        settings.save();
        gUpdate = false;
    end
end

settings.register('settings', 'settings_update', function(newSettings)
    gSettings = newSettings;
end);

ashita.events.register('load', 'load_cb', function ()
    local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    if playerIndex ~= 0 then
        --Initialize zone/subzone. Credit to atom0s for locating signature and offsets.
        local zonePointer = ashita.memory.find('FFXiMain.dll', 0, '8B0D????????8B44240425FFFF00003B', 0x02, 0x00);
        local pointer = ashita.memory.read_uint32(zonePointer);
        if (pointer ~= 0) then
            pointer = ashita.memory.read_uint32(pointer + 0x04);
            if (pointer ~= 0) then
                gui:SetZone(ashita.memory.read_uint32(pointer + 0x3C2E0), ashita.memory.read_uint16(pointer + 0x3C2EA));
            end
        end
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    TrySaveSettings(true);
end);

ashita.events.register('command', 'scenthound_command_cb', function (e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    args[1] = string.lower(args[1]);
    if (args[1] == '/scenthound') or (args[1] == '/sc') then
        gui:Show();
        e.blocked = true;
        return;
    end
end);

ashita.events.register('d3d_present', 'scenthound_handlerender', function ()
    gui:Tick();
    indicator:Tick();
    TrySaveSettings();
end);

ashita.events.register('packet_in', 'scenthound_handleincomingpacket', function (e)
    if (e.id == 0x00A) then
        gPacketList = {};
        gLocationCache = {};
        TrySaveSettings(true);
        local zone = struct.unpack('H', e.data, 0x30 + 1);;
        local subZone = struct.unpack('H', e.data, 0x9E + 1);
        gui:SetZone(zone, subZone);
        tracker:HandleZone();
    end

    if (e.id == 0x00E) then
        --Update location cache if position is provided..
        if bit.band(struct.unpack('B', e.data, 0x0A + 1), 0x01) == 0x01 then
            local index = struct.unpack('H', e.data, 0x08 + 1);
            gLocationCache[index] = {
                X = struct.unpack('f', e.data, 0x0C+1),
                Y = struct.unpack('f', e.data, 0x14+1),
                Z = struct.unpack('f', e.data, 0x10+1)
            };
        end
        
        tracker:HandleEntityUpdate(e);
    end

    if (e.id == 0xF5) then
        local index = struct.unpack('H', e.data, 0x12+1);
        gLocationCache[index] = {
            X = struct.unpack('f', e.data, 0x04+1),
            Y = struct.unpack('f', e.data, 0x0C+1),
            Z = struct.unpack('f', e.data, 0x08+1)
        };
    end
end);