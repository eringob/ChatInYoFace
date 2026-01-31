local ADDON_NAME = ...

local DEFAULTS = {
    anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    locked = true,
    font = "Fonts\\FRIZQT__.TTF",
    size = 18,
    outline = "OUTLINE",
    lines = 6,
    time = 6,
    spacing = 2,
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
        CHAT_MSG_GUILD = true,
        CHAT_MSG_OFFICER = true,
        CHAT_MSG_CHANNEL = true,
        CHAT_MSG_INSTANCE_CHAT = true,
        CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    },
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

    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints(true)
    anchor.bg:SetColorTexture(0, 0, 0, 0.35)

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

local function ApplyLockState(anchor)
    if ChatInYoFaceDB.locked then
        anchor:EnableMouse(false)
        anchor.text:Hide()
        anchor.bg:Hide()
    else
        anchor:EnableMouse(true)
        anchor.text:Show()
        anchor.bg:Show()
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

local function CreateLine(messageFrame)
    local line = messageFrame:CreateFontString(nil, "OVERLAY")
    ApplyFont(line)
    line:SetJustifyH("CENTER")
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
        startY = startY + ChatInYoFaceDB.size + ChatInYoFaceDB.spacing
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

local function HandleChatEvent(messageFrame, event, ...)
    if ChatInYoFaceDB.channels and ChatInYoFaceDB.channels[event] == false then
        return
    end

    local msg, sender, _, _, _, _, _, _, channelNumber, channelName = ...

    if not msg or msg == "" then
        return
    end

    local display = msg
    if sender and sender ~= "" then
        display = string.format("%s: %s", sender, msg)
    end

    local r, g, b = GetChatColor(event, channelNumber)

    if event == "CHAT_MSG_CHANNEL" and channelName and channelName ~= "" then
        display = string.format("[%s] %s", channelName, display)
    end

    AddMessage(messageFrame, display, r, g, b)
end

local function CreateOptionsPanel(anchor, messageFrame)
    local panel = CreateFrame("Frame", "ChatInYoFaceOptionsPanel")
    panel.name = "ChatInYoFace"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ChatInYoFace")

    local lock = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lock:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    lock.Text:SetText("Lock anchor")
    lock:SetScript("OnClick", function(self)
        ChatInYoFaceDB.locked = self:GetChecked() and true or false
        ApplyLockState(anchor)
    end)

    local fontLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -14)
    fontLabel:SetText("Font")

    local fontDropdown = CreateFrame("Frame", "ChatInYoFaceFontDropdown", panel, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -6)

    local fontOptions = {
        { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
        { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
        { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
        { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
    }

    local function SetFont(path)
        ChatInYoFaceDB.font = path
        RefreshFonts(messageFrame)
        LayoutLines(messageFrame)
    end

    UIDropDownMenu_Initialize(fontDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, item in ipairs(fontOptions) do
            info.text = item.name
            info.func = function()
                UIDropDownMenu_SetSelectedValue(fontDropdown, item.path)
                SetFont(item.path)
            end
            info.value = item.path
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(fontDropdown, 160)

    local sizeSlider = CreateFrame("Slider", "ChatInYoFaceSizeSlider", panel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 16, -24)
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

    local channelsLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    channelsLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", -16, -18)
    channelsLabel:SetText("Chat Channels")

    local channelList = {
        { key = "CHAT_MSG_SAY", label = "Say" },
        { key = "CHAT_MSG_YELL", label = "Yell" },
        { key = "CHAT_MSG_WHISPER", label = "Whisper" },
        { key = "CHAT_MSG_WHISPER_INFORM", label = "Whisper (Outgoing)" },
        { key = "CHAT_MSG_PARTY", label = "Party" },
        { key = "CHAT_MSG_PARTY_LEADER", label = "Party Leader" },
        { key = "CHAT_MSG_RAID", label = "Raid" },
        { key = "CHAT_MSG_RAID_LEADER", label = "Raid Leader" },
        { key = "CHAT_MSG_RAID_WARNING", label = "Raid Warning" },
        { key = "CHAT_MSG_GUILD", label = "Guild" },
        { key = "CHAT_MSG_OFFICER", label = "Officer" },
        { key = "CHAT_MSG_CHANNEL", label = "Channels" },
        { key = "CHAT_MSG_INSTANCE_CHAT", label = "Instance" },
        { key = "CHAT_MSG_INSTANCE_CHAT_LEADER", label = "Instance Leader" },
    }

    local prev = channelsLabel
    local channelChecks = {}
    for i, entry in ipairs(channelList) do
        local check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
        check.Text:SetText(entry.label)
        check:SetScript("OnClick", function(self)
            ChatInYoFaceDB.channels[entry.key] = self:GetChecked() and true or false
        end)
        channelChecks[entry.key] = check
        prev = check
    end

    panel.refresh = function()
        lock:SetChecked(ChatInYoFaceDB.locked)
        UIDropDownMenu_SetSelectedValue(fontDropdown, ChatInYoFaceDB.font)
        UIDropDownMenu_SetText(fontDropdown, (function()
            for _, item in ipairs(fontOptions) do
                if item.path == ChatInYoFaceDB.font then
                    return item.name
                end
            end
            return ChatInYoFaceDB.font
        end)())
        sizeSlider:SetValue(ChatInYoFaceDB.size)

        for _, entry in ipairs(channelList) do
            local check = channelChecks[entry.key]
            if check then
                check:SetChecked(ChatInYoFaceDB.channels[entry.key] ~= false)
            end
        end
    end

    panel:SetScript("OnShow", panel.refresh)

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
        else
            print("ChatInYoFace commands:")
            print("/cif lock - lock anchor")
            print("/cif unlock - unlock anchor")
            print("/cif font <path> - set font path")
            print("/cif size <8-64> - set font size")
            print("/cif lines <1-20> - number of lines")
            print("/cif time <1-30> - seconds on screen")
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
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
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

    local anchor = CreateAnchor()
    anchor:ClearAllPoints()
    anchor:SetPoint(ChatInYoFaceDB.anchor.point, UIParent, ChatInYoFaceDB.anchor.relativePoint, ChatInYoFaceDB.anchor.x, ChatInYoFaceDB.anchor.y)

    local messageFrame = CreateMessageFrame(anchor)
    SetupSlashCommands(anchor, messageFrame)
    ApplyLockState(anchor)

    CreateOptionsPanel(anchor, messageFrame)

    self:SetScript("OnUpdate", function(_, elapsed)
        UpdateFade(messageFrame)
    end)

    RegisterChatEvents(self)
    self:SetScript("OnEvent", function(_, chatEvent, ...)
        HandleChatEvent(messageFrame, chatEvent, ...)
    end)
end)
