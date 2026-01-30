local zoneDat = require('zonedat');
local imgui = require('imgui');

local isOpen = { false };
local trackSelection = -1;
local zoneSelection = -1;
local sortedTrack = T{};
local sortedZone = T{};
local gui = {};
local identifierOptions = T { 'Index (Decimal)', 'Index (Hex)', 'Id (Decimal)', 'Id (Hex)' };

local function sortPredicate(a,b)
    if (a.Name ~= b.Name) then
        return a.Name < b.Name;
    else
        return a.Id < b.Id;
    end
end
local function RebuildTracking();
    sortedTrack = T{};
    for _,entry in pairs(gZoneList) do
        if gSettings.Monitored[entry.Id] ~= nil then
            sortedTrack:append(entry);
        end
    end
    table.sort(sortedTrack, sortPredicate);
end

local function ColorSelector(container, key)
    --Credit: Atom0s for color flip function from equipmon
    local function cflip(c)
        local r, b = c[3], c[1];
        c[1] = r;
        c[3] = b;
        return c;
    end
    local colors = cflip({ imgui.ColorConvertU32ToFloat4(container[key]) });
    if (imgui.ColorEdit4('Color', colors)) then
        colors = cflip(colors);
        container[key] = imgui.ColorConvertFloat4ToU32(colors);
        gUpdate = true;
        gUpdateTimer = os.clock() + 5;
    end
end

function gui:SetZone(zone, subZone)
    gZoneList = zoneDat:Load(zone, subZone);
    sortedZone = T{};
    for id,mob in pairs(gZoneList) do
        sortedZone:append(mob);
    end
    table.sort(sortedZone, sortPredicate);
    trackSelection = -1;
    zoneSelection = -1;
    RebuildTracking();
end

function gui:Show()
    isOpen[1] = true;
end

function gui:Tick()
    if isOpen[1] == false then
        return;
    end

    if (imgui.Begin('ScentHound##Scenthound_MainWindow', isOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
        if imgui.BeginTabBar('##ScentHoundTabBar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            if imgui.BeginTabItem('Active Tracking') then
                if imgui.BeginChild('TrackList', { 360, 340 }, ImGuiChildFlags_Borders) then
                    for index,entry in ipairs(sortedTrack) do
                        if imgui.Selectable(entry:ToString(), index == trackSelection) then
                            trackSelection = index;
                        end
                    end
                    imgui.EndChild();
                end

                if trackSelection ~= -1 then
                    local entry = sortedTrack[trackSelection];
                    imgui.BeginGroup();
                    if imgui.Checkbox('Alarm##ScentHoundAlarmButton', { entry.Alarm }) then
                        entry.Alarm = not entry.Alarm;
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                    imgui.ShowHelp('Play an audible alarm when the monster pops.');
                    if imgui.Checkbox('Draw##ScentHoundDrawButton', { entry.Draw }) then
                        entry.Draw = not entry.Draw;
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                    imgui.ShowHelp('Draw an arc to the monster when the monster is alive.');
                    imgui.EndGroup();
                    imgui.SameLine();
                    imgui.BeginGroup();
                    if imgui.Checkbox('Widescan On Pop##ScentHoundWidescanButton', { entry.Widescan }) then
                        entry.Widescan = not entry.Widescan;
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                    imgui.ShowHelp('Immediately track monster on widescan when it pops.');
                    if imgui.Button('Single Widescan') then
                        local cmd = string.format('/watchdog track %u', bit.band(entry.Id, 0x7FF));
                        AshitaCore:GetChatManager():QueueCommand(-1, cmd);
                    end
                    imgui.ShowHelp('Attempt to track the monster or NPC on widescan.');
                    imgui.EndGroup();
                    if gSettings.AllowPacketSearch == true then
                        imgui.SameLine();
                        imgui.BeginGroup();
                        local isTracked = gPacketList[entry] ~= nil;
                        if imgui.Checkbox('Repeat Packet##ScentHoundPacketsButton', { isTracked }) then
                            if isTracked then
                                gPacketList[entry] = nil;
                            else
                                gPacketList[entry] = 0;
                            end
                        end
                        imgui.ShowHelp('Send periodic 0x16 packets to force server to update monster.');
                        if imgui.Button('Single Packet') then
                            local packet = struct.pack('LL', 0, bit.band(entry.Id, 0x7FF));
                            AshitaCore:GetPacketManager():AddOutgoingPacket(0x16, packet:totable());
                            print(chat.header('ScentHound') .. chat.message(string.format('Sent update request packet for %s.', entry:ToString())));
                        end
                        imgui.ShowHelp('Send one 0x16 packet to force server to update monster.');
                        imgui.EndGroup();
                    end
                    if entry.Draw then
                        ColorSelector(entry, 'Color');
                    end
                    if imgui.Button('Remove##ScentHoundRemoveButton') then
                        gPacketList[entry] = nil;
                        gSettings.Monitored[entry.Id] = nil;
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                        RebuildTracking();
                        trackSelection = -1;
                    end
                    imgui.ShowHelp('Remove monster from tracking.');
                end
                imgui.EndTabItem();
            end

            if imgui.BeginTabItem('Zone List') then
                if imgui.BeginChild('ZoneList', { 360, 340 }, ImGuiChildFlags_Borders) then
                    for index,entry in ipairs(sortedZone) do
                        if imgui.Selectable(entry:ToString(), index == zoneSelection) then
                            zoneSelection = index;
                        end
                        if (imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(0)) then
                            if gSettings.Monitored[entry.Id] ~= entry then
                                gSettings.Monitored[entry.Id] = entry;
                                gUpdate = true;
                                gUpdateTimer = os.clock() + 5;
                                print(chat.header('ScentHound') .. chat.message(string.format('%s added to tracking.', entry:ToString())));
                                RebuildTracking();
                            else
                                print(chat.header('ScentHound') .. chat.error(string.format('%s is already being tracked.', entry:ToString())));
                            end
                        end
                    end
                    imgui.EndChild();
                end
                    
                if zoneSelection ~= -1 then
                    local entry = sortedZone[zoneSelection];
                    local buffer = { entry.Alias };
                    imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Alias');
                    if imgui.InputText(string.format('##ScentHoundAlias', entry.Id), buffer, 256) then
                        entry.Alias = buffer[1];
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                    if imgui.Button('Track') then
                        if gSettings.Monitored[entry.Id] ~= entry then
                            gSettings.Monitored[entry.Id] = entry;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                            print(chat.header('ScentHound') .. chat.message(string.format('%s added to tracking.', entry:ToString())));
                            RebuildTracking();
                        else
                            print(chat.header('ScentHound') .. chat.error(string.format('%s is already being tracked.', entry:ToString())));
                        end
                    end
                end
                imgui.EndTabItem();
            end
            
            if imgui.BeginTabItem('Misc.') then
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Identifier Type');
                if imgui.BeginCombo('##ScentHoundIdType', gSettings.IdentifierType, ImGuiComboFlags_None) then
                    local current = gSettings.IdentifierType;
                    for _,entry in ipairs(identifierOptions) do
                        if imgui.Selectable(entry, entry == current) then
                            gSettings.IdentifierType = entry;
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                    end
                end
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Alarm File');
                local buffer = { gSettings.Sound };                
                if imgui.InputText('##ScentHoundAlarmFile', buffer, 256) then
                    if buffer[1] ~= gSettings.Sound then
                        gSettings.Sound = buffer[1];
                        gUpdate = true;
                        gUpdateTimer = os.clock() + 5;
                    end
                end
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Default Color');
                ColorSelector(gSettings, 'DefaultColor');
                imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Packet Search [DANGEROUS]');
                if imgui.Checkbox('Enabled', { gSettings.AllowPacketSearch }) then
                    gSettings.AllowPacketSearch = not gSettings.AllowPacketSearch;
                    if not gSettings.AllowPacketSearch then
                        gPacketList = {};
                    end
                    --No delay on disabling this saving to disc..
                    settings.save();
                    gUpdate = false;
                end
                imgui.ShowHelp('Allow 0x16 packet searching. This is easily detectable by server and risks a ban if SE becomes more concerned about it.');
                if gSettings.AllowPacketSearch then
                    imgui.TextColored({ 1.0, 0.75, 0.55, 1.0 }, 'Packet Frequency (Seconds)');
                    local frequency = { gSettings.PacketSearchDelay };
                    if (imgui.SliderFloat('##PacketSearchFrequency', frequency, 0.4, 300, '%.2f', ImGuiSliderFlags_AlwaysClamp)) then
                        if (frequency[1] ~= gSettings.PacketSearchDelay) then
                            gSettings.PacketSearchDelay = math.min(math.max(0.4, frequency[1]), 300);
                            gUpdate = true;
                            gUpdateTimer = os.clock() + 5;
                        end
                    end
                    imgui.ShowHelp('Set delay between 0x16 packets. With multiple targets being tracked, they will rotate.');
                end
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();
end

return gui;