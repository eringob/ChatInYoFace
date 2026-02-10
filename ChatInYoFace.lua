local ADDON_NAME = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local SOUND_NONE = "__NONE__"
local debugUntil = 0

local DEFAULTS = {
    anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    locked = true,
    font = "Fonts\\FRIZQT__.TTF",
    size = 18,
    outline = "THICKOUTLINE",
    lines = 6,
    time = 6,
    spacing = 2,
    hideChatFrame = false,
    channels = {
        CHAT_MSG_SAY = true,
        CHAT_MSG_YELL = true,
        CHAT_MSG_WHISPER = true,
        CHAT_MSG_WHISPER_INFORM = true,
        CHAT_MSG_PARTY = true,
        CHAT_MSG_PARTY_LEADER = true,
        CHAT_MSG_RAID = true,
        CHAT_MSG_RAID_LEADER = true,
        CHAT_MSG_RAID_WARNING = true,
        CHAT_MSG_LOOT = true,
        CHAT_MSG_SYSTEM = true,
        CHAT_MSG_GUILD = true,
        CHAT_MSG_OFFICER = true,
        CHAT_MSG_CHANNEL = true,
        CHAT_MSG_COMMUNITIES_CHANNEL = true,
        CHAT_MSG_INSTANCE_CHAT = true,
        CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    },
    channelSounds = {},
}

local DEFAULT_FONT_OPTIONS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local BASE_CHANNEL_LIST = {
    { key = "CHAT_MSG_SAY", label = "Say" },
    { key = "CHAT_MSG_YELL", label = "Yell" },
    { key = "CHAT_MSG_WHISPER", label = "Whisper" },
    { key = "CHAT_MSG_WHISPER_INFORM", label = "Whisper (Outgoing)" },
    { key = "CHAT_MSG_PARTY", label = "Party" },
    { key = "CHAT_MSG_PARTY_LEADER", label = "Party Leader" },
    { key = "CHAT_MSG_RAID", label = "Raid" },
    { key = "CHAT_MSG_RAID_LEADER", label = "Raid Leader" },
    { key = "CHAT_MSG_RAID_WARNING", label = "Raid Warning" },
    { key = "CHAT_MSG_LOOT", label = "Item Loot" },
    { key = "CHAT_MSG_SYSTEM", label = "System Messages" },
    { key = "CHAT_MSG_GUILD", label = "Guild" },
    { key = "CHAT_MSG_OFFICER", label = "Officer" },
    { key = "GUILD_MOTD", label = "GMotD" },
    { key = "CHAT_MSG_COMMUNITIES_CHANNEL", label = "Communities" },
    { key = "CHAT_MSG_INSTANCE_CHAT", label = "Instance" },
    { key = "CHAT_MSG_INSTANCE_CHAT_LEADER", label = "Instance Leader" },
}

local EXCLUDED_CHANNEL_LABELS = {
    ["guild - general"] = true,
    ["communities - general"] = true,
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function RegisterLocalFonts()
    if not LSM then
        return
    end

    local list = _G.ChatInYoFace_FontList
    if type(list) ~= "table" then
        return
    end

    for _, entry in ipairs(list) do
        if entry and entry.name and entry.file then
            LSM:Register("font", entry.name, entry.file)
        end
    end
end

local function BuildFontOptions()
    local options = {}
    local seen = {}

    for _, item in ipairs(DEFAULT_FONT_OPTIONS) do
        table.insert(options, { name = item.name, path = item.path })
        seen[item.path] = true
    end

    if LSM then
        local lsmFonts = LSM:List("font")
        table.sort(lsmFonts, function(a, b)
            return a:lower() < b:lower()
        end)

        for _, name in ipairs(lsmFonts) do
            local path = LSM:Fetch("font", name)
            if path and not seen[path] then
                table.insert(options, { name = name, path = path })
                seen[path] = true
            end
        end
    end

    return options
end

local function BuildSoundOptions()
    local options = { { name = "None", value = SOUND_NONE } }
    local seen = {}

    if LSM then
        local lsmSounds = LSM:List("sound")
        table.sort(lsmSounds, function(a, b)
            return a:lower() < b:lower()
        end)

        for _, name in ipairs(lsmSounds) do
            local path = LSM:Fetch("sound", name)
            if path and not seen[path] then
                table.insert(options, { name = name, value = path })
                seen[path] = true
            end
        end
    end

    return options
end

local function NormalizeChannelName(channelName)
    if channelName == nil then
        return channelName
    end

    if type(channelName) ~= "string" then
        channelName = tostring(channelName)
    end

    if channelName == "" then
        return channelName
    end

    local trimmed = channelName:match("^%s*(.-)%s*$")
    local clubId, streamId = trimmed:match("^Community:%s*(%d+)%s*:?(%d*)$")
    if clubId and C_Club then
        clubId = tonumber(clubId)
        if streamId and streamId ~= "" and C_Club.GetStreamInfo then
            local info = C_Club.GetStreamInfo(clubId, tonumber(streamId))
            if info and info.name and info.name ~= "" then
                return info.name
            end
        end

        if C_Club.GetClubInfo then
            local info = C_Club.GetClubInfo(clubId)
            if info and info.name and info.name ~= "" then
                return info.name
            end
        end
    end

    return trimmed
end

local function ResolveChatChannelName(channelNumber, channelName)
    local lookup = {}
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = NormalizeChannelName(list[i + 1])
        if name and name ~= "" then
            local lower = name:lower()
            lookup[lower] = name
            lookup[lower:gsub("%s+", "")] = name
        end
    end

    local name
    if channelNumber and type(channelNumber) == "number" and channelNumber > 0 and GetChannelName then
        local _, resolved = GetChannelName(channelNumber)
        name = resolved
    elseif channelNumber and type(channelNumber) == "string" and channelNumber ~= "" then
        name = channelNumber
    end

    if not name or name == "" then
        name = channelName
    end

    name = NormalizeChannelName(name)
    if not name or name == "" then
        return name
    end

    local inner = name:match("%((.-)%)")
    if inner and inner ~= "" then
        name = inner
    end

    local lower = name:lower()
    if lookup[lower] then
        return lookup[lower]
    end

    local compact = lower:gsub("%s+", "")
    if lookup[compact] then
        return lookup[compact]
    end

    local stripped = lower:gsub("^%s*%d+%s*%.%s*", "")
    if lookup[stripped] then
        return lookup[stripped]
    end

    local strippedCompact = stripped:gsub("%s+", "")
    if lookup[strippedCompact] then
        return lookup[strippedCompact]
    end

    local base = lower:gsub("%s*%-.*$", "")
    if lookup[base] then
        return lookup[base]
    end

    local baseCompact = base:gsub("%s+", "")
    if lookup[baseCompact] then
        return lookup[baseCompact]
    end

    return name
end

local function GetCommunityIds(channelName)
    if not channelName or channelName == "" then
        return nil, nil
    end

    local clubId, streamId = channelName:match("^Community:%s*(%d+)%s*:?(%d*)$")
    if not clubId then
        return nil, nil
    end

    clubId = tonumber(clubId)
    if streamId == "" then
        streamId = nil
    else
        streamId = tonumber(streamId)
    end

    return clubId, streamId
end

local function GetCommunityDisplayName(channelName)
    local clubId, streamId = GetCommunityIds(channelName)
    if clubId and C_Club then
        local clubInfo = C_Club.GetClubInfo and C_Club.GetClubInfo(clubId) or nil
        local clubName = clubInfo and clubInfo.name or nil
        local streamName

        if streamId and C_Club.GetStreamInfo then
            local streamInfo = C_Club.GetStreamInfo(clubId, streamId)
            streamName = streamInfo and streamInfo.name or nil
        end

        if clubName and streamName and streamName ~= "" then
            return clubName .. " - " .. streamName
        end
        if streamName and streamName ~= "" then
            return streamName
        end
        if clubName and clubName ~= "" then
            return clubName
        end
    end

    return NormalizeChannelName(channelName)
end

local function GetChannelKey(event, channelName)
    if event == "CHAT_MSG_CHANNEL" and channelName and channelName ~= "" then
        return "CHANNEL:" .. NormalizeChannelName(channelName)
    end
    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" and channelName and channelName ~= "" then
        local clubId, streamId = GetCommunityIds(channelName)
        if clubId and streamId then
            return "COMMUNITY:" .. clubId .. ":" .. streamId
        end
        if clubId then
            return "COMMUNITY:" .. clubId
        end
        return "COMMUNITY:" .. NormalizeChannelName(channelName)
    end
    return event
end

local function BuildChannelList()
    local entries = {}
    local seenKeys = {}
    local seenLabels = {}
    local excludedLabels = {}
    local guildLabelPrefix
    if GetGuildInfo then
        local guildName = GetGuildInfo("player")
        if guildName and guildName ~= "" then
            excludedLabels[guildName:lower()] = true
            local escaped = guildName:gsub("(%W)", "%%%1")
            guildLabelPrefix = "^" .. escaped:lower() .. "%s*%-%s*"
        end
    end

    local function AddEntry(entry)
        if not entry or not entry.key or not entry.label then
            return
        end
        local labelKey = entry.label:lower()
        if labelKey:match("^guild%s*%-") or labelKey:match("^communities%s*%-") then
            return
        end
        if guildLabelPrefix and labelKey:match(guildLabelPrefix .. "guild$") then
            return
        end
        if guildLabelPrefix and labelKey:match(guildLabelPrefix .. "officer$") then
            return
        end
        if excludedLabels[labelKey] then
            return
        end
        if EXCLUDED_CHANNEL_LABELS[labelKey] then
            return
        end
        if seenKeys[entry.key] then
            return
        end
        if seenLabels[labelKey] then
            return
        end
        seenKeys[entry.key] = true
        seenLabels[labelKey] = true
        table.insert(entries, entry)
    end

    for _, item in ipairs(BASE_CHANNEL_LIST) do
        AddEntry(item)
    end

    local list = { GetChannelList() }
    local custom = {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        local label = NormalizeChannelName(name)
        if label and label ~= "" then
            table.insert(custom, { key = "CHANNEL:" .. label, label = label })
        end
    end

    table.sort(custom, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    for _, item in ipairs(custom) do
        AddEntry(item)
    end

    if C_Club and C_Club.GetSubscribedClubs then
        local clubs = C_Club.GetSubscribedClubs()
        local streamsFn = C_Club.GetStreams or C_Club.GetClubStreams

        for _, clubEntry in ipairs(clubs or {}) do
            local clubId = type(clubEntry) == "table" and clubEntry.clubId or clubEntry
            if type(clubId) == "number" then
                local clubInfo = (type(clubEntry) == "table" and clubEntry) or (C_Club.GetClubInfo and C_Club.GetClubInfo(clubId)) or nil
                local clubName = clubInfo and clubInfo.name or nil
                local streams = streamsFn and streamsFn(clubId) or nil

                for _, stream in ipairs(streams or {}) do
                    local label
                    if clubName and stream.name and stream.name ~= "" then
                        label = clubName .. " - " .. stream.name
                    elseif stream.name and stream.name ~= "" then
                        label = stream.name
                    elseif clubName and clubName ~= "" then
                        label = clubName
                    end

                    if label and stream.streamId then
                        AddEntry({
                            key = "COMMUNITY:" .. clubId .. ":" .. stream.streamId,
                            label = label,
                        })
                    end
                end
            end
        end
    end

    return entries
end

local function GetChatColor(event, channelNumber)
    local chatType = event:match("^CHAT_MSG_(.+)$")
    if not chatType then
        return 1, 1, 1
    end

    if chatType == "CHANNEL" and channelNumber and ChatTypeInfo["CHANNEL" .. channelNumber] then
        local info = ChatTypeInfo["CHANNEL" .. channelNumber]
        return info.r, info.g, info.b
    end

    local info = ChatTypeInfo[chatType] or ChatTypeInfo.SAY
    return info.r, info.g, info.b
end

local function CreateAnchor()
    local anchor = CreateFrame("Frame", "ChatInYoFaceAnchor", UIParent)
    anchor:SetSize(300, 30)
    anchor:SetPoint("CENTER")
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")

    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchor.text:SetPoint("CENTER")
    anchor.text:SetText("ChatInYoFace")
    anchor.text:SetTextColor(0.88, 0.92, 0.96)

    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints(true)
    anchor.bg:SetColorTexture(0.11, 0.12, 0.13, 0.85)

    anchor.borderTop = anchor:CreateTexture(nil, "BORDER")
    anchor.borderTop:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    anchor.borderTop:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -1)
    anchor.borderTop:SetHeight(1)
    anchor.borderTop:SetColorTexture(0.24, 0.26, 0.3, 1)

    anchor.borderBottom = anchor:CreateTexture(nil, "BORDER")
    anchor.borderBottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 1, 1)
    anchor.borderBottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    anchor.borderBottom:SetHeight(1)
    anchor.borderBottom:SetColorTexture(0.24, 0.26, 0.3, 1)

    anchor.borderLeft = anchor:CreateTexture(nil, "BORDER")
    anchor.borderLeft:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    anchor.borderLeft:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 1, 1)
    anchor.borderLeft:SetWidth(1)
    anchor.borderLeft:SetColorTexture(0.24, 0.26, 0.3, 1)

    anchor.borderRight = anchor:CreateTexture(nil, "BORDER")
    anchor.borderRight:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -1)
    anchor.borderRight:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    anchor.borderRight:SetWidth(1)
    anchor.borderRight:SetColorTexture(0.24, 0.26, 0.3, 1)

    anchor.accent = anchor:CreateTexture(nil, "ARTWORK")
    anchor.accent:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    anchor.accent:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -1, -1)
    anchor.accent:SetHeight(2)
    anchor.accent:SetColorTexture(0.2, 0.8, 0.9, 1)

    anchor:SetScript("OnDragStart", function(self)
        if not ChatInYoFaceDB.locked then
            self:StartMoving()
        end
    end)

    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ChatInYoFaceDB.anchor.point = point
        ChatInYoFaceDB.anchor.relativePoint = relativePoint
        ChatInYoFaceDB.anchor.x = x
        ChatInYoFaceDB.anchor.y = y
    end)

    return anchor
end

local function CreateMessageFrame(anchor)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    frame:SetSize(600, 400)
    frame.lines = {}
    return frame
end

local function EnsureHideHook(frame)
    if not frame or frame.cifHideHooked then
        return
    end

    frame.cifHideHooked = true
    hooksecurefunc(frame, "Show", function(f)
        if ChatInYoFaceDB and ChatInYoFaceDB.hideChatFrame then
            if f.SetAlpha then
                f:SetAlpha(0)
            end
            if f.EnableMouse then
                f:EnableMouse(false)
            end
        end
    end)
end

local function SetFrameHidden(frame, hidden)
    if not frame then
        return
    end

    EnsureHideHook(frame)

    if hidden then
        if frame.cifPrevAlpha == nil then
            frame.cifPrevAlpha = frame:GetAlpha()
        end
        if frame.cifPrevMouse == nil and frame.IsMouseEnabled then
            frame.cifPrevMouse = frame:IsMouseEnabled()
        end
        frame:SetAlpha(0)
        if frame.EnableMouse then
            frame:EnableMouse(false)
        end
    else
        if frame.cifPrevAlpha ~= nil then
            frame:SetAlpha(frame.cifPrevAlpha)
            frame.cifPrevAlpha = nil
        end
        if frame.cifPrevMouse ~= nil and frame.EnableMouse then
            frame:EnableMouse(frame.cifPrevMouse)
            frame.cifPrevMouse = nil
        end
    end
end

local function SetTabHidden(tab, hidden)
    if not tab then
        return
    end

    EnsureHideHook(tab)

    local text = tab.Text or (tab.GetFontString and tab:GetFontString()) or _G[tab:GetName() .. "Text"]
    local function ApplyRegionAlpha(alpha)
        if not tab.GetNumRegions then
            return
        end
        for i = 1, tab:GetNumRegions() do
            local region = select(i, tab:GetRegions())
            if region and region.SetAlpha then
                region:SetAlpha(alpha)
            end
        end
    end

    if hidden then
        if tab.cifPrevAlpha == nil then
            tab.cifPrevAlpha = tab:GetAlpha()
        end
        if not tab.cifRegionAlpha then
            tab.cifRegionAlpha = {}
            if tab.GetNumRegions then
                for i = 1, tab:GetNumRegions() do
                    local region = select(i, tab:GetRegions())
                    if region and region.GetAlpha then
                        tab.cifRegionAlpha[i] = region:GetAlpha()
                    end
                end
            end
        end
        tab:SetAlpha(0)
        if text then
            text:SetAlpha(0)
        end
        ApplyRegionAlpha(0)
        tab:EnableMouse(false)
    else
        if tab.cifPrevAlpha ~= nil then
            tab:SetAlpha(tab.cifPrevAlpha)
            tab.cifPrevAlpha = nil
        end
        if text then
            text:SetAlpha(1)
        end
        if tab.cifRegionAlpha then
            if tab.GetNumRegions then
                for i = 1, tab:GetNumRegions() do
                    local region = select(i, tab:GetRegions())
                    local alpha = tab.cifRegionAlpha[i]
                    if region and region.SetAlpha and alpha ~= nil then
                        region:SetAlpha(alpha)
                    end
                end
            end
            tab.cifRegionAlpha = nil
        end
        tab:EnableMouse(true)
    end
end

local function SetEditBoxVisibility(editBox, hidden)
    if not editBox then
        return
    end

    if hidden then
        local active = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or nil
        if not editBox.cifDetached then
            editBox.cifDetached = true
            editBox.cifPrevParent = editBox:GetParent()
            editBox.cifPrevPoints = {}
            for i = 1, editBox:GetNumPoints() do
                local point, relativeTo, relativePoint, x, y = editBox:GetPoint(i)
                editBox.cifPrevPoints[i] = { point, relativeTo, relativePoint, x, y }
            end
            editBox:SetParent(UIParent)
            editBox:ClearAllPoints()
            for _, entry in ipairs(editBox.cifPrevPoints) do
                editBox:SetPoint(entry[1], entry[2], entry[3], entry[4], entry[5])
            end
        end
        if active and active == editBox then
            editBox:SetAlpha(1)
            editBox:Show()
        else
            editBox:Hide()
        end
    else
        if editBox.cifDetached then
            editBox.cifDetached = nil
            local parent = editBox.cifPrevParent or UIParent
            local points = editBox.cifPrevPoints
            editBox.cifPrevParent = nil
            editBox.cifPrevPoints = nil
            editBox:SetParent(parent)
            if points then
                editBox:ClearAllPoints()
                for _, entry in ipairs(points) do
                    editBox:SetPoint(entry[1], entry[2], entry[3], entry[4], entry[5])
                end
            end
        end
        local active = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or nil
        if active and active == editBox then
            editBox:Show()
        else
            editBox:Hide()
        end
    end
end

local function ApplyChatFrameVisibility(hidden)
    if not NUM_CHAT_WINDOWS then
        return
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local editBox = _G["ChatFrame" .. i .. "EditBox"]

        SetFrameHidden(frame, hidden)
        SetTabHidden(tab, hidden)
        SetEditBoxVisibility(editBox, hidden)
    end
end

local chatVisibilityHooked = false

local function HookChatFrameVisibilityUpdates()
    if chatVisibilityHooked or not hooksecurefunc then
        return
    end

    chatVisibilityHooked = true

    local function ReapplyIfHidden()
        if ChatInYoFaceDB and ChatInYoFaceDB.hideChatFrame then
            ApplyChatFrameVisibility(true)
        end
    end

    if type(FCF_DockUpdateTabs) == "function" then
        hooksecurefunc("FCF_DockUpdateTabs", ReapplyIfHidden)
    end
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", ReapplyIfHidden)
    end
    if type(FCF_OpenNewWindow) == "function" then
        hooksecurefunc("FCF_OpenNewWindow", ReapplyIfHidden)
    end
    if type(ChatEdit_ActivateChat) == "function" then
        hooksecurefunc("ChatEdit_ActivateChat", ReapplyIfHidden)
    end
    if type(ChatEdit_DeactivateChat) == "function" then
        hooksecurefunc("ChatEdit_DeactivateChat", ReapplyIfHidden)
    end
end

local function ApplyLockState(anchor)
    if ChatInYoFaceDB.locked then
        anchor:EnableMouse(false)
        anchor.text:Hide()
        anchor.bg:Hide()
        if anchor.borderTop then
            anchor.borderTop:Hide()
        end
        if anchor.borderBottom then
            anchor.borderBottom:Hide()
        end
        if anchor.borderLeft then
            anchor.borderLeft:Hide()
        end
        if anchor.borderRight then
            anchor.borderRight:Hide()
        end
        if anchor.accent then
            anchor.accent:Hide()
        end
    else
        anchor:EnableMouse(true)
        anchor.text:Show()
        anchor.bg:Show()
        if anchor.borderTop then
            anchor.borderTop:Show()
        end
        if anchor.borderBottom then
            anchor.borderBottom:Show()
        end
        if anchor.borderLeft then
            anchor.borderLeft:Show()
        end
        if anchor.borderRight then
            anchor.borderRight:Show()
        end
        if anchor.accent then
            anchor.accent:Show()
        end
    end
end

local function ApplyFont(line)
    line:SetFont(ChatInYoFaceDB.font, ChatInYoFaceDB.size, ChatInYoFaceDB.outline)
end

local function RefreshFonts(messageFrame)
    for _, line in ipairs(messageFrame.lines) do
        ApplyFont(line)
    end
end

local function GetMaxLineWidth()
    return math.floor(GetScreenWidth() * 0.25)
end

local function GetChatPrefix(event, displayChannelName, channelNumber)
    if event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM" then
        return nil
    end
    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" and displayChannelName and displayChannelName ~= "" then
        return displayChannelName
    end
    if event == "CHAT_MSG_CHANNEL" then
        if channelNumber and tonumber(channelNumber) then
            return tostring(channelNumber)
        end
        if displayChannelName and displayChannelName ~= "" then
            return displayChannelName
        end
    end
    if event == "CHAT_MSG_GUILD" then
        return "G"
    end
    if event == "CHAT_MSG_OFFICER" then
        return "O"
    end

    local chatType = event:match("^CHAT_MSG_(.+)$")
    if chatType then
        local label = _G["CHAT_" .. chatType]
        if type(label) == "string" and label ~= "" then
            label = label:gsub("%s*:%s*$", "")
            if label ~= "" then
                return label
            end
        end
        return chatType:gsub("_", " ")
    end

    return nil
end

local function CreateLine(messageFrame)
    local line = messageFrame:CreateFontString(nil, "OVERLAY")
    ApplyFont(line)
    line:SetJustifyH("CENTER")
    line:SetWordWrap(true)
    line:SetWidth(GetMaxLineWidth())
    line:SetAlpha(1)
    line.expire = 0
    return line
end

local function LayoutLines(messageFrame)
    local startY = 0
    for i = 1, #messageFrame.lines do
        local line = messageFrame.lines[i]
        line:ClearAllPoints()
        line:SetPoint("TOP", messageFrame, "TOP", 0, -startY)
        line:SetWidth(GetMaxLineWidth())
        local height = line:GetStringHeight() or 0
        if height < ChatInYoFaceDB.size then
            height = ChatInYoFaceDB.size
        end
        startY = startY + height + ChatInYoFaceDB.spacing
    end
end

local function AddMessage(messageFrame, text, r, g, b)
    local line
    if #messageFrame.lines < ChatInYoFaceDB.lines then
        line = CreateLine(messageFrame)
        table.insert(messageFrame.lines, 1, line)
    else
        line = table.remove(messageFrame.lines)
        table.insert(messageFrame.lines, 1, line)
    end

    line:SetText(text)
    line:SetTextColor(r, g, b)
    line.expire = GetTime() + ChatInYoFaceDB.time
    line:SetAlpha(1)

    LayoutLines(messageFrame)
end

local function ShowGuildMotd(messageFrame)
    if not ChatInYoFaceDB.channels or ChatInYoFaceDB.channels["GUILD_MOTD"] == false then
        return
    end

    if not IsInGuild or not IsInGuild() then
        return
    end

    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or nil
    if not motd or motd == "" then
        return
    end

    local r, g, b = GetChatColor("CHAT_MSG_GUILD")
    AddMessage(messageFrame, "MOTD: " .. motd, r, g, b)
end

local function PlayChannelSound(channelKey)
    local sounds = ChatInYoFaceDB.channelSounds
    if not sounds then
        return
    end

    local sound = sounds[channelKey]
    if not sound or sound == "" then
        return
    end

    if type(sound) == "number" then
        PlaySound(sound, "Master")
    else
        PlaySoundFile(sound, "Master")
    end
end

local function UpdateFade(messageFrame)
    local now = GetTime()
    for i = #messageFrame.lines, 1, -1 do
        local line = messageFrame.lines[i]
        local remaining = line.expire - now
        if remaining <= 0 then
            line:SetText("")
            line:SetAlpha(0)
        elseif remaining < 1.5 then
            line:SetAlpha(remaining / 1.5)
        else
            line:SetAlpha(1)
        end
    end
end

local function IsPlayerSender(sender)
    if not sender or sender == "" then
        return false
    end

    local shortSender = Ambiguate and Ambiguate(sender, "short") or sender
    local playerName, playerRealm = UnitFullName and UnitFullName("player") or nil
    if not playerName then
        return false
    end

    if playerRealm and playerRealm ~= "" then
        local fullName = playerName .. "-" .. playerRealm
        return sender == fullName or shortSender == playerName
    end

    return shortSender == playerName or sender == playerName
end

local function HandleChatEvent(messageFrame, event, ...)
    if not event or not event:match("^CHAT_MSG_") then
        return
    end

    local msg, sender, _, _, _, _, _, _, channelNumber, channelName = ...
    if debugUntil > 0 and GetTime() <= debugUntil then
        print(string.format("[ChatInYoFace] %s channelNumber=%s channelName=%s", tostring(event), tostring(channelNumber), tostring(channelName)))
    end
    local displayChannelName
    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        displayChannelName = GetCommunityDisplayName(channelName)
    elseif event == "CHAT_MSG_CHANNEL" then
        displayChannelName = ResolveChatChannelName(channelNumber, channelName)
    else
        displayChannelName = NormalizeChannelName(channelName)
    end

    local channelKey = GetChannelKey(event, displayChannelName)
    if ChatInYoFaceDB.channels and ChatInYoFaceDB.channels[channelKey] == false then
        return
    end

    if not msg or msg == "" then
        return
    end

    local display = msg
    if event ~= "CHAT_MSG_LOOT" and sender and sender ~= "" and not IsPlayerSender(sender) then
        display = string.format("%s: %s", sender, msg)
    end

    if event == "CHAT_MSG_LOOT" then
        local itemId = msg and msg:match("item:(%d+)")
        if itemId and GetItemInfoInstant then
            local _, _, _, _, icon = GetItemInfoInstant(tonumber(itemId))
            if icon then
                display = string.format("|T%s:40:40:0:0|t %s", icon, display)
            end
        end
    end

    local r, g, b = GetChatColor(event, channelNumber)

    local prefix = GetChatPrefix(event, displayChannelName, channelNumber)
    if prefix and prefix ~= "" then
        display = string.format("%s: %s", prefix, display)
    end

    PlayChannelSound(channelKey)
    AddMessage(messageFrame, display, r, g, b)
end

local function CreateOptionsPanel(anchor, messageFrame)
    local panel = CreateFrame("Frame", "ChatInYoFaceOptionsPanel")
    panel.name = "ChatInYoFace"

    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)
    panel.bg:SetColorTexture(0.08, 0.09, 0.1, 0.55)

    panel.borderTop = panel:CreateTexture(nil, "BORDER")
    panel.borderTop:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    panel.borderTop:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    panel.borderTop:SetHeight(1)
    panel.borderTop:SetColorTexture(0.2, 0.22, 0.25, 0.8)

    panel.borderBottom = panel:CreateTexture(nil, "BORDER")
    panel.borderBottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    panel.borderBottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    panel.borderBottom:SetHeight(1)
    panel.borderBottom:SetColorTexture(0.2, 0.22, 0.25, 0.8)

    panel.borderLeft = panel:CreateTexture(nil, "BORDER")
    panel.borderLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    panel.borderLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    panel.borderLeft:SetWidth(1)
    panel.borderLeft:SetColorTexture(0.2, 0.22, 0.25, 0.8)

    panel.borderRight = panel:CreateTexture(nil, "BORDER")
    panel.borderRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    panel.borderRight:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    panel.borderRight:SetWidth(1)
    panel.borderRight:SetColorTexture(0.2, 0.22, 0.25, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "ChatInYoFaceOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar.bg = scrollBar:CreateTexture(nil, "BACKGROUND")
        scrollBar.bg:SetAllPoints(scrollBar)
        scrollBar.bg:SetColorTexture(0.1, 0.11, 0.12, 0.9)

        if scrollBar.SetThumbTexture then
            scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
            local thumb = scrollBar:GetThumbTexture()
            if thumb then
                thumb:SetVertexColor(0.2, 0.8, 0.9)
            end
        end

        local up = scrollBar.ScrollUpButton or _G[scrollBar:GetName() .. "ScrollUpButton"]
        local down = scrollBar.ScrollDownButton or _G[scrollBar:GetName() .. "ScrollDownButton"]
        if up and up.SetNormalTexture then
            up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            up:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
            up:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", "ADD")
        end
        if down and down.SetNormalTexture then
            down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            down:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
            down:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
        end
    end

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ChatInYoFace")
    local titleFont, _, titleFlags = title:GetFont()
    if titleFont then
        title:SetFont(titleFont, 22, titleFlags)
    end
    title:SetTextColor(1, 1, 1)

    local accent = content:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    accent:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -22)
    accent:SetHeight(2)
    accent:SetColorTexture(0.2, 0.8, 0.9, 1)

    local function StyleSectionHeader(label)
        local font, _, flags = label:GetFont()
        if font then
            label:SetFont(font, 14, flags)
        end
        label:SetTextColor(0.88, 0.92, 0.96)
    end

    local BACKDROP_INFO = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    }

    local function ApplyBackdrop(frame)
        if not frame or not frame.SetBackdrop then
            return
        end
        frame:SetBackdrop(BACKDROP_INFO)
        frame:SetBackdropColor(0.11, 0.12, 0.13, 0.9)
        frame:SetBackdropBorderColor(0.24, 0.26, 0.3, 1)
    end

    local function StyleCheckbox(check)
        local box = check and check:GetNormalTexture()
        if box then
            box:SetDesaturated(true)
            box:SetVertexColor(0.2, 0.8, 0.9)
        end
        local highlight = check and check:GetHighlightTexture()
        if highlight then
            highlight:SetColorTexture(0.2, 0.8, 0.9, 0.15)
        end
    end

    local function StyleDropdown(dropdown)
        local name = dropdown and dropdown.GetName and dropdown:GetName() or nil
        if name then
            local left = _G[name .. "Left"]
            local middle = _G[name .. "Middle"]
            local right = _G[name .. "Right"]
            if left then left:Hide() end
            if middle then middle:Hide() end
            if right then right:Hide() end
        end

        if dropdown and not dropdown.bgFrame then
            dropdown.bgFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
            dropdown.bgFrame:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, -2)
            dropdown.bgFrame:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -20, 6)
            local level = (dropdown.GetFrameLevel and dropdown:GetFrameLevel() or 0) - 1
            if level < 0 then
                level = 0
            end
            dropdown.bgFrame:SetFrameLevel(level)
            dropdown.bgFrame:EnableMouse(false)
        end
        ApplyBackdrop(dropdown.bgFrame or dropdown)

        local button = dropdown and _G[dropdown:GetName() .. "Button"]
        if button and button.SetNormalTexture then
            button:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            button:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
            button:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
        end
    end

    local function SetDropdownTextColor(dropdown, r, g, b)
        if UIDropDownMenu_SetTextColor then
            UIDropDownMenu_SetTextColor(dropdown, r, g, b)
            return
        end

        local name = dropdown and dropdown.GetName and dropdown:GetName() or nil
        local text = name and _G[name .. "Text"] or nil
        if text and text.SetTextColor then
            text:SetTextColor(r, g, b)
        end
    end

    local function StyleDropdownList(listFrame)
        if not listFrame or listFrame.cifStyled then
            return
        end

        listFrame.cifStyled = true
        if listFrame.SetBackdrop then
            listFrame:SetBackdrop(BACKDROP_INFO)
            listFrame:SetBackdropColor(0.11, 0.12, 0.13, 0.95)
            listFrame:SetBackdropBorderColor(0.24, 0.26, 0.3, 1)
        end

        for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
            local button = _G[listFrame:GetName() .. "Button" .. i]
            if button and button.GetHighlightTexture then
                local hl = button:GetHighlightTexture()
                if hl then
                    hl:SetColorTexture(0.2, 0.8, 0.9, 0.18)
                end
            end
            if button and button.GetCheckedTexture then
                local checked = button:GetCheckedTexture()
                if checked then
                    checked:SetVertexColor(0.2, 0.8, 0.9)
                end
            end
            if button and button.GetFontString then
                local text = button:GetFontString()
                if text then
                    if button.checked then
                        text:SetTextColor(0.2, 0.8, 0.9)
                    else
                        text:SetTextColor(1, 1, 1)
                    end
                end
            end
        end
    end

    local function StyleDropdownLists()
        for i = 1, UIDROPDOWNMENU_MAXLEVELS do
            local listFrame = _G["DropDownList" .. i]
            if listFrame then
                StyleDropdownList(listFrame)
            end
        end
    end

    StyleDropdownLists()
    if hooksecurefunc and UIDropDownMenu_CreateFrames then
        hooksecurefunc("UIDropDownMenu_CreateFrames", StyleDropdownLists)
    end

    local function StyleSlider(slider)
        if not slider then
            return
        end
        local name = slider.GetName and slider:GetName() or nil
        if name then
            local bg = _G[name .. "Background"]
            local track = _G[name .. "Track"]
            local low = _G[name .. "TrackLow"]
            local high = _G[name .. "TrackHigh"]
            if bg then bg:SetTexture(nil) end
            if track then track:SetTexture(nil) end
            if low then low:SetTexture(nil) end
            if high then high:SetTexture(nil) end
        end

        if not slider.bgFrame then
            slider.bgFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
            slider.bgFrame:SetPoint("TOPLEFT", slider, "TOPLEFT", 6, -18)
            slider.bgFrame:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", -6, 18)
        end
        ApplyBackdrop(slider.bgFrame)

        if not slider.bar then
            slider.bar = slider:CreateTexture(nil, "BORDER")
            slider.bar:SetPoint("LEFT", slider, "LEFT", 8, 0)
            slider.bar:SetPoint("RIGHT", slider, "RIGHT", -8, 0)
            slider.bar:SetHeight(6)
            slider.bar:SetColorTexture(0.12, 0.13, 0.15, 1)
        end

        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
            thumb:SetVertexColor(0.2, 0.8, 0.9)
        end
    end

    local function StyleButton(button)
        if not button then
            return
        end
        ApplyBackdrop(button)
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        local hl = button:GetHighlightTexture()
        if hl then
            hl:SetVertexColor(0.2, 0.8, 0.9, 0.15)
        end
    end

    local lock = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    lock:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    lock.Text:SetText("Lock anchor")
    StyleCheckbox(lock)
    lock:SetScript("OnClick", function(self)
        ChatInYoFaceDB.locked = self:GetChecked() and true or false
        ApplyLockState(anchor)
    end)

    local hideChat = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    hideChat:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -8)
    hideChat.Text:SetText("Hide original chat")
    StyleCheckbox(hideChat)
    hideChat:SetScript("OnClick", function(self)
        ChatInYoFaceDB.hideChatFrame = self:GetChecked() and true or false
        ApplyChatFrameVisibility(ChatInYoFaceDB.hideChatFrame)
    end)

    local fontLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", hideChat, "BOTTOMLEFT", 0, -14)
    fontLabel:SetText("Font")
    StyleSectionHeader(fontLabel)

    local fontDropdown = CreateFrame("Frame", "ChatInYoFaceFontDropdown", content, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -6)
    StyleDropdown(fontDropdown)

    local fontOptions = BuildFontOptions()

    local function RefreshFontOptions()
        fontOptions = BuildFontOptions()
    end

    local function SetFont(path)
        ChatInYoFaceDB.font = path
        RefreshFonts(messageFrame)
        LayoutLines(messageFrame)
    end

    UIDropDownMenu_Initialize(fontDropdown, function(self, level)
        RefreshFontOptions()
        local info = UIDropDownMenu_CreateInfo()
        for _, item in ipairs(fontOptions) do
            info.text = item.name
            info.textR, info.textG, info.textB = 1, 1, 1
            info.func = function()
                UIDropDownMenu_SetSelectedValue(fontDropdown, item.path)
                UIDropDownMenu_SetText(fontDropdown, item.name)
                SetFont(item.path)
            end
            info.value = item.path
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(fontDropdown, 160)
    UIDropDownMenu_SetText(fontDropdown, " ")
    SetDropdownTextColor(fontDropdown, 1, 1, 1)

    local sizeSlider = CreateFrame("Slider", "ChatInYoFaceSizeSlider", content, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 0, -24)
    StyleSlider(sizeSlider)
    sizeSlider:SetMinMaxValues(8, 64)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider.Text:SetText("Font Size")
    sizeSlider.Low:SetText("8")
    sizeSlider.High:SetText("64")
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        ChatInYoFaceDB.size = value
        self:SetValue(value)
        RefreshFonts(messageFrame)
        LayoutLines(messageFrame)
    end)
    sizeSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Font Size: " .. math.floor(self:GetValue() + 0.5))
    end)
    sizeSlider:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    sizeSlider:HookScript("OnValueChanged", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText("Font Size: " .. math.floor(self:GetValue() + 0.5))
        end
    end)

    local outlineCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    outlineCheck:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -12)
    outlineCheck.Text:SetText("Outline text")
    StyleCheckbox(outlineCheck)
    outlineCheck:SetScript("OnClick", function(self)
        ChatInYoFaceDB.outline = self:GetChecked() and "THICKOUTLINE" or ""
        RefreshFonts(messageFrame)
        LayoutLines(messageFrame)
    end)

    local timeSlider = CreateFrame("Slider", "ChatInYoFaceTimeSlider", content, "OptionsSliderTemplate")
    timeSlider:SetPoint("TOPLEFT", outlineCheck, "BOTTOMLEFT", 0, -24)
    StyleSlider(timeSlider)
    timeSlider:SetMinMaxValues(1, 30)
    timeSlider:SetValueStep(1)
    timeSlider:SetObeyStepOnDrag(true)
    timeSlider.Text:SetText("Fade Time (s)")
    timeSlider.Low:SetText("1")
    timeSlider.High:SetText("30")
    timeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        ChatInYoFaceDB.time = value
        self:SetValue(value)
    end)
    timeSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Fade Time: " .. math.floor(self:GetValue() + 0.5) .. "s")
    end)
    timeSlider:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    timeSlider:HookScript("OnValueChanged", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText("Fade Time: " .. math.floor(self:GetValue() + 0.5) .. "s")
        end
    end)

    local channelsLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    channelsLabel:SetPoint("TOPLEFT", timeSlider, "BOTTOMLEFT", 0, -18)
    channelsLabel:SetText("Chat Channels")
    StyleSectionHeader(channelsLabel)

    local channelList = BuildChannelList()
    local channelChecks = {}
    local checksByIndex = {}
    local columns = 3
    local rowsPerColumn = math.max(1, math.ceil(#channelList / columns))

    local function ClearChannelChecks()
        for _, check in pairs(channelChecks) do
            check:Hide()
            check:SetParent(nil)
        end
        channelChecks = {}
        checksByIndex = {}
    end

    local function BuildChannelChecks()
        ClearChannelChecks()
        channelList = BuildChannelList()
        rowsPerColumn = math.max(1, math.ceil(#channelList / columns))

        for i, entry in ipairs(channelList) do
            local check = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
            local row = (i - 1) % rowsPerColumn

            if i == 1 then
                check:SetPoint("TOPLEFT", channelsLabel, "BOTTOMLEFT", 0, -8)
            elseif row == 0 then
                local prevColumnCheck = checksByIndex[i - rowsPerColumn]
                check:SetPoint("TOPLEFT", prevColumnCheck, "TOPRIGHT", 140, 0)
            else
                local prevRowCheck = checksByIndex[i - 1]
                check:SetPoint("TOPLEFT", prevRowCheck, "BOTTOMLEFT", 0, -6)
            end

            check.Text:SetText(entry.label)
            StyleCheckbox(check)
            check:SetScript("OnClick", function(self)
                ChatInYoFaceDB.channels[entry.key] = self:GetChecked() and true or false
            end)
            channelChecks[entry.key] = check
            checksByIndex[i] = check
        end
    end

    BuildChannelChecks()

    local bottomAnchor = checksByIndex[rowsPerColumn] or channelsLabel

    local soundLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    soundLabel:SetPoint("TOPLEFT", bottomAnchor, "BOTTOMLEFT", 0, -14)
    soundLabel:SetText("Channel Sounds")
    StyleSectionHeader(soundLabel)

    local channelSelect = CreateFrame("Frame", "ChatInYoFaceSoundChannelDropdown", content, "UIDropDownMenuTemplate")
    channelSelect:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -6)
    UIDropDownMenu_SetWidth(channelSelect, 170)
    StyleDropdown(channelSelect)

    local soundSelect = CreateFrame("Frame", "ChatInYoFaceSoundDropdown", content, "UIDropDownMenuTemplate")
    soundSelect:SetPoint("TOPLEFT", channelSelect, "TOPRIGHT", 8, 0)
    UIDropDownMenu_SetWidth(soundSelect, 200)
    StyleDropdown(soundSelect)

    local previewButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    previewButton:SetPoint("TOPLEFT", soundSelect, "TOPRIGHT", 8, -2)
    previewButton:SetSize(70, 22)
    previewButton:SetText("Preview")
    StyleButton(previewButton)

    local function UpdateScrollLayout()
        local width = scrollFrame:GetWidth()
        if width and width > 0 then
            content:SetWidth(width)
        end
        local top = title:GetTop()
        local bottom = previewButton:GetBottom() or soundSelect:GetBottom()
        if top and bottom then
            local height = top - bottom + 40
            if height < 1 then
                height = 1
            end
            content:SetHeight(height)
        end
    end

    local selectedSoundChannel = channelList[1] and channelList[1].key or nil
    local soundOptions = BuildSoundOptions()

    local function RefreshSoundOptions()
        soundOptions = BuildSoundOptions()
    end

    local function GetSoundLabel(value)
        if not value then
            return "None"
        end
        for _, item in ipairs(soundOptions) do
            if item.value == value then
                return item.name
            end
        end
        return tostring(value)
    end

    local function SetChannelSound(channelKey, value)
        if not channelKey then
            return
        end
        if value == SOUND_NONE then
            ChatInYoFaceDB.channelSounds[channelKey] = nil
        else
            ChatInYoFaceDB.channelSounds[channelKey] = value
        end
    end

    local function PlaySoundValue(value)
        if not value or value == SOUND_NONE then
            return
        end

        if type(value) == "number" then
            PlaySound(value, "Master")
        else
            PlaySoundFile(value, "Master")
        end
    end

    local function RefreshSoundDropdownText()
        if not selectedSoundChannel then
            UIDropDownMenu_SetText(soundSelect, "None")
            return
        end
        local current = ChatInYoFaceDB.channelSounds[selectedSoundChannel]
        UIDropDownMenu_SetSelectedValue(soundSelect, current or SOUND_NONE)
        UIDropDownMenu_SetText(soundSelect, GetSoundLabel(current))
    end

    local function RefreshPreviewButton()
        local current = selectedSoundChannel and ChatInYoFaceDB.channelSounds[selectedSoundChannel] or nil
        previewButton:SetEnabled(current and current ~= SOUND_NONE)
    end

    UIDropDownMenu_Initialize(channelSelect, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, entry in ipairs(channelList) do
            info.text = entry.label
            info.textR, info.textG, info.textB = 1, 1, 1
            info.value = entry.key
            info.func = function()
                selectedSoundChannel = entry.key
                UIDropDownMenu_SetSelectedValue(channelSelect, entry.key)
                UIDropDownMenu_SetText(channelSelect, entry.label)
                SetDropdownTextColor(channelSelect, 1, 1, 1)
                RefreshSoundOptions()
                RefreshSoundDropdownText()
                RefreshPreviewButton()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(channelSelect, " ")
    SetDropdownTextColor(channelSelect, 1, 1, 1)

    UIDropDownMenu_Initialize(soundSelect, function(self, level)
        RefreshSoundOptions()
        local info = UIDropDownMenu_CreateInfo()
        for _, item in ipairs(soundOptions) do
            info.text = item.name
            info.textR, info.textG, info.textB = 1, 1, 1
            info.value = item.value
            info.func = function()
                SetChannelSound(selectedSoundChannel, item.value)
                UIDropDownMenu_SetSelectedValue(soundSelect, item.value)
                UIDropDownMenu_SetText(soundSelect, item.name)
                SetDropdownTextColor(soundSelect, 1, 1, 1)
                RefreshPreviewButton()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(soundSelect, " ")
    SetDropdownTextColor(soundSelect, 1, 1, 1)

    previewButton:SetScript("OnClick", function()
        local current = selectedSoundChannel and ChatInYoFaceDB.channelSounds[selectedSoundChannel] or nil
        PlaySoundValue(current)
    end)

    panel.refresh = function()
        lock:SetChecked(ChatInYoFaceDB.locked)
        hideChat:SetChecked(ChatInYoFaceDB.hideChatFrame)
        BuildChannelChecks()
        bottomAnchor = checksByIndex[rowsPerColumn] or channelsLabel
        soundLabel:ClearAllPoints()
        soundLabel:SetPoint("TOPLEFT", bottomAnchor, "BOTTOMLEFT", 0, -14)

        if selectedSoundChannel and not channelChecks[selectedSoundChannel] then
            selectedSoundChannel = channelList[1] and channelList[1].key or nil
        end

        RefreshFontOptions()
        UIDropDownMenu_SetSelectedValue(fontDropdown, ChatInYoFaceDB.font)
        UIDropDownMenu_SetText(fontDropdown, (function()
            for _, item in ipairs(fontOptions) do
                if item.path == ChatInYoFaceDB.font then
                    return item.name
                end
            end
            return ChatInYoFaceDB.font
        end)())
        SetDropdownTextColor(fontDropdown, 1, 1, 1)
        sizeSlider:SetValue(ChatInYoFaceDB.size)
        outlineCheck:SetChecked(ChatInYoFaceDB.outline ~= nil and ChatInYoFaceDB.outline ~= "")
        timeSlider:SetValue(ChatInYoFaceDB.time)

        for _, entry in ipairs(channelList) do
            local check = channelChecks[entry.key]
            if check then
                check:SetChecked(ChatInYoFaceDB.channels[entry.key] ~= false)
            end
        end

        if selectedSoundChannel then
            for _, entry in ipairs(channelList) do
                if entry.key == selectedSoundChannel then
                    UIDropDownMenu_SetSelectedValue(channelSelect, entry.key)
                    UIDropDownMenu_SetText(channelSelect, entry.label)
                    SetDropdownTextColor(channelSelect, 1, 1, 1)
                    break
                end
            end
        end
        RefreshSoundOptions()
        RefreshSoundDropdownText()
        SetDropdownTextColor(soundSelect, 1, 1, 1)
        RefreshPreviewButton()
        UpdateScrollLayout()
    end

    panel:SetScript("OnShow", function()
        panel.refresh()
        UpdateScrollLayout()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end

    return panel
end

local function SetupSlashCommands(anchor, messageFrame)
    SLASH_CHATINYO1 = "/cif"
    SlashCmdList.CHATINYO = function(msg)
        local cmd, rest = msg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()

        if cmd == "unlock" then
            ChatInYoFaceDB.locked = false
            ApplyLockState(anchor)
        elseif cmd == "lock" then
            ChatInYoFaceDB.locked = true
            ApplyLockState(anchor)
        elseif cmd == "font" and rest ~= "" then
            ChatInYoFaceDB.font = rest
            RefreshFonts(messageFrame)
            LayoutLines(messageFrame)
        elseif cmd == "size" then
            local size = tonumber(rest)
            if size and size >= 8 and size <= 64 then
                ChatInYoFaceDB.size = size
                RefreshFonts(messageFrame)
                LayoutLines(messageFrame)
            end
        elseif cmd == "lines" then
            local count = tonumber(rest)
            if count and count >= 1 and count <= 20 then
                ChatInYoFaceDB.lines = count
                LayoutLines(messageFrame)
            end
        elseif cmd == "time" then
            local t = tonumber(rest)
            if t and t >= 1 and t <= 30 then
                ChatInYoFaceDB.time = t
            end
        elseif cmd == "debug" then
            debugUntil = GetTime() + 60
            print("ChatInYoFace: debug logging enabled for 60 seconds.")
        else
            print("ChatInYoFace commands:")
            print("/cif lock - lock anchor")
            print("/cif unlock - unlock anchor")
            print("/cif font <path> - set font path")
            print("/cif size <8-64> - set font size")
            print("/cif lines <1-20> - number of lines")
            print("/cif time <1-30> - seconds on screen")
            print("/cif debug - log channel details for 60s")
        end
    end
end

local function RegisterChatEvents(frame)
    local events = {
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_LOOT",
        "CHAT_MSG_SYSTEM",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_COMMUNITIES_CHANNEL",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "GUILD_MOTD",
        "PLAYER_GUILD_UPDATE",
    }

    for _, event in ipairs(events) do
        frame:RegisterEvent(event)
    end
end

local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("ADDON_LOADED")

addonFrame:SetScript("OnEvent", function(self, event, addonName)
    if event ~= "ADDON_LOADED" or addonName ~= ADDON_NAME then
        return
    end

    ChatInYoFaceDB = CopyDefaults(DEFAULTS, ChatInYoFaceDB)
    if ChatInYoFaceDB.channels then
        if ChatInYoFaceDB.channels["CHAT_MSG_GUILD_MOTD"] ~= nil and ChatInYoFaceDB.channels["GUILD_MOTD"] == nil then
            ChatInYoFaceDB.channels["GUILD_MOTD"] = ChatInYoFaceDB.channels["CHAT_MSG_GUILD_MOTD"]
        end
        ChatInYoFaceDB.channels["CHAT_MSG_GUILD_MOTD"] = nil
    end
    RegisterLocalFonts()

    local anchor = CreateAnchor()
    anchor:ClearAllPoints()
    anchor:SetPoint(ChatInYoFaceDB.anchor.point, UIParent, ChatInYoFaceDB.anchor.relativePoint, ChatInYoFaceDB.anchor.x, ChatInYoFaceDB.anchor.y)

    local messageFrame = CreateMessageFrame(anchor)
    SetupSlashCommands(anchor, messageFrame)
    ApplyLockState(anchor)
    ApplyChatFrameVisibility(ChatInYoFaceDB.hideChatFrame)
    HookChatFrameVisibilityUpdates()

    CreateOptionsPanel(anchor, messageFrame)
    ShowGuildMotd(messageFrame)

    self:SetScript("OnUpdate", function(_, elapsed)
        UpdateFade(messageFrame)
    end)

    RegisterChatEvents(self)
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ADDON_LOADED")
    self:SetScript("OnEvent", function(_, chatEvent, ...)
        if chatEvent == "PLAYER_LOGIN" or chatEvent == "PLAYER_ENTERING_WORLD" then
            ApplyChatFrameVisibility(ChatInYoFaceDB.hideChatFrame)
        elseif chatEvent == "GUILD_MOTD" or chatEvent == "PLAYER_GUILD_UPDATE" then
            ShowGuildMotd(messageFrame)
        else
            HandleChatEvent(messageFrame, chatEvent, ...)
        end
    end)
end)
