-- BTD Macro v14.2 (3 раздельные училки: баланс / цена улучшения / цена постройки; макрос бьёт сразу по цене действия)
-- Изменения относительно v8:
--  * скип волны при воспроизведении через firesignal/getconnections (у сигнала нет :Fire())
--  * запись: place пишется сразу (порядок сохраняется), entity_id дописывается позже; у всех действий есть время t
--  * воспроизведение: entity_id ждётся синхронно, тайминги по t (старые макросы без t идут по задержкам)
--  * маппинг старый->новый entity_id строится на лету (работает, если сервер переиспользует id после продажи)
--  * десериализатор прерывается на неизвестном теге вместо чтения мусора
--  * хук игнорирует собственные вызовы (checkcaller)
--  * защита от двойной загрузки, очистка имени файла, один колбэк add_tower
--  * DEBUG: один раз печатает новые wire id (клиент->сервер) и новые kind (сервер->клиент)
-- НЕ ПРОВЕРЕНО В ИГРЕ: wire id скипа и признак нехватки денег неизвестны, см. комментарии ниже.

local genv = (getgenv and getgenv()) or _G
if genv.BTD_MACRO_JOB == game.JobId then
    dwarn("[BTD] уже загружен в этом сервере")
    return
end
genv.BTD_MACRO_JOB = game.JobId

-- ══════════════════════════════
--     КЛЮЧ ДОСТУПА
-- ══════════════════════════════
-- Честно: это переключатель вкладок внутри твоего же файла, а не защита кода. Любой, у кого
-- есть сам файл, может открыть его текстом и прочитать или вырезать эту проверку. Она только
-- разделяет роли между теми, кому ты сам дал файл, не мешает никому читать исходник.
local ACCESS_KEYS = {
    ["333zoop"] = "owner",   -- создатель: доступ ко вкладке wire id
    ["platina"] = "friend",  -- друг: без вкладки wire id
}
local KEY_FILE = "BTD_Macros/key.txt"
local ACCESS_LEVEL = nil

do
    pcall(function()
        if not isfolder("BTD_Macros") then makefolder("BTD_Macros") end
    end)
    local ok, saved = pcall(readfile, KEY_FILE)
    if ok and saved and ACCESS_KEYS[saved] then
        ACCESS_LEVEL = ACCESS_KEYS[saved]
    end
end

if not ACCESS_LEVEL then
    local sg0 = Instance.new("ScreenGui")
    sg0.Name = "BTDMacroKey"
    sg0.ResetOnSpawn = false
    sg0.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 260, 0, 130)
    box.Position = UDim2.new(0.5, -130, 0.5, -65)
    box.BackgroundColor3 = Color3.fromRGB(19, 21, 36)
    box.BorderSizePixel = 0
    box.Parent = sg0
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.Text = "⚔ BTD Macro — ключ доступа"
    title.Size = UDim2.new(1, -20, 0, 24)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(236, 238, 250)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = box

    local input = Instance.new("TextBox")
    input.Size = UDim2.new(1, -20, 0, 34)
    input.Position = UDim2.new(0, 10, 0, 44)
    input.BackgroundColor3 = Color3.fromRGB(32, 35, 58)
    input.TextColor3 = Color3.fromRGB(236, 238, 250)
    input.PlaceholderText = "ключ"
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.Code
    input.TextSize = 13
    input.BorderSizePixel = 0
    input.Text = ""
    input.Parent = box
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 8)

    local msg = Instance.new("TextLabel")
    msg.Text = ""
    msg.Size = UDim2.new(1, -20, 0, 16)
    msg.Position = UDim2.new(0, 10, 0, 82)
    msg.BackgroundTransparency = 1
    msg.Font = Enum.Font.Gotham
    msg.TextSize = 10
    msg.TextColor3 = Color3.fromRGB(244, 92, 112)
    msg.TextXAlignment = Enum.TextXAlignment.Left
    msg.Parent = box

    local okBtn = Instance.new("TextButton")
    okBtn.Text = "Войти"
    okBtn.Size = UDim2.new(1, -20, 0, 28)
    okBtn.Position = UDim2.new(0, 10, 0, 98)
    okBtn.BackgroundColor3 = Color3.fromRGB(139, 108, 255)
    okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    okBtn.Font = Enum.Font.GothamBold
    okBtn.TextSize = 12
    okBtn.BorderSizePixel = 0
    okBtn.Parent = box
    Instance.new("UICorner", okBtn).CornerRadius = UDim.new(0, 8)

    local function tryKey()
        local k = input.Text
        local lvl = ACCESS_KEYS[k]
        if lvl then
            ACCESS_LEVEL = lvl
            pcall(writefile, KEY_FILE, k)
            sg0:Destroy()
        else
            msg.Text = "Неверный ключ"
        end
    end
    okBtn.MouseButton1Click:Connect(tryKey)
    input.FocusLost:Connect(function(enter) if enter then tryKey() end end)

    while not ACCESS_LEVEL do task.wait(0.2) end
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local RS = game:GetService("ReplicatedStorage")
local NetserEvent = RS:WaitForChild("NetserEvent")
local Remotes = require(RS.Modules.RemoteEvents)

local DEBUG = true -- печатать новые wire id и kind один раз

-- ══════════════════════════════
--     ПАПКА МАКРОСОВ
-- ══════════════════════════════
local FOLDER = "BTD_Macros"
pcall(function()
    if not isfolder(FOLDER) then makefolder(FOLDER) end
end)

-- ══════════════════════════════
--     ЖУРНАЛ (консоль + файл + буфер обмена)
-- ══════════════════════════════
local LOG_FILE = FOLDER .. "/log.txt"
local logLines = {}
local flushPending = false

local function flushLog()
    pcall(writefile, LOG_FILE, table.concat(logLines, "\n"))
end

local function pushLog(line)
    logLines[#logLines + 1] = os.date("%H:%M:%S") .. " " .. line
    if #logLines > 400 then table.remove(logLines, 1) end
    if not flushPending then
        flushPending = true
        task.delay(3, function()
            flushPending = false
            flushLog()
        end)
    end
end

local function dlog(msg)
    pushLog(msg)
    print(msg)
end

local function dwarn(msg)
    pushLog("WARN " .. msg)
    warn(msg)
end

-- ══════════════════════════════
--     ОБЛАЧНАЯ ПАПКА (GitHub): wire id, записи режимов/скорости/рестарта, макросы
-- ══════════════════════════════
-- CLOUD_CONFIG_URL — ссылка на GitHub API contents твоей папки с файлами скрипта, например:
--   https://api.github.com/repos/ТВОЙ_ЛОГИН/ТВОЙ_РЕПО/contents/BTD_Macros?ref=main
-- Эта папка в репозитории — просто копия содержимого твоей локальной BTD_Macros: те же
-- wire_map.json, routines.json и файлы макросов. Скрипт читает её через GitHub API
-- (только GET, сюда он ничего не пишет и твой репозиторий не трогает) и раскладывает файлы
-- по локальной папке BTD_Macros того, кто запустил скрипт.
-- Пустая ссылка — вся эта часть просто не выполняется, работает только локальная папка.
local CLOUD_CONFIG_URL = "" -- например: "https://api.github.com/repos/USER/REPO/contents/BTD_Macros?ref=main"
local cloudRoutinesRaw = nil  -- содержимое облачного routines.json; разбирается позже, когда готова таблица routines

do
    if CLOUD_CONFIG_URL ~= "" then
        local function cloudGet(url)
            local getter = (http and http.request) or (syn and syn.request) or http_request or request
            local ok, res
            if getter then
                ok, res = pcall(function()
                    local r = getter({ Url = url, Method = "GET", Headers = { ["User-Agent"] = "Roblox" } })
                    return type(r) == "table" and r.Body or r
                end)
            else
                ok, res = pcall(function() return game:HttpGet(url) end)
            end
            if ok and type(res) == "string" and #res > 0 then return res end
            return nil
        end

        local listRaw = cloudGet(CLOUD_CONFIG_URL)
        local okList, list = false, nil
        if listRaw then
            okList, list = pcall(function() return HttpService:JSONDecode(listRaw) end)
        end
        if not (okList and type(list) == "table") then
            dwarn("[CLOUD] папка недоступна или ссылка настроена неверно")
        else
            -- эти файлы из облака не трогаем: настройки и ключ — личные для каждого
            local RESERVED = { ["settings.json"] = true, ["key.txt"] = true, ["uuid_map.json"] = true, ["log.txt"] = true }
            local got = {}
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry.type == "file" and type(entry.name) == "string"
                    and entry.name:match("%.json$") and not RESERVED[entry.name] and entry.download_url then
                    local content = cloudGet(entry.download_url)
                    if content then
                        if entry.name == "wire_map.json" then
                            pcall(writefile, FOLDER .. "/wire_map.json", content)
                            got[#got + 1] = entry.name
                        elseif entry.name == "routines.json" then
                            cloudRoutinesRaw = content
                            got[#got + 1] = entry.name
                        else
                            -- файл макроса: сохраняем, только если такого ещё нет локально —
                            -- свои записанные макросы на этом экзекьюторе не трогаем
                            local path = FOLDER .. "/" .. entry.name
                            local existsOk, exists = pcall(isfile, path)
                            if not (existsOk and exists) then
                                pcall(writefile, path, content)
                                got[#got + 1] = entry.name
                            end
                        end
                    end
                end
            end
            if #got > 0 then
                dlog("[CLOUD] из GitHub получено: " .. table.concat(got, ", "))
            end
        end
    end
end

-- ══════════════════════════════
--     UUID MAP
-- ══════════════════════════════
local uuidMap = {}
local nameMap = {}

local function loadUUIDs()
    local ok, raw = pcall(readfile, FOLDER .. "/uuid_map.json")
    if ok and raw and #raw > 1 then
        pcall(function()
            local parsed = HttpService:JSONDecode(raw)
            for name, uuid in pairs(parsed) do
                uuidMap[name] = uuid
                nameMap[uuid] = name
            end
        end)
    end
end

local function saveUUIDs()
    pcall(writefile, FOLDER .. "/uuid_map.json", HttpService:JSONEncode(uuidMap))
end

loadUUIDs()
do
    local c = 0
    for _ in pairs(uuidMap) do c += 1 end
    dlog("[UUID] Загружено башен: " .. c)
end

-- ══════════════════════════════
--     СЕРИАЛИЗАТОР
-- ══════════════════════════════
local function serialize(wireId, ...)
    local args = table.pack(...)
    local data = buffer.create(256)
    local cursor = 0

    local function alloc(n)
        while cursor + n > buffer.len(data) do
            local nb = buffer.create(buffer.len(data) * 2)
            buffer.copy(nb, 0, data)
            data = nb
        end
    end

    local function writeValue(v)
        local t = typeof(v)
        if t == "number" then
            alloc(9)
            buffer.writeu8(data, cursor, 1)
            buffer.writef64(data, cursor + 1, v)
            cursor += 9
        elseif t == "string" then
            local len = #v
            alloc(len + 5)
            buffer.writeu8(data, cursor, 2)
            buffer.writeu32(data, cursor + 1, len)
            buffer.writestring(data, cursor + 5, v)
            cursor += len + 5
        elseif t == "Vector3" then
            alloc(13)
            buffer.writeu8(data, cursor, 3)
            buffer.writef32(data, cursor + 1, v.X)
            buffer.writef32(data, cursor + 5, v.Y)
            buffer.writef32(data, cursor + 9, v.Z)
            cursor += 13
        elseif t == "boolean" then
            alloc(2)
            buffer.writeu8(data, cursor, 12)
            buffer.writeu8(data, cursor + 1, v and 1 or 0)
            cursor += 2
        elseif v == nil then
            alloc(1)
            buffer.writeu8(data, cursor, 6)
            cursor += 1
        end
    end

    alloc(3)
    buffer.writeu16(data, cursor, wireId)
    buffer.writeu8(data, cursor + 2, args.n)
    cursor += 3
    for i = 1, args.n do writeValue(args[i]) end

    local result = buffer.create(cursor)
    buffer.copy(result, 0, data, 0, cursor)
    return result
end

local function sendToServer(wireId, ...)
    local data = serialize(wireId, ...)
    NetserEvent:FireServer({ data = data, references = {} })
end

-- ══════════════════════════════
--     СОСТОЯНИЕ
-- ══════════════════════════════
local recording      = false
local playing        = false
local recActions     = {}
local recStart       = 0
local pendingPlaces  = 0
local DELAY_PLACE    = 0.8
local DELAY_UPGRADE  = 0.4
local DELAY_WAVE     = 0.2
local MIN_GAP        = 0.05 -- минимальный зазор между действиями при воспроизведении по t
local ENTITY_TIMEOUT = 3
local waveCounter    = 0

-- facade_id -> entity_id (присваивает сервер); общий для записи и воспроизведения
local facadeToEntity = {}
local knownEntities = {}      -- entity_id, которые сервер выдал в этой сессии
local placeWireByFacade = {}  -- facade_id -> wire id пакета, которым башню поставили

-- ══════════════════════════════
--     WIRE ID: АВТООПРЕДЕЛЕНИЕ
-- ══════════════════════════════
-- place        : по сигнатуре аргументов (uuid, Vector3, число, строка); подтверждается ответом add_tower
-- skip         : по корреляции с кликом на кнопку скипа (два одинаковых наблюдения)
-- upgrade, sell: кнопки "Учить" в GUI, одно действие в игре за раз
-- Начальные 31/35/17 взяты из v8 и считаются предположением (знак "?"), пока не подтверждены (знак "✓").
-- Подтверждённые id сохраняются в wire_map.json вместе с game.PlaceVersion;
-- после обновления игры файл игнорируется, id определяются заново.
local WIRE_ROLES = { "place", "upgrade", "sell", "skip" }
local WIRE_FILE = FOLDER .. "/wire_map.json"
local wire   = { place = 31, upgrade = 35, sell = 17, skip = nil }
local wireOk = { place = false, upgrade = false, sell = false, skip = false }
local skipArgc = nil
local placeVersion = 0
pcall(function() placeVersion = game.PlaceVersion end)

local setStatus = function() end   -- переопределяется в блоке GUI
local onWireChanged = function() end

local function saveWire()
    local ids = {}
    for _, role in ipairs(WIRE_ROLES) do
        if wireOk[role] and wire[role] then ids[role] = wire[role] end
    end
    pcall(writefile, WIRE_FILE, HttpService:JSONEncode({
        placeVersion = placeVersion, ids = ids, skipArgc = skipArgc,
    }))
end

do
    local ok, raw = pcall(readfile, WIRE_FILE)
    if ok and raw and #raw > 1 then
        local ok2, parsed = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok2 and type(parsed) == "table" and type(parsed.ids) == "table" then
            if parsed.placeVersion == placeVersion then
                for _, role in ipairs(WIRE_ROLES) do
                    local id = parsed.ids[role]
                    if type(id) == "number" then
                        wire[role] = id
                        wireOk[role] = true
                    end
                end
                if type(parsed.skipArgc) == "number" then skipArgc = parsed.skipArgc end
                dlog("[WIRE] загружено из файла (версия игры совпадает)")
            else
                dwarn("[WIRE] версия игры изменилась, сохранённые wire id сброшены")
            end
        end
    end
end

local function assignWire(role, id, confirmed)
    -- неподтверждённое предположение с тем же id у другой роли заведомо неверно
    for _, other in ipairs(WIRE_ROLES) do
        if other ~= role and wire[other] == id and not wireOk[other] then
            wire[other] = nil
        end
    end
    local changed = wire[role] ~= id or (confirmed and not wireOk[role])
    wire[role] = id
    if confirmed then
        wireOk[role] = true
    elseif changed then
        wireOk[role] = false
    end
    if changed then
        if confirmed then saveWire() end
        onWireChanged()
    end
end

-- последние 5 секунд исходящего трафика (для корреляции и фильтра шума)
local recentTraffic = {}
local function noteTraffic(wireId, argc)
    local now = os.clock()
    local fresh = {}
    for _, e in ipairs(recentTraffic) do
        if now - e.t <= 5 then fresh[#fresh + 1] = e end
    end
    fresh[#fresh + 1] = { t = now, id = wireId, argc = argc }
    recentTraffic = fresh
end

-- режим обучения: первый новый пакет с числом (entity_id) первым аргументом
local learning = nil
local function startLearn(role)
    local now = os.clock()
    local noise = {}
    for _, e in ipairs(recentTraffic) do
        if now - e.t <= 3 then noise[e.id] = true end
    end
    local mine = { role = role, noise = noise }
    learning = mine
    task.delay(20, function()
        if learning == mine then
            learning = nil
            setStatus("✗ Обучение '" .. role .. "': время вышло", Color3.fromRGB(255, 200, 80))
        end
    end)
end

local function tryLearn(event)
    if not learning then return false end
    local id = event.wireId
    if learning.noise[id] then return false end
    local first = event.args[1]
    if type(first) ~= "number" then return false end
    if next(knownEntities) ~= nil and not knownEntities[first] then return false end
    for _, other in ipairs(WIRE_ROLES) do
        if other ~= learning.role and wireOk[other] and wire[other] == id then return false end
    end
    local role = learning.role
    learning = nil
    assignWire(role, id, true)
    dlog("[WIRE] " .. role .. " = " .. id .. " (аргументов: " .. tostring(event.argc) .. ")")
    setStatus("✓ wire " .. role .. " = " .. id .. ", аргументов: " .. tostring(event.argc),
        Color3.fromRGB(120, 255, 140))
    return true
end

-- скип: пакет, ушедший вокруг клика на кнопку, если он единственный неизвестный
local skipVotes = {}
local function onSkipClicked()
    local tc = os.clock()
    task.spawn(function()
        task.wait(0.45)
        local cand, count = {}, 0
        for _, e in ipairs(recentTraffic) do
            if e.t >= tc - 0.15 and e.t <= tc + 0.45
                and type(e.id) == "number"
                and e.id ~= wire.place and e.id ~= wire.upgrade and e.id ~= wire.sell then
                if cand[e.id] == nil then
                    cand[e.id] = e.argc or 0
                    count += 1
                end
            end
        end
        if count ~= 1 then return end
        local id, argc = next(cand)
        skipVotes[id] = (skipVotes[id] or 0) + 1
        if skipVotes[id] >= 2 and not (wireOk.skip and wire.skip == id) then
            skipArgc = argc
            assignWire("skip", id, true)
            dlog("[WIRE] skip = " .. id .. " (аргументов: " .. argc .. ")")
        end
    end)
end

local warnedUnconfirmed = {}
local function warnIfUnconfirmed(role)
    if wire[role] and not wireOk[role] and not warnedUnconfirmed[role] then
        warnedUnconfirmed[role] = true
        dwarn("[WIRE] " .. role .. "=" .. wire[role] .. " не подтверждён; если действие не срабатывает, нажми 'Учить'")
    end
end

-- ══════════════════════════════
--     АВТО-ЦИКЛ: НАСТРОЙКИ, ЗАПИСЬ И ВОСПРОИЗВЕДЕНИЕ ПАКЕТОВ (СТАРТ / РЕСТАРТ)
-- ══════════════════════════════
-- Как игра выбирает режим и перезапускает матч, неизвестно, поэтому эти два действия записываются
-- руками: нажимаешь "Записать", делаешь действие в игре, скрипт сохраняет все ушедшие пакеты
-- (Netser, другие RemoteEvent/RemoteFunction, ProximityPrompt) и потом повторяет их.
-- Пакеты с Instance или таблицами в аргументах не воспроизводятся (помечаются bad).
-- Записи привязаны к PlaceId и game.PlaceVersion: после обновления игры их надо записать заново.
local SETTINGS_FILE = FOLDER .. "/settings.json"
local ROUTINES_FILE = FOLDER .. "/routines.json"
local SETTING_KEYS = { "autoLoop", "autoMacro", "restartDelay", "startDelay", "tpReload", "loaderFile", "autoDiff", "modeName", "autoSpeed", "speedName", "speedDelay", "moneyPath", "moneyKind", "upgradeCostPath", "placeCostPath" }
local settings = {
    autoLoop     = false,
    autoMacro    = nil,
    restartDelay = 2.0,
    startDelay   = 5.0,
    tpReload     = false,
    loaderFile   = "BTD_Macro.lua",
    autoDiff     = false,
    modeName     = "easy",
    autoSpeed    = false,
    speedName    = "x2",
    speedDelay   = 2.0,
    moneyPath    = "",      -- путь к балансу через game:FindFirstChild по частям, напр. Players.Username.PlayerGui.Main.Cash.Amount
    moneyKind    = "text",  -- "text" = разобрать Text ("$1.25K"), "number" = читать .Value
    upgradeCostPath = "",   -- путь к метке с ценой улучшения (как она мелькает при выборе апгрейда)
    placeCostPath   = "",   -- путь к метке с ценой постройки (как она видна в магазине башен)
}
-- скорости для записи: у каждой своя запись routines["speed_<id>"]. Список можно править под игру
local SPEEDS = {
    { id = "x1", label = "x1" },
    { id = "x2", label = "x2" },
    { id = "x3", label = "x3" },
}
local function speedLabel(id)
    for _, m in ipairs(SPEEDS) do
        if m.id == id then return m.label end
    end
    return tostring(id)
end
-- режимы для авто-выбора; запись каждого хранится в routines["mode_<id>"]
local MODES = {
    { id = "easy",     label = "Easy" },
    { id = "medium",   label = "Medium" },
    { id = "hard",     label = "Hard" },
    { id = "extreme",  label = "Extreme" },
    { id = "endless",  label = "Endless" },
    { id = "bossrush", label = "Boss Rush" },
}
local function modeLabel(id)
    for _, m in ipairs(MODES) do
        if m.id == id then return m.label end
    end
    return tostring(id)
end
local routines = {}
local playRun = 0
local capture = nil
local onAutoChanged = function() end
-- состояние раунда из серверных событий (set_round_state / set_intermission_timer)
local roundState, intermissionTimer = nil, nil
local learnPlaceUntil = 0   -- до этого времени следующий place-пакет подтверждает wire id
local onStateChanged = function() end

local function loadJsonFile(path)
    local ok, raw = pcall(readfile, path)
    if not ok or type(raw) ~= "string" or #raw < 2 then return nil end
    local ok2, parsed = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok2 and type(parsed) == "table" then return parsed end
    return nil
end

do
    local st = loadJsonFile(SETTINGS_FILE)
    if st then
        for _, k in ipairs(SETTING_KEYS) do
            if st[k] ~= nil then settings[k] = st[k] end
        end
    end
    if type(settings.restartDelay) ~= "number" then settings.restartDelay = 2.0 end
    if type(settings.startDelay) ~= "number" then settings.startDelay = 5.0 end
    if type(settings.loaderFile) ~= "string" then settings.loaderFile = "BTD_Macro.lua" end
    local rt = loadJsonFile(ROUTINES_FILE)
    if rt then routines = rt end

    -- облачные записи режимов/скорости/рестарта дополняют локальные, не затирая то,
    -- что уже записано своими руками на этом экзекьюторе
    if cloudRoutinesRaw then
        local ok2, cloudRoutines = pcall(function() return HttpService:JSONDecode(cloudRoutinesRaw) end)
        if ok2 and type(cloudRoutines) == "table" then
            local added = 0
            for key, rec in pairs(cloudRoutines) do
                if routines[key] == nil and type(rec) == "table" then
                    routines[key] = rec
                    added += 1
                end
            end
            if added > 0 then
                pcall(writefile, ROUTINES_FILE, HttpService:JSONEncode(routines))
                dlog("[CLOUD] добавлено записей из routines.json (GitHub): " .. added)
            end
        end
    end
end

local function saveSettings()
    pcall(writefile, SETTINGS_FILE, HttpService:JSONEncode(settings))
end

local function saveRoutines()
    pcall(writefile, ROUTINES_FILE, HttpService:JSONEncode(routines))
end

-- значения аргументов <-> JSON
local function encodeArgs(getArg, n)
    local out, bad = {}, false
    for i = 1, n do
        local v = getArg(i)
        local t = typeof(v)
        if t == "number" then
            if v ~= v or v == math.huge or v == -math.huge then
                bad = true
                out[i] = { __nil = true }
            else
                out[i] = v
            end
        elseif t == "string" or t == "boolean" then
            out[i] = v
        elseif t == "Vector3" then
            out[i] = { __v3 = { v.X, v.Y, v.Z } }
        elseif t == "nil" then
            out[i] = { __nil = true }
        else
            bad = true
            out[i] = { __nil = true }
        end
    end
    return out, bad
end

local function decodeValue(v)
    if type(v) == "table" then
        if v.__v3 then return Vector3.new(v.__v3[1], v.__v3[2], v.__v3[3]) end
        return nil
    end
    return v
end

local function brief(v)
    local str = tostring(v)
    if #str > 40 then str = str:sub(1, 37) .. "..." end
    return str
end

local function appendCapture(pkt, label)
    local now = os.clock()
    if capture.pending then
        capture.pending = false
        routines[capture.name] = { placeId = game.PlaceId, version = placeVersion, packets = {} }
    end
    pkt.dt = capture.last and (now - capture.last) or 0
    capture.last = now
    local list = routines[capture.name].packets
    list[#list + 1] = pkt
    if pkt.bad then capture.bad += 1 end
    saveRoutines() -- сохраняем на лету: при телепорте скрипт может не успеть дожить до "стоп"
    dlog("[CAP:" .. capture.name .. "] #" .. #list .. " " .. label
        .. (pkt.bad and "  (НЕ воспроизводится)" or ""))
    onAutoChanged()
end

local function captureNet(event)
    if not capture or capture.noise[event.wireId] then return end
    local n = event.argc or #event.args
    local args, bad = encodeArgs(function(i) return event.args[i] end, n)
    local d = {}
    for i = 1, n do d[i] = brief(event.args[i]) end
    appendCapture({ kind = "net", wire = event.wireId, n = n, args = args, bad = bad or nil },
        "net wire=" .. event.wireId .. " args: " .. table.concat(d, ", "))
end

local function captureRemote(path, method, pack)
    if not capture or capture.noise["R:" .. path] then return end
    local args, bad = encodeArgs(function(i) return pack[i] end, pack.n)
    local d = {}
    for i = 1, pack.n do d[i] = brief(pack[i]) end
    appendCapture({ kind = "remote", path = path, method = method, n = pack.n, args = args, bad = bad or nil },
        method .. " " .. path .. " args: " .. table.concat(d, ", "))
end

local function capturePrompt(prompt)
    if not capture then return end
    local path = prompt:GetFullName()
    appendCapture({ kind = "prompt", path = path, n = 0, args = {} },
        "prompt " .. path .. " (" .. tostring(prompt.ActionText) .. ")")
end

local function startCapture(name)
    -- пакеты, которые шли регулярно в последние 5 секунд, считаются фоновым шумом
    local counts, noise = {}, {}
    for _, e in ipairs(recentTraffic) do counts[e.id] = (counts[e.id] or 0) + 1 end
    for id, c in pairs(counts) do
        if c >= 2 then noise[id] = true end
    end
    capture = { name = name, last = nil, noise = noise, bad = 0, pending = true }
    onAutoChanged()
end

local function stopCapture()
    local c = capture
    capture = nil
    if c then
        local r = routines[c.name]
        local cnt = (r and not c.pending and r.packets) and #r.packets or 0
        dlog("[CAP:" .. c.name .. "] запись завершена, пакетов: " .. cnt .. ", не воспроизводится: " .. c.bad)
    end
    onAutoChanged()
end

local function resolvePath(path)
    local cur = game
    for part in tostring(path):gmatch("[^%.]+") do
        cur = cur and cur:FindFirstChild(part)
        if not cur then return nil end
    end
    return cur
end

-- ══════════════════════════════
--     БАЛАНС (для воспроизведения "сразу как хватит денег")
-- ══════════════════════════════
-- "$1.25K" / "1 250" / "2M" и т.п. -> число. Неизвестный формат -> nil, без подмены нулём
local function parseMoneyText(txt)
    if type(txt) ~= "string" then return nil end
    local suf = txt:match("([KkMmBbТтМмКк])%s*$")
    local digits = txt:gsub("[^%d%.,]", ""):gsub(",", "")
    local n = tonumber(digits)
    if not n then return nil end
    if suf then
        suf = suf:upper()
        if suf == "K" or suf == "К" then n *= 1e3
        elseif suf == "M" or suf == "М" then n *= 1e6
        elseif suf == "B" then n *= 1e9
        elseif suf == "T" or suf == "Т" then n *= 1e12
        end
    end
    return n
end

-- Как readBalance, но сам определяет .Value или .Text — для цен (используются только эти две функции)
local function readAt(path)
    if not path or path == "" then return nil end
    local obj = resolvePath(path)
    if not obj then return nil end
    local okV, v = pcall(function() return obj.Value end)
    if okV and type(v) == "number" then return v end
    local okT, t = pcall(function() return obj.Text end)
    if okT then return parseMoneyText(t) end
    return nil
end

local function readUpgradeCost() return readAt(settings.upgradeCostPath) end
local function readPlaceCost() return readAt(settings.placeCostPath) end

-- settings.moneyPath настраивается только во вкладке "Разработчик" (owner).
-- Без пути или при ошибке чтения возвращает nil — воспроизведение тогда идёт по старым таймингам.
local function readBalance()
    if not settings.moneyPath or settings.moneyPath == "" then return nil end
    local obj = resolvePath(settings.moneyPath)
    if not obj then return nil end
    if settings.moneyKind == "number" then
        local ok, v = pcall(function() return obj.Value end)
        if ok and type(v) == "number" then return v end
        return nil
    else
        local ok, v = pcall(function() return obj.Text end)
        if ok then return parseMoneyText(v) end
        return nil
    end
end

local function runRoutine(name, alive)
    alive = alive or function() return true end
    local r = routines[name]
    if not r or type(r.packets) ~= "table" or #r.packets == 0 then
        dwarn("[ROUTINE] '" .. name .. "' не записан")
        return false
    end
    if r.placeId ~= game.PlaceId then
        dwarn("[ROUTINE] '" .. name .. "' записан для другого места")
        return false
    end
    if r.version ~= placeVersion then
        dwarn("[ROUTINE] версия игры изменилась с момента записи '" .. name .. "': запиши заново")
        return false
    end

    local sent, skipped = 0, 0
    for _, pk in ipairs(r.packets) do
        if not alive() then return false end
        if pk.dt and pk.dt > 0 then task.wait(math.min(pk.dt, 5)) end
        if not alive() then return false end

        if pk.bad then
            skipped += 1
        else
            local args = {}
            local n = pk.n or 0
            for i = 1, n do args[i] = decodeValue(pk.args[i]) end

            if pk.kind == "net" then
                sendToServer(pk.wire, table.unpack(args, 1, n))
                sent += 1
            elseif pk.kind == "remote" then
                local remote = resolvePath(pk.path)
                if remote then
                    if pk.method == "InvokeServer" then
                        task.spawn(function() pcall(remote.InvokeServer, remote, table.unpack(args, 1, n)) end)
                    else
                        pcall(remote.FireServer, remote, table.unpack(args, 1, n))
                    end
                    sent += 1
                else
                    dwarn("[ROUTINE] не найден remote " .. tostring(pk.path))
                    skipped += 1
                end
            elseif pk.kind == "prompt" then
                local prompt = resolvePath(pk.path)
                if prompt and fireproximityprompt then
                    pcall(fireproximityprompt, prompt)
                    sent += 1
                else
                    dwarn("[ROUTINE] нет prompt " .. tostring(pk.path) .. " или нет fireproximityprompt")
                    skipped += 1
                end
            end
        end
    end
    dlog("[ROUTINE] '" .. name .. "': отправлено " .. sent .. ", пропущено " .. skipped)
    return sent > 0
end

-- другие RemoteEvent/RemoteFunction (не Netser): логируются один раз и попадают в запись
local seenRemotes = {}
local function onOtherRemote(remote, method, ...)
    if typeof(remote) ~= "Instance" then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return end
    local path = remote:GetFullName()
    local pack = table.pack(...)
    if DEBUG and not seenRemotes[path] then
        seenRemotes[path] = true
        dlog("[REMOTE] новый " .. path .. " (" .. method .. "), аргументов: " .. pack.n)
    end
    noteTraffic("R:" .. path, pack.n)
    captureRemote(path, method, pack)
end

game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
    pcall(capturePrompt, prompt)
end)

-- ══════════════════════════════
--     GUI ИГРЫ
-- ══════════════════════════════
local MainGui = PlayerGui:WaitForChild("MainGui")
local Info    = MainGui:WaitForChild("Info")

local NameLabel = nil
for _, v in ipairs(Info:GetDescendants()) do
    if v:IsA("TextLabel") and v.Name == "Label" then
        NameLabel = v
        break
    end
end

local SkipBtn = MainGui
    :WaitForChild("Clipping")
    :WaitForChild("Main")
    :WaitForChild("checkmark")

local warnedSkip = false
local function pressSkip()
    if firesignal then
        local ok = pcall(firesignal, SkipBtn.MouseButton1Click)
        if ok then return true end
    end
    if getconnections then
        local ok, conns = pcall(getconnections, SkipBtn.MouseButton1Click)
        if ok and conns then
            for _, c in ipairs(conns) do
                pcall(function() c:Fire() end)
            end
            return true
        end
    end
    if not warnedSkip then
        warnedSkip = true
        dwarn("[SKIP] нет firesignal/getconnections в этом экзекьюторе; скип не выполнен")
    end
    return false
end

-- ══════════════════════════════
--     ИМЯ БАШНИ
-- ══════════════════════════════
local lastTowerName = nil
if NameLabel then
    NameLabel:GetPropertyChangedSignal("Text"):Connect(function()
        local txt = NameLabel.Text
        if txt and txt ~= "" then lastTowerName = txt end
    end)
end

local function getTowerName()
    if NameLabel then
        local txt = NameLabel.Text
        if txt and txt ~= "" then return txt end
    end
    return lastTowerName
end

-- ══════════════════════════════
--     ДЕСЕРИАЛИЗАТОР
-- ══════════════════════════════
-- Возвращает results, aborted. При неизвестном теге или выходе за границу
-- буфера разбор останавливается; уже разобранные сообщения остаются в results.
local function deserialize(buf, refs)
    local cursor = 0
    local len = buffer.len(buf)
    local references = refs or {}
    local aborted = false

    local function need(n)
        if cursor + n > len then
            aborted = true
            return false
        end
        return true
    end

    local function readValue()
        if not need(1) then return nil end
        local t = buffer.readu8(buf, cursor)
        cursor += 1
        if t == 1 then
            if not need(8) then return nil end
            local v = buffer.readf64(buf, cursor)
            cursor += 8
            return v
        elseif t == 2 then
            if not need(4) then return nil end
            local l = buffer.readu32(buf, cursor)
            cursor += 4
            if not need(l) then return nil end
            local s = buffer.readstring(buf, cursor, l)
            cursor += l
            return s
        elseif t == 3 then
            if not need(12) then return nil end
            local x = buffer.readf32(buf, cursor)
            local y = buffer.readf32(buf, cursor + 4)
            local z = buffer.readf32(buf, cursor + 8)
            cursor += 12
            return Vector3.new(x, y, z)
        elseif t == 6 then
            return nil
        elseif t == 10 then
            if not need(2) then return nil end
            local idx = buffer.readu16(buf, cursor)
            cursor += 2
            return references[idx]
        elseif t == 12 then
            if not need(1) then return nil end
            local v = buffer.readu8(buf, cursor) == 1
            cursor += 1
            return v
        end
        aborted = true
        if DEBUG then dwarn("[SNIFF] неизвестный тег типа: " .. tostring(t)) end
        return nil
    end

    local results = {}
    while cursor < len and not aborted do
        if not need(3) then break end
        local wireId = buffer.readu16(buf, cursor)
        local argCount = buffer.readu8(buf, cursor + 2)
        cursor += 3
        local args = {}
        for i = 1, argCount do
            args[i] = readValue()
            if aborted then break end
        end
        if aborted then break end
        table.insert(results, { wireId = wireId, args = args, argc = argCount })
    end
    return results, aborted
end

-- ══════════════════════════════
--     СЕРВЕР -> КЛИЕНТ (SendUnbufferedEvent)
-- ══════════════════════════════
local seenKinds = {}
local unbufferedCallbacks = Remotes.SendUnbufferedEvent.callbacks
if unbufferedCallbacks then
    table.insert(unbufferedCallbacks, function(data)
        if type(data) ~= "table" then return end

        if DEBUG and data.kind and not seenKinds[data.kind] then
            seenKinds[data.kind] = true
            local parts = {}
            for k, v in pairs(data) do
                parts[#parts + 1] = tostring(k) .. "=" .. typeof(v) .. ":" .. tostring(v)
            end
            dlog("[S->C] новый kind '" .. tostring(data.kind) .. "': " .. table.concat(parts, ", "))
        end

        if data.kind == "set_round_state" then
            roundState = data.round_state
            onStateChanged()
        elseif data.kind == "set_intermission_timer" then
            intermissionTimer = data.timer
            onStateChanged()
        end

        if data.kind == "add_tower" then
            local entityId  = data.entity_id
            local facadeId  = data.spawn_facade_id
            local towerName = data.spawn_kind_name
            local uuid      = data.spawn_item_id

            if facadeId and entityId then
                facadeToEntity[facadeId] = entityId
                knownEntities[entityId] = true
                local w = placeWireByFacade[facadeId]
                if w then
                    placeWireByFacade[facadeId] = nil
                    assignWire("place", w, true)
                end
            end

            if towerName and uuid and not uuidMap[towerName] then
                uuidMap[towerName] = uuid
                nameMap[uuid] = towerName
                saveUUIDs()
                dlog("[UUID] Сохранено: " .. towerName .. " -> " .. uuid)
            end
        end
    end)
    dlog("[OK] SendUnbufferedEvent подключён через callbacks")
else
    dwarn("[WARN] callbacks не найден в SendUnbufferedEvent")
end

-- ══════════════════════════════
--     СНИФФЕР (клиент -> сервер)
-- ══════════════════════════════
local seenWire = {}

local UUID_PATTERN = "^%x+%-%x+%-%x+%-%x+%-%x+$"

local function isPlaceSignature(event)
    local a = event.args
    return type(a[1]) == "string" and a[1]:match(UUID_PATTERN) ~= nil
        and typeof(a[2]) == "Vector3"
        and (a[3] == nil or type(a[3]) == "number")
        and type(a[4]) == "string"
end

local function recordPlace(event)
    local uuid     = event.args[1]
    local pos      = event.args[2]
    local rotation = event.args[3] or 0
    local facade   = event.args[4]

    local name = nameMap[uuid] or getTowerName() or uuid
    local entry = {
        action    = "place",
        tower     = name,
        uuid      = uuid,
        facade_id = facade,
        x = pos.X, y = pos.Y, z = pos.Z,
        rotation  = rotation,
        t         = os.clock() - recStart,
        balance_before = readBalance(),
        price = readPlaceCost(),
    }
    table.insert(recActions, entry)

    pendingPlaces += 1
    task.spawn(function()
        local deadline = os.clock() + ENTITY_TIMEOUT
        while os.clock() < deadline and not facadeToEntity[facade] do
            task.wait(0.05)
        end
        entry.entity_id = facadeToEntity[facade]
        if not entry.entity_id then
            dwarn("[REC] entity_id не получен для " .. tostring(facade))
        end
        pendingPlaces -= 1
    end)
end

local function onClientEvent(event)
    local id = event.wireId
    noteTraffic(id, event.argc or #event.args)
    captureNet(event)

    if DEBUG and not seenWire[id] then
        seenWire[id] = true
        dlog("[C->S] новый wire id " .. id .. ", аргументов: " .. tostring(event.argc))
    end

    -- place определяется по сигнатуре, независимо от записи
    if isPlaceSignature(event) then
        placeWireByFacade[event.args[4]] = id
        if os.clock() < learnPlaceUntil then
            learnPlaceUntil = 0
            assignWire("place", id, true)
            dlog("[WIRE] place = " .. id .. " (выучен хуком, аргументов: " .. tostring(event.argc) .. ")")
            setStatus("✓ wire place = " .. id, Color3.fromRGB(120, 255, 140))
        elseif wire.place ~= id then
            dlog("[WIRE] place по сигнатуре: " .. id .. " (ждём подтверждения add_tower)")
            assignWire("place", id, false)
        end
        if recording then recordPlace(event) end
        return
    end

    if tryLearn(event) then return end
    if not recording then return end

    if wire.upgrade and id == wire.upgrade then
        local entityId = event.args[1]
        if type(entityId) ~= "number" then return end
        table.insert(recActions, {
            action    = "upgrade",
            tower     = getTowerName() or ("entity_" .. entityId),
            entity_id = entityId,
            tier      = event.args[2],
            t         = os.clock() - recStart,
            balance_before = readBalance(),
            price = readUpgradeCost(),
        })
        dlog("[REC] UPGRADE entity_id=" .. entityId .. " tier=" .. tostring(event.args[2]))

    elseif wire.sell and id == wire.sell then
        local entityId = event.args[1]
        if type(entityId) ~= "number" then return end
        table.insert(recActions, {
            action    = "sell",
            entity_id = entityId,
            t         = os.clock() - recStart,
            balance_before = readBalance(),
        })
        dlog("[REC] SELL entity_id=" .. entityId)
    end
end

local oldNamecall
local function namecallHook(self, ...)
    local method = getnamecallmethod()

    if method == "FireServer" and self == NetserEvent
        and not (checkcaller and checkcaller()) then
        local packet = select(1, ...)
        if type(packet) == "table" and packet.data then
            local refs = {}
            if packet.references then
                for _, pair in ipairs(packet.references) do
                    refs[pair[1]] = pair[2]
                end
            end
            local ok, results = pcall(deserialize, packet.data, refs)
            if ok and results then
                for _, event in ipairs(results) do
                    pcall(onClientEvent, event)
                end
            end
        end
    end

    if (method == "FireServer" or method == "InvokeServer") and self ~= NetserEvent
        and not (checkcaller and checkcaller()) then
        pcall(onOtherRemote, self, method, ...)
    end

    return oldNamecall(self, ...)
end
oldNamecall = hookmetamethod(game, "__namecall",
    newcclosure and newcclosure(namecallHook) or namecallHook)

-- ══════════════════════════════
--     СКИП ВОЛНЫ (запись по клику на кнопку)
-- ══════════════════════════════
-- Клик, вызванный самим макросом, при воспроизведении не пишется (recording=false).
-- Wire id скипа неизвестен: если включён DEBUG, после ручного скипа он появится
-- в консоли как "[C->S] новый wire id ...".
SkipBtn.MouseButton1Click:Connect(function()
    onSkipClicked()
    if recording then
        waveCounter += 1
        table.insert(recActions, {
            action = "skip",
            wave   = waveCounter,
            t      = os.clock() - recStart,
        })
        dlog("[REC] SKIP WAVE " .. waveCounter)
    end
end)

-- ══════════════════════════════
--     ВОСПРОИЗВЕДЕНИЕ
-- ══════════════════════════════
local function resolveUUID(action)
    local uuid = action.uuid
    if type(uuid) == "string" and uuid:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
        return uuid
    end
    return uuidMap[action.tower]
end

local function playMacro(actions, onStatus, onDone)
    if playing or recording then return end
    playing = true
    playRun += 1
    local myRun = playRun
    local function active() return playing and playRun == myRun end

    task.spawn(function()
        local oldToNew = {} -- entity_id из записи -> entity_id в этом матче
        local failed = 0
        local replayStart = os.clock()
        local byBalance = readBalance() ~= nil
        dlog("[REPLAY] ожидание по " .. (byBalance and "балансу (путь задан)" or "записанным таймингам"))

        for i, action in ipairs(actions) do
            if not active() then break end
            onStatus(i .. "/" .. #actions)

            -- порог: если записана прямая цена действия (price) — ждём именно её, это надёжнее;
            -- иначе, если записан баланс до действия (balance_before) — ждём его как раньше
            local threshold = action.price or action.balance_before
            if byBalance and threshold then
                -- не ждём записанный таймкод: действие выполняется, как только денег хватает.
                -- запас сверх записанного времени — на случай, если чтение баланса собьётся
                local cap = replayStart + (action.t or 0) + 10
                local ok = false
                while active() and os.clock() < cap do
                    local bal = readBalance()
                    if bal and bal >= threshold then ok = true break end
                    task.wait(0.1)
                end
                if not active() then break end
                if not ok then
                    dwarn("[REPLAY] баланс не дорос до " .. threshold .. " за разумное время, выполняю как есть")
                end
            elseif action.t then
                local due = replayStart + action.t
                while active() and os.clock() < due do task.wait(0.05) end
                if not active() then break end
            end

            local kind = action.action

            if kind == "place" then
                local uuid = resolveUUID(action)
                if not uuid or not action.x or not action.y or not action.z then
                    dwarn("[SKIP] нет UUID или координат: " .. tostring(action.tower))
                    failed += 1
                    continue
                end

                if not wire.place then
                    dwarn("[REPLAY] wire id place неизвестен: поставь одну башню вручную, он определится сам")
                    failed += 1
                    continue
                end
                warnIfUnconfirmed("place")

                local pos = Vector3.new(action.x, action.y, action.z)
                local newFacade = "{" .. HttpService:GenerateGUID(false) .. "}"
                sendToServer(wire.place, uuid, pos, action.rotation or 0, newFacade)

                local deadline = os.clock() + ENTITY_TIMEOUT
                while active() and os.clock() < deadline and not facadeToEntity[newFacade] do
                    task.wait(0.05)
                end

                local newId = facadeToEntity[newFacade]
                if action.entity_id then
                    oldToNew[action.entity_id] = newId -- nil, если сервер не ответил
                end
                if not newId then
                    dwarn("[REPLAY] нет entity_id после place: " .. tostring(action.tower))
                    failed += 1
                end
                if action.t then task.wait(MIN_GAP) else task.wait(DELAY_PLACE) end

            elseif kind == "upgrade" then
                local newId = oldToNew[action.entity_id]
                if newId and wire.upgrade then
                    warnIfUnconfirmed("upgrade")
                    sendToServer(wire.upgrade, newId, action.tier)
                elseif newId then
                    dwarn("[REPLAY] wire id upgrade неизвестен: нажми 'Учить апгрейд'")
                    failed += 1
                else
                    dwarn("[REPLAY] upgrade: нет соответствия для entity_id=" .. tostring(action.entity_id))
                    failed += 1
                end
                if action.t then task.wait(MIN_GAP) else task.wait(DELAY_UPGRADE) end

            elseif kind == "sell" then
                local newId = oldToNew[action.entity_id]
                if newId and wire.sell then
                    warnIfUnconfirmed("sell")
                    sendToServer(wire.sell, newId)
                    oldToNew[action.entity_id] = nil
                elseif newId then
                    dwarn("[REPLAY] wire id sell неизвестен: нажми 'Учить продажу'")
                    failed += 1
                else
                    dwarn("[REPLAY] sell: нет соответствия для entity_id=" .. tostring(action.entity_id))
                    failed += 1
                end
                if action.t then task.wait(MIN_GAP) else task.wait(DELAY_UPGRADE) end

            elseif kind == "skip" then
                -- по wire id только если он подтверждён и пакет без аргументов; иначе через кнопку
                if wire.skip and wireOk.skip and skipArgc == 0 then
                    sendToServer(wire.skip)
                else
                    pressSkip()
                end
                if action.t then task.wait(MIN_GAP) else task.wait(DELAY_WAVE) end
            end
        end

        local stoppedByUser = not active()
        if playRun == myRun then playing = false end
        if stoppedByUser then
            onStatus("■ Остановлено")
        elseif failed > 0 then
            onStatus("✓ Готово, пропущено действий: " .. failed)
        else
            onStatus("✓ Готово!")
        end
        dlog("[REPLAY] Завершено, пропущено: " .. failed)
        if onDone then onDone() end
    end)
end

-- ══════════════════════════════
--     СПИСОК МАКРОСОВ
-- ══════════════════════════════
-- служебные файлы папки: это не макросы
local RESERVED_JSON = { routines = true, settings = true, wire_map = true, uuid_map = true }

-- макрос = JSON-массив действий, у каждого есть строковое поле action
local function isMacroData(t)
    if type(t) ~= "table" then return false end
    if next(t) == nil then return true end
    if t[1] == nil then return false end
    local n = 0
    for k, v in pairs(t) do
        if type(k) ~= "number" or type(v) ~= "table" or type(v.action) ~= "string" then return false end
        n += 1
    end
    return n == #t
end

local function getMacros()
    local list = {}
    local ok, files = pcall(listfiles, FOLDER)
    if not ok then return list end
    for _, path in ipairs(files) do
        local name = path:match("([^/\\]+)%.json$")
        if name and not RESERVED_JSON[name:lower()] then
            local okr, raw = pcall(readfile, path)
            local okp, data = false, nil
            if okr and raw then okp, data = pcall(function() return HttpService:JSONDecode(raw) end) end
            if okp and isMacroData(data) then
                table.insert(list, { name = name, path = path })
            end
        end
    end
    table.sort(list, function(x, y) return x.name:lower() < y.name:lower() end)
    return list
end

local function sanitizeName(s)
    s = s:gsub("[/\\:%*%?\"<>|]", "_")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-- ══════════════════════════════
--     АВТО-ЦИКЛ
-- ══════════════════════════════
-- Конец матча определяется по тексту на экране (проверено только "Поражение" по скриншоту,
-- остальные слова предположение). Найденный элемент печатается в консоль.
local END_KEYWORDS = { "Поражение", "Победа", "Defeat", "Victory" }

local function cleanText(txt)
    txt = txt:gsub("<[^>]+>", "")
    txt = txt:gsub("[%s%p]", "")
    return txt
end

local function guiShown(obj)
    local cur = obj
    while cur and cur ~= PlayerGui do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function endScreenVisible()
    local own = PlayerGui:FindFirstChild("BTDMacroV9")
    for _, d in ipairs(PlayerGui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and #d.Text <= 60
            and not (own and d:IsDescendantOf(own)) then
            local txt = cleanText(d.Text)
            for _, kw in ipairs(END_KEYWORDS) do
                if txt == kw and d.AbsoluteSize.X > 0 and guiShown(d) then
                    return true, kw, d
                end
            end
        end
    end
    return false
end

local function startAutoMacro()
    local name = settings.autoMacro
    if not name then
        setStatus("Авто: макрос не выбран", Color3.fromRGB(255, 200, 80))
        return false
    end
    local ok, raw = pcall(readfile, FOLDER .. "/" .. name .. ".json")
    if not ok then
        dwarn("[AUTO] файл макроса не найден: " .. tostring(name))
        return false
    end
    local ok2, acts = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 or type(acts) ~= "table" then
        dwarn("[AUTO] ошибка JSON в макросе " .. tostring(name))
        return false
    end
    playing = false
    task.wait(0.2)
    playMacro(acts, function(st)
        setStatus("▶ авто " .. name .. ": " .. st, Color3.fromRGB(255, 200, 80))
    end)
    return true
end

local autoToken = 0

-- «в матче»: сервер прислал TOWER_DEFENSE или уже выдал башни
local function inMatchNow()
    return roundState == "TOWER_DEFENSE" or next(knownEntities) ~= nil
end

-- после конца матча состояние прошлого матча сбрасывается, иначе лобби считается матчем
local speedDone = false

local function resetMatchState()
    roundState = nil
    knownEntities = {}
    speedDone = false
    onStateChanged()
end

-- Следит за экраном конца и применяет записанную скорость один раз за матч.
-- Когда виден экран конца, состояние матча сбрасывается: следующий матч определится заново.
local function startSpeedWatcher()
    task.spawn(function()
        local wasEnd = false
        while PlayerGui:FindFirstChild("BTDMacroV9") do
            task.wait(1)
            local ended = endScreenVisible() and true or false
            if ended and not wasEnd then
                resetMatchState()
            end
            wasEnd = ended

            if settings.autoSpeed and not ended and not speedDone and inMatchNow()
                and not recording and not capture then
                local rn = "speed_" .. tostring(settings.speedName)
                local r = routines[rn]
                if r and type(r.packets) == "table" and #r.packets > 0 and r.placeId == game.PlaceId then
                    speedDone = true
                    setStatus("Авто: скорость " .. speedLabel(settings.speedName) .. " через " .. settings.speedDelay .. " с",
                        Color3.fromRGB(255, 200, 80))
                    task.wait(settings.speedDelay)
                    if settings.autoSpeed and not endScreenVisible() then
                        local ok = runRoutine(rn)
                        dlog("[AUTO] скорость " .. rn .. (ok and " отправлена" or " не отправлена"))
                        setStatus(ok and ("Авто: скорость " .. speedLabel(settings.speedName) .. " включена")
                            or "Авто: скорость не отправлена (см. журнал)",
                            ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 80, 80))
                    end
                end
            end
        end
    end)
end

-- выбор сложности: до 3 попыток, успех = сервер сообщил, что матч начался. Возвращает true/false
local function selectDifficulty(token)
    local YEL, RED = Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 80)
    local function aliveDiff() return settings.autoDiff and token == autoToken end

    local modeRoutine = "mode_" .. tostring(settings.modeName)
    if not routines[modeRoutine] and routines.start then modeRoutine = "start" end
    local modeR = routines[modeRoutine]
    if not (modeR and type(modeR.packets) == "table" and #modeR.packets > 0) then
        setStatus("Авто: для «" .. modeLabel(settings.modeName) .. "» нет записи (вкладка «Запись»)", YEL)
        dwarn("[AUTO] нет записи режима " .. modeRoutine)
        return false
    end
    if modeR.placeId ~= game.PlaceId then
        setStatus("Авто: запись «" .. modeLabel(settings.modeName) .. "» сделана в другом месте", YEL)
        dwarn("[AUTO] запись " .. modeRoutine .. " для PlaceId " .. tostring(modeR.placeId) .. ", сейчас " .. tostring(game.PlaceId))
        return false
    end
    if inMatchNow() then
        dlog("[AUTO] уже идёт матч, выбор сложности пропущен")
        return true
    end

    for attempt = 1, 3 do
        if not aliveDiff() then return false end
        setStatus("Авто: «" .. modeLabel(settings.modeName) .. "» через " .. settings.startDelay .. " с (" .. attempt .. "/3)", YEL)
        task.wait(settings.startDelay)
        if not aliveDiff() then return false end
        if inMatchNow() then return true end
        dlog("[AUTO] отправляю запись " .. modeRoutine .. ", попытка " .. attempt)
        runRoutine(modeRoutine, aliveDiff)
        local t0 = os.clock()
        while aliveDiff() and os.clock() - t0 < 30 do
            if inMatchNow() then
                setStatus("Авто: матч «" .. modeLabel(settings.modeName) .. "» начался", Color3.fromRGB(120, 255, 140))
                return true
            end
            task.wait(0.5)
        end
    end
    if aliveDiff() then
        setStatus("Авто: сложность не выбралась, см. журнал", RED)
    end
    return false
end

local function autoLoop(token)
    local function alive() return settings.autoLoop and token == autoToken end
    local restartR = routines.restart
    dlog("[AUTO] старт: autoDiff=" .. tostring(settings.autoDiff) .. " autoLoop=" .. tostring(settings.autoLoop)
        .. " режим=" .. tostring(settings.modeName) .. " PlaceId=" .. tostring(game.PlaceId)
        .. " roundState=" .. tostring(roundState) .. " в матче=" .. tostring(inMatchNow() and true or false))

    -- 1) авто выбор сложности (не зависит от записи рестарта)
    if settings.autoDiff then selectDifficulty(token) end

    -- 2) авто рестарт: матч -> конец -> рестарт -> макрос
    if not settings.autoLoop or token ~= autoToken then return end
    if not (restartR and restartR.placeId == game.PlaceId) then
        setStatus("Авто: нет записи РЕСТАРТ для этого места (вкладка «Запись»)", Color3.fromRGB(255, 200, 80))
        return
    end
    local first = true
    while alive() do
        if first then
            first = false
            if not endScreenVisible() then
                setStatus("Авто: старт макроса через " .. settings.startDelay .. " с", Color3.fromRGB(255, 200, 80))
                task.wait(settings.startDelay)
                if not alive() then break end
                startAutoMacro()
            end
        end

        local kw, obj
        while alive() do
            local shown, w, o = endScreenVisible()
            if shown then
                kw, obj = w, o
                break
            end
            task.wait(1)
        end
        if not alive() then break end

        dlog("[AUTO] конец матча по тексту '" .. tostring(kw) .. "': " .. obj:GetFullName())
        playing = false
        setStatus("Авто: матч закончен, рестарт через " .. settings.restartDelay .. " с", Color3.fromRGB(255, 200, 80))
        task.wait(settings.restartDelay)

        local restarted = false
        for attempt = 1, 3 do
            if not alive() then break end
            runRoutine("restart", alive)
            local t0 = os.clock()
            while alive() and endScreenVisible() and os.clock() - t0 < 20 do task.wait(0.5) end
            if not endScreenVisible() then
                restarted = true
                break
            end
        end
        if not alive() then break end
        if not restarted then
            setStatus("Авто: рестарт не сработал, цикл остановлен. Вкладка «Запись» → ↻ Перезаписать", Color3.fromRGB(255, 80, 80))
            settings.autoLoop = false
            saveSettings()
            onAutoChanged()
            break
        end

        -- после рестарта игра снова просит выбрать сложность
        if settings.autoDiff then
            resetMatchState()
            selectDifficulty(token)
            if not alive() then break end
        end

        task.wait(settings.startDelay)
        if not alive() then break end
        startAutoMacro()
    end
end

-- перезапуск фонового цикла после смены любого из двух переключателей
local function applyAuto()
    saveSettings()
    autoToken += 1
    if settings.autoLoop or settings.autoDiff then
        local token = autoToken
        task.spawn(function() autoLoop(token) end)
    else
        setStatus("Автоматика выключена", Color3.fromRGB(255, 100, 100))
    end
    onAutoChanged()
end

local function setAuto(on)
    settings.autoLoop = on and true or false
    applyAuto()
end

local function setAutoDiff(on)
    settings.autoDiff = on and true or false
    applyAuto()
end

-- автозагрузка скрипта после телепорта между местами (нужен queue_on_teleport и файл скрипта в workspace)
local function queueReload()
    if not queue_on_teleport then return false end
    local ok = pcall(queue_on_teleport, 'loadstring(readfile("' .. settings.loaderFile .. '"))()')
    return ok
end
if settings.tpReload then queueReload() end
LocalPlayer.OnTeleport:Connect(function()
    if settings.tpReload then queueReload() end
    if capture then stopCapture() end
    flushLog()
end)

-- ══════════════════════════════
--     GUI
-- ══════════════════════════════
-- весь интерфейс в своей функции: у неё свой лимит локальных переменных
local function buildGui()
local UIS = game:GetService("UserInputService")

local C = {
    bg      = Color3.fromRGB(9, 10, 18),
    card    = Color3.fromRGB(19, 21, 36),
    card2   = Color3.fromRGB(32, 35, 58),
    accent  = Color3.fromRGB(139, 108, 255),
    accent2 = Color3.fromRGB(56, 189, 248),
    stroke  = Color3.fromRGB(62, 66, 104),
    text    = Color3.fromRGB(236, 238, 250),
    dim     = Color3.fromRGB(128, 134, 168),
    green   = Color3.fromRGB(52, 211, 153),
    red     = Color3.fromRGB(244, 92, 112),
    yellow  = Color3.fromRGB(251, 191, 36),
}
local function tween(obj, props, t)
    pcall(function()
        game:GetService("TweenService"):Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad), props):Play()
    end)
end
local DARK_ON_GREEN = Color3.fromRGB(6, 28, 20)

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
    return c
end

local function mkLabel(parent, text, pos, size, o)
    o = o or {}
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = pos
    l.Size = size
    l.Text = text
    l.Font = o.bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = o.size or 11
    l.TextColor3 = o.color or C.text
    l.TextXAlignment = o.align or Enum.TextXAlignment.Left
    l.TextYAlignment = o.yalign or Enum.TextYAlignment.Center
    l.TextWrapped = o.wrap or false
    l.Parent = parent
    return l
end

local function mkButton(parent, text, pos, size, color, onClick, o)
    o = o or {}
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.BackgroundColor3 = color or C.card2
    b.BackgroundTransparency = o.flat and 1 or 0
    b.Position = pos
    b.Size = size
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = o.size or 11
    b.TextColor3 = o.textColor or C.text
    b.BorderSizePixel = 0
    b.Parent = parent
    corner(b, o.radius or 9)
    if color == C.accent then
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(C.accent, C.accent2)
        g.Rotation = 20
        g.Parent = b
    end
    if not o.flat then
        local st = Instance.new("UIStroke")
        st.Color = C.stroke
        st.Transparency = 0.65
        st.Thickness = 1
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        st.Parent = b
        b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.14 }, 0.12) end)
        b.MouseLeave:Connect(function() tween(b, { BackgroundTransparency = 0 }, 0.12) end)
        b.MouseButton1Down:Connect(function() tween(b, { BackgroundTransparency = 0.32 }, 0.06) end)
        b.MouseButton1Up:Connect(function() tween(b, { BackgroundTransparency = 0 }, 0.12) end)
    end
    if onClick then b.MouseButton1Click:Connect(onClick) end
    return b
end

-- обновлялки динамических элементов, вызываются из refreshAll()
local updaters = {}
local function reg(fn)
    updaters[#updaters + 1] = fn
    fn()
end
local function refreshAll()
    for _, fn in ipairs(updaters) do pcall(fn) end
end

-- ══════════════════════════════
--     ОКНО
-- ══════════════════════════════
-- имя ScreenGui используется в endScreenVisible(), не менять
local sg = Instance.new("ScreenGui")
sg.Name = "BTDMacroV9"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = PlayerGui

local FRAME_W = 340
local FRAME_H = math.clamp(((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or 600) - 24, 300, 540)
local HEADER_H = 38
local TABS_H = 34
local STATUS_H = 26

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
frame.Position = UDim2.new(0, 10, 0.5, -FRAME_H / 2)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = sg
corner(frame, 16)
do
    local st = Instance.new("UIStroke")
    st.Color = C.accent
    st.Transparency = 0.35
    st.Thickness = 1.5
    st.Parent = frame
    local sgr = Instance.new("UIGradient")
    sgr.Color = ColorSequence.new(C.accent, C.accent2)
    sgr.Rotation = 90
    sgr.Parent = st
    local bgr = Instance.new("UIGradient")
    bgr.Color = ColorSequence.new(Color3.fromRGB(16, 17, 32), C.bg)
    bgr.Rotation = 90
    bgr.Parent = frame
end

-- шапка (за неё окно перетаскивается)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Parent = frame
corner(header, 16)

do
local headerFill = Instance.new("Frame")
headerFill.Size = UDim2.new(1, 0, 0, 14)
headerFill.Position = UDim2.new(0, 0, 1, -14)
headerFill.BackgroundColor3 = C.card
headerFill.BorderSizePixel = 0
headerFill.Parent = header
local line = Instance.new("Frame")
line.Size = UDim2.new(1, 0, 0, 2)
line.Position = UDim2.new(0, 0, 1, -2)
line.BorderSizePixel = 0
line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
line.Parent = header
local lg = Instance.new("UIGradient")
lg.Color = ColorSequence.new(C.accent, C.accent2)
lg.Parent = line
local pro = mkLabel(header, "PRO v14.2", UDim2.new(0, 112, 0.5, -8), UDim2.new(0, 46, 0, 16),
    { bold = true, size = 8, color = Color3.fromRGB(255, 255, 255), align = Enum.TextXAlignment.Center })
pro.BackgroundTransparency = 0
pro.BackgroundColor3 = C.accent
corner(pro, 8)
end

mkLabel(header, "⚔ BTD MACRO", UDim2.new(0, 12, 0, 0), UDim2.new(0, 100, 1, 0), { bold = true, size = 13 })

local stateChip = mkLabel(header, "—", UDim2.new(1, -170, 0.5, -10), UDim2.new(0, 92, 0, 20),
    { bold = true, size = 9, color = C.dim, align = Enum.TextXAlignment.Center })
stateChip.BackgroundTransparency = 0
stateChip.BackgroundColor3 = C.card2
stateChip.TextTruncate = Enum.TextTruncate.AtEnd
corner(stateChip, 10)

do
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- тело окна
local body = Instance.new("Frame")
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.Size = UDim2.new(1, 0, 1, -HEADER_H)
body.BackgroundTransparency = 1
body.Parent = frame

local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.new(0, 10, 0, 4)
tabBar.Size = UDim2.new(1, -20, 0, TABS_H - 6)
tabBar.BackgroundColor3 = C.card
tabBar.BorderSizePixel = 0
tabBar.Parent = body
corner(tabBar, 11)

local statusBar = Instance.new("Frame")
statusBar.Position = UDim2.new(0, 0, 1, -STATUS_H)
statusBar.Size = UDim2.new(1, 0, 0, STATUS_H)
statusBar.BackgroundColor3 = C.card
statusBar.BorderSizePixel = 0
statusBar.Parent = body
corner(statusBar, 12)

local statusDot = Instance.new("Frame")
statusDot.Position = UDim2.new(0, 10, 0.5, -4)
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.BackgroundColor3 = C.dim
statusDot.BorderSizePixel = 0
statusDot.Parent = statusBar
corner(statusDot, 4)

local statusLbl = mkLabel(statusBar, "Готов", UDim2.new(0, 26, 0, 0), UDim2.new(1, -36, 1, 0), { size = 10, color = C.dim })
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd

setStatus = function(txt, col)
    statusLbl.Text = txt
    statusLbl.TextColor3 = col or C.dim
    tween(statusDot, { BackgroundColor3 = col or C.dim }, 0.2)
end

local bodyArea = Instance.new("Frame")
bodyArea.Position = UDim2.new(0, 0, 0, TABS_H)
bodyArea.Size = UDim2.new(1, 0, 1, -(TABS_H + STATUS_H + 4))
bodyArea.BackgroundTransparency = 1
bodyArea.ClipsDescendants = true
bodyArea.Parent = body

-- ══════════════════════════════
--     СТРАНИЦЫ И ЭЛЕМЕНТЫ
-- ══════════════════════════════
local pages, orders = {}, {}

local function newPage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = name
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = C.accent
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.ScrollingDirection = Enum.ScrollingDirection.Y
    p.Size = UDim2.new(1, 0, 1, 0)
    p.Visible = false
    p.Parent = bodyArea
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = p
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = p
    pages[name] = p
    orders[p] = 0
    return p
end

local function nextOrder(p)
    orders[p] += 1
    return orders[p]
end

local function mkSection(page, text)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.Size = UDim2.new(1, 0, 0, 18)
    f.LayoutOrder = nextOrder(page)
    f.Parent = page
    local mark = Instance.new("Frame")
    mark.Position = UDim2.new(0, 0, 0.5, -6)
    mark.Size = UDim2.new(0, 3, 0, 12)
    mark.BackgroundColor3 = C.accent
    mark.BorderSizePixel = 0
    mark.Parent = f
    corner(mark, 2)
    mkLabel(f, text, UDim2.new(0, 10, 0, 0), UDim2.new(1, -10, 1, 0), { bold = true, size = 10, color = C.dim })
    return f
end

local function mkCard(page, height)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = C.card
    f.BorderSizePixel = 0
    f.Size = UDim2.new(1, 0, 0, height)
    f.LayoutOrder = nextOrder(page)
    f.ClipsDescendants = true
    f.Parent = page
    corner(f, 12)
    local st = Instance.new("UIStroke")
    st.Color = C.stroke
    st.Transparency = 0.6
    st.Thickness = 1
    st.Parent = f
    return f
end

local function mkStepper(card, y, caption, getV, setV, minV, maxV, step)
    mkLabel(card, caption, UDim2.new(0, 10, 0, y), UDim2.new(1, -150, 0, 28), { size = 11, color = C.dim })
    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.Position = UDim2.new(1, -136, 0, y)
    box.Size = UDim2.new(0, 126, 0, 28)
    box.Parent = card
    local val = mkLabel(box, "", UDim2.new(0, 32, 0, 0), UDim2.new(0, 62, 1, 0),
        { bold = true, align = Enum.TextXAlignment.Center })
    local function upd() val.Text = string.format("%.1f c", getV()) end
    mkButton(box, "−", UDim2.new(0, 0, 0, 0), UDim2.new(0, 30, 1, 0), C.card2, function()
        setV(math.max(minV, math.round((getV() - step) * 10) / 10))
        upd()
    end, { size = 14 })
    mkButton(box, "+", UDim2.new(1, -30, 0, 0), UDim2.new(0, 30, 1, 0), C.card2, function()
        setV(math.min(maxV, math.round((getV() + step) * 10) / 10))
        upd()
    end, { size = 14 })
    upd()
end

-- переключатель-«пилюля»: заголовок, пояснение (функция), положение on/off
local function mkSwitch(parent, y, title, subFn, getOn, onClick)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Position = UDim2.new(0, 10, 0, y)
    row.Size = UDim2.new(1, -20, 0, 44)
    row.Parent = parent
    mkLabel(row, title, UDim2.new(0, 0, 0, 0), UDim2.new(1, -60, 0, 22), { bold = true, size = 12 })
    local sub = mkLabel(row, "", UDim2.new(0, 0, 0, 22), UDim2.new(1, -60, 0, 22),
        { size = 9, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
    local track = Instance.new("Frame")
    track.Position = UDim2.new(1, -46, 0.5, -12)
    track.Size = UDim2.new(0, 46, 0, 24)
    track.BackgroundColor3 = C.card2
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 12)
    local knob = Instance.new("Frame")
    knob.Position = UDim2.new(0, 3, 0.5, -9)
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 9)
    local hit = Instance.new("TextButton")
    hit.BackgroundTransparency = 1
    hit.Size = UDim2.new(1, 0, 1, 0)
    hit.Text = ""
    hit.Parent = row
    hit.MouseButton1Click:Connect(onClick)
    reg(function()
        local on = getOn()
        tween(track, { BackgroundColor3 = on and C.green or C.card2 }, 0.15)
        tween(knob, { Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9) }, 0.15)
        sub.Text = subFn()
    end)
    return row
end

-- две независимые автоматики
local function hasRoutine(n)
    local r = routines[n]
    return r and type(r.packets) == "table" and #r.packets > 0
end

local function mkAutoSwitch(card, y, which)
    if which == "diff" then
        mkSwitch(card, y, "🎯 Авто выбор сложности",
            function()
                local mn = "mode_" .. tostring(settings.modeName)
                if not (hasRoutine(mn) or hasRoutine("start")) then
                    return "Нет записи для «" .. modeLabel(settings.modeName) .. "» (вкладка «Режим»)"
                end
                return "Лобби: сам выберет «" .. modeLabel(settings.modeName) .. "» и запустит матч"
            end,
            function() return settings.autoDiff == true end,
            function()
                if recording or capture then
                    setStatus("⚠ Сначала останови запись", C.yellow)
                    return
                end
                if not settings.autoDiff and not (hasRoutine("mode_" .. tostring(settings.modeName)) or hasRoutine("start")) then
                    setStatus("⚠ Запиши режим «" .. modeLabel(settings.modeName) .. "» на вкладке «Режим»", C.yellow)
                    return
                end
                setAutoDiff(not settings.autoDiff)
            end)
    elseif which == "speed" then
        mkSwitch(card, y, "⏩ Авто скорость",
            function()
                if not hasRoutine("speed_" .. tostring(settings.speedName)) then
                    return "Нет записи для " .. speedLabel(settings.speedName) .. " (вкладка «Запись»)"
                end
                return "Матч: сам включит скорость " .. speedLabel(settings.speedName)
            end,
            function() return settings.autoSpeed == true end,
            function()
                if recording or capture then
                    setStatus("⚠ Сначала останови запись", C.yellow)
                    return
                end
                if not settings.autoSpeed and not hasRoutine("speed_" .. tostring(settings.speedName)) then
                    setStatus("⚠ Запиши скорость " .. speedLabel(settings.speedName) .. " на вкладке «Запись»", C.yellow)
                    return
                end
                settings.autoSpeed = not settings.autoSpeed
                speedDone = false
                saveSettings()
                refreshAll()
            end)
    else
        mkSwitch(card, y, "🔁 Авто рестарт",
            function()
                if not hasRoutine("restart") then return "Нет записи РЕСТАРТ (вкладка «Авто» ниже)" end
                return "Матч: конец → рестарт → выбранный макрос заново"
            end,
            function() return settings.autoLoop == true end,
            function()
                if recording or capture then
                    setStatus("⚠ Сначала останови запись", C.yellow)
                    return
                end
                if not settings.autoLoop and not hasRoutine("restart") then
                    setStatus("⚠ Сначала запиши РЕСТАРТ", C.yellow)
                    return
                end
                setAuto(not settings.autoLoop)
            end)
    end
end

local function setPage(name) end -- переопределяется ниже

-- ══════════════════════════════
--     ЗАПИСЬ / ВОСПРОИЗВЕДЕНИЕ ПАКЕТОВ: ОБЩИЕ ДЕЙСТВИЯ
-- ══════════════════════════════
-- ══════════════════════════════
--     ВЫПАДАЮЩИЙ СПИСОК
-- ══════════════════════════════
local closeDropFn = nil
local function closeDrop()
    local f = closeDropFn
    closeDropFn = nil
    if f then pcall(f) end
end

-- getLabel() -> текст поля; getItems() -> { {id=, label=, sub=, selected=}, ... }; onPick(id)
local function mkDropdown(parent, pos, size, getLabel, getItems, onPick)
    local field = mkButton(parent, "", pos, size, C.card2, nil, { size = 12 })
    field.TextXAlignment = Enum.TextXAlignment.Left
    field.ClipsDescendants = true
    do
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 28)
        pad.Parent = field
        local arrow = mkLabel(field, "▾", UDim2.new(1, 4, 0, 0), UDim2.new(0, 22, 1, 0),
            { bold = true, size = 14, color = C.accent, align = Enum.TextXAlignment.Center })
        arrow.ZIndex = 2
    end
    field.TextTruncate = Enum.TextTruncate.AtEnd
    reg(function() field.Text = getLabel() end)

    field.MouseButton1Click:Connect(function()
        local wasOpen = closeDropFn ~= nil
        closeDrop()
        if wasOpen then return end
        local items = getItems()
        local ROW = 36
        local h = math.min(#items * ROW + 10, 216)
        local fx = field.AbsolutePosition.X - frame.AbsolutePosition.X
        local fy = field.AbsolutePosition.Y - frame.AbsolutePosition.Y
        local y = fy + field.AbsoluteSize.Y + 4
        if y + h > FRAME_H - STATUS_H - 4 and fy - h - 4 > 40 then
            y = fy - h - 4
        end

        local catcher = Instance.new("TextButton")
        catcher.BackgroundTransparency = 1
        catcher.Text = ""
        catcher.Size = UDim2.new(1, 0, 1, 0)
        catcher.ZIndex = 40
        catcher.Parent = frame

        local popup = Instance.new("Frame")
        popup.BackgroundColor3 = C.card
        popup.BorderSizePixel = 0
        popup.Position = UDim2.fromOffset(fx, y)
        popup.Size = UDim2.fromOffset(field.AbsoluteSize.X, h)
        popup.ZIndex = 41
        popup.Parent = frame
        corner(popup, 12)
        local st = Instance.new("UIStroke")
        st.Color = C.accent
        st.Transparency = 0.2
        st.Thickness = 1.2
        st.Parent = popup

        local list = Instance.new("ScrollingFrame")
        list.BackgroundTransparency = 1
        list.BorderSizePixel = 0
        list.Size = UDim2.new(1, 0, 1, 0)
        list.ScrollBarThickness = 3
        list.ScrollBarImageColor3 = C.accent
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.CanvasSize = UDim2.new(0, 0, 0, 0)
        list.Parent = popup
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 2)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Parent = list
        local lp = Instance.new("UIPadding")
        lp.PaddingTop = UDim.new(0, 5)
        lp.PaddingBottom = UDim.new(0, 5)
        lp.PaddingLeft = UDim.new(0, 5)
        lp.PaddingRight = UDim.new(0, 5)
        lp.Parent = list

        for i, it in ipairs(items) do
            local b = Instance.new("TextButton")
            b.AutoButtonColor = false
            b.LayoutOrder = i
            b.Size = UDim2.new(1, 0, 0, ROW - 2)
            b.BackgroundColor3 = it.selected and C.accent or C.card2
            b.BackgroundTransparency = it.selected and 0.25 or 0.55
            b.BorderSizePixel = 0
            b.Text = ""
            b.Parent = list
            corner(b, 8)
            local l1 = mkLabel(b, it.label, UDim2.new(0, 10, 0, 0), UDim2.new(1, -90, 1, 0),
                { bold = it.selected == true, size = 12 })
            l1.TextTruncate = Enum.TextTruncate.AtEnd
            if it.sub then
                mkLabel(b, it.sub, UDim2.new(1, -84, 0, 0), UDim2.new(0, 76, 1, 0),
                    { size = 9, color = it.subColor or C.dim, align = Enum.TextXAlignment.Right })
            end
            b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.1 }, 0.08) end)
            b.MouseLeave:Connect(function()
                tween(b, { BackgroundTransparency = it.selected and 0.25 or 0.55 }, 0.08)
            end)
            b.MouseButton1Click:Connect(function()
                closeDrop()
                onPick(it.id)
            end)
        end

        closeDropFn = function()
            catcher:Destroy()
            popup:Destroy()
        end
        catcher.MouseButton1Click:Connect(closeDrop)
    end)
    return field
end

local function toggleCapture(name)
    if capture then
        if capture.name == name then
            stopCapture()
            setStatus("✓ Запись '" .. name .. "' завершена", C.green)
        else
            setStatus("⚠ Сначала останови запись '" .. capture.name .. "'", C.yellow)
        end
    else
        if recording or playing then
            setStatus("⚠ Сначала останови макрос", C.yellow)
            return
        end
        startCapture(name)
        if name:sub(1, 5) == "mode_" then
            setStatus("⏺ Выбери режим и запусти матч вручную", C.red)
        elseif name:sub(1, 6) == "speed_" then
            setStatus("⏺ В матче нажми кнопку скорости до нужной, потом «Стоп записи»", C.red)
        else
            setStatus("⏺ Нажми перезапуск в игре, потом СТОП записи", C.red)
        end
    end
end

local function argText(a)
    if type(a) == "table" then
        if a.__v3 then
            return string.format("V(%.0f,%.0f,%.0f)", a.__v3[1], a.__v3[2], a.__v3[3])
        end
        return "nil"
    end
    return brief(a)
end

local function packetLabel(pk)
    local a = {}
    for k = 1, (pk.n or 0) do a[k] = argText(pk.args and pk.args[k]) end
    local what
    if pk.kind == "net" then
        what = "net " .. tostring(pk.wire)
    else
        what = tostring(pk.kind) .. " " .. brief(pk.path)
    end
    return what .. " (" .. table.concat(a, ", ") .. ")"
end

local function packetKey(pk)
    local ok, enc = pcall(function() return HttpService:JSONEncode(pk.args or {}) end)
    return tostring(pk.kind) .. "|" .. tostring(pk.wire) .. "|" .. tostring(pk.path) .. "|" .. tostring(pk.n) .. "|" .. (ok and enc or "?")
end

-- одинаковые подряд идущие пакеты сворачиваются в "×N"
local function routineSummary(name)
    local r = routines[name]
    if not r or type(r.packets) ~= "table" or #r.packets == 0 then return "Нет записи" end
    local lines, i, shown = {}, 1, 0
    while i <= #r.packets do
        local pk = r.packets[i]
        local j = i
        while j < #r.packets and packetKey(r.packets[j + 1]) == packetKey(pk) do j += 1 end
        shown += 1
        if shown > 6 then
            lines[#lines + 1] = "… ещё " .. (#r.packets - i + 1) .. " пак."
            break
        end
        local rep = j - i + 1
        lines[#lines + 1] = packetLabel(pk) .. (rep > 1 and (" ×" .. rep) or "") .. (pk.bad and " !" or "")
        i = j + 1
    end
    return table.concat(lines, "\n")
end

-- какие wire id/пакеты записаны для каждого режима
local function modeWiresText(list, prefix)
    list = list or MODES
    prefix = prefix or "mode_"
    local lines = {}
    for _, m in ipairs(list) do
        local r = routines[prefix .. m.id]
        local txt = "—"
        if r and type(r.packets) == "table" and #r.packets > 0 then
            local seen, order = {}, {}
            for _, pk in ipairs(r.packets) do
                local k = pk.kind == "net" and ("net " .. tostring(pk.wire)) or (tostring(pk.kind))
                if not seen[k] then seen[k] = 0; order[#order + 1] = k end
                seen[k] += 1
            end
            local parts = {}
            for _, k in ipairs(order) do parts[#parts + 1] = k .. "×" .. seen[k] end
            txt = "✓ " .. table.concat(parts, ", ")
        end
        lines[#lines + 1] = string.format("%-9s %s", m.label, txt)
    end
    return table.concat(lines, "\n")
end

local function mkRoutineCard(page, nameArg)
    local function getName() return type(nameArg) == "function" and nameArg() or nameArg end
    local card = mkCard(page, 226)
    local info = mkLabel(card, "", UDim2.new(0, 10, 0, 8), UDim2.new(1, -20, 0, 16), { bold = true, size = 11 })
    local rec = mkButton(card, "", UDim2.new(0, 10, 0, 30), UDim2.new(0.46, -10, 0, 30), C.red,
        function() toggleCapture(getName()) end)
    mkButton(card, "▶ Тест", UDim2.new(0.46, 0, 0, 30), UDim2.new(0.30, -4, 0, 30), C.card2, function()
        if capture then
            setStatus("⚠ Сначала останови запись", C.yellow)
            return
        end
        setStatus("▶ Тест '" .. getName() .. "'...", C.yellow)
        task.spawn(function()
            local ok = runRoutine(getName())
            setStatus(ok and ("✓ '" .. getName() .. "' отправлен") or ("✗ '" .. getName() .. "' не выполнен (см. журнал)"),
                ok and C.green or C.red)
        end)
    end)
    mkButton(card, "🗑", UDim2.new(0.76, 0, 0, 30), UDim2.new(0.24, -10, 0, 30), C.card2, function()
        if capture and capture.name == getName() then stopCapture() end
        routines[getName()] = nil
        saveRoutines()
        refreshAll()
        setStatus("🗑 Запись '" .. getName() .. "' удалена", C.dim)
    end)

    -- вторая строка: перезапись и правка
    mkButton(card, "↻ Перезаписать", UDim2.new(0, 10, 0, 66), UDim2.new(0.5, -14, 0, 28), C.accent, function()
        if recording or playing then
            setStatus("⚠ Сначала останови макрос", C.yellow)
            return
        end
        if capture then stopCapture() end
        routines[getName()] = nil
        saveRoutines()
        startCapture(getName())
        refreshAll()
        if getName():sub(1, 5) == "mode_" then
            setStatus("⏺ Старая запись удалена. Выбери режим и запусти матч", C.red)
        elseif getName():sub(1, 6) == "speed_" then
            setStatus("⏺ Старая запись удалена. В матче нажми кнопку скорости, потом «Стоп записи»", C.red)
        else
            setStatus("⏺ Старая запись удалена. Нажми перезапуск в игре, потом «Стоп записи»", C.red)
        end
    end, { size = 10 })
    mkButton(card, "✂ Убрать дубли", UDim2.new(0.5, 4, 0, 66), UDim2.new(0.5, -14, 0, 28), C.card2, function()
        local r = routines[getName()]
        if not r or type(r.packets) ~= "table" or #r.packets == 0 then
            setStatus("Нечего чистить", C.dim)
            return
        end
        local out, prev = {}, nil
        for _, pk in ipairs(r.packets) do
            local k = packetKey(pk)
            if k ~= prev then out[#out + 1] = pk end
            prev = k
        end
        local removed = #r.packets - #out
        if removed > 0 then
            if out[1] then out[1].dt = 0 end
            r.packets = out
            saveRoutines()
            setStatus("✂ Убрано повторов: " .. removed .. ", осталось " .. #out, C.green)
        else
            setStatus("Повторов нет", C.dim)
        end
        refreshAll()
    end, { size = 10 })
    mkButton(card, "⌫ Убрать последний пакет", UDim2.new(0, 10, 0, 98), UDim2.new(1, -20, 0, 24), C.card2, function()
        local r = routines[getName()]
        if r and type(r.packets) == "table" and #r.packets > 0 then
            table.remove(r.packets)
            if #r.packets == 0 then routines[getName()] = nil end
            saveRoutines()
            setStatus("⌫ Последний пакет убран", C.dim)
            refreshAll()
        end
    end, { size = 10 })

    local sum = mkLabel(card, "", UDim2.new(0, 10, 0, 128), UDim2.new(1, -20, 0, 94),
        { size = 9, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
    sum.Font = Enum.Font.Code
    reg(function()
        local r = routines[getName()]
        local cnt = (r and type(r.packets) == "table") and #r.packets or 0
        local active = capture and capture.name == getName()
        if active then
            info.Text = "⏺ Идёт запись..."
            info.TextColor3 = C.red
        elseif cnt > 0 then
            info.Text = "Записано: " .. cnt .. " пак." .. (r.placeId == game.PlaceId and "" or "  (другое место)")
            info.TextColor3 = (r.placeId == game.PlaceId) and C.green or C.yellow
        else
            info.Text = "Не записано"
            info.TextColor3 = C.dim
        end
        rec.Text = active and "⏹ Стоп записи" or "⏺ Записать"
        sum.Text = routineSummary(getName())
    end)
    return card
end

-- ══════════════════════════════
--     ОБЩИЕ СПИСКИ ДЛЯ ВЫПАДАЮЩИХ МЕНЮ
-- ══════════════════════════════
local function diffLabel()
    local id = settings.modeName
    return "🎯  " .. modeLabel(id) .. (hasRoutine("mode_" .. tostring(id)) and "   ✓" or "   · нет записи")
end

local function diffItems()
    local out = {}
    for _, m in ipairs(MODES) do
        local rec = hasRoutine("mode_" .. m.id)
        out[#out + 1] = {
            id = m.id, label = m.label, selected = settings.modeName == m.id,
            sub = rec and "✓ записан" or "нет записи", subColor = rec and C.green or C.dim,
        }
    end
    return out
end

local function diffPick(id)
    settings.modeName = id
    saveSettings()
    refreshAll()
end

local function speedLabelText()
    local id = settings.speedName
    return "⏩  " .. speedLabel(id) .. (hasRoutine("speed_" .. tostring(id)) and "   ✓" or "   · нет записи")
end

local function speedItems()
    local out = {}
    for _, m in ipairs(SPEEDS) do
        local rec = hasRoutine("speed_" .. m.id)
        out[#out + 1] = {
            id = m.id, label = m.label, selected = settings.speedName == m.id,
            sub = rec and "✓ записана" or "нет записи", subColor = rec and C.green or C.dim,
        }
    end
    return out
end

local function speedPick(id)
    settings.speedName = id
    saveSettings()
    refreshAll()
end

local function macroLabel()
    if settings.autoMacro then return "📋  " .. settings.autoMacro end
    return "Выбери макрос…"
end

local function macroItems()
    local out = { { id = false, label = "— не выбран —", selected = settings.autoMacro == nil } }
    for _, m in ipairs(getMacros()) do
        out[#out + 1] = { id = m.name, label = m.name, selected = settings.autoMacro == m.name }
    end
    return out
end

local function macroPick(id)
    settings.autoMacro = id or nil
    saveSettings()
    refreshAll()
end

-- ══════════════════════════════
--     ВКЛАДКА 1: ГЛАВНАЯ
-- ══════════════════════════════
local pHome = newPage("home")

mkSection(pHome, "СЛОЖНОСТЬ")
do
local c = mkCard(pHome, 74)
mkLabel(c, "Что выбирать в лобби", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 0, 16), { size = 10, color = C.dim })
mkDropdown(c, UDim2.new(0, 10, 0, 26), UDim2.new(1, -20, 0, 38), diffLabel, diffItems, diffPick)
end

mkSection(pHome, "СКОРОСТЬ")
do
local c = mkCard(pHome, 74)
mkLabel(c, "Что включать в матче", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 0, 16), { size = 10, color = C.dim })
mkDropdown(c, UDim2.new(0, 10, 0, 26), UDim2.new(1, -20, 0, 38), speedLabelText, speedItems, speedPick)
end

mkSection(pHome, "МАКРОС")
do
local c = mkCard(pHome, 74)
mkLabel(c, "Что запускать в матче", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 0, 16), { size = 10, color = C.dim })
mkDropdown(c, UDim2.new(0, 10, 0, 26), UDim2.new(1, -104, 0, 38), macroLabel, macroItems, macroPick)
mkButton(c, "▶", UDim2.new(1, -88, 0, 26), UDim2.new(0, 36, 0, 38), C.green, function()
    if recording or capture then
        setStatus("⚠ Сначала останови запись", C.yellow)
        return
    end
    if playing then
        setStatus("⚠ Уже запущено", C.yellow)
        return
    end
    task.spawn(startAutoMacro)
end, { size = 14, textColor = DARK_ON_GREEN })
mkButton(c, "⏹", UDim2.new(1, -46, 0, 26), UDim2.new(0, 36, 0, 38), C.card2, function()
    playing = false
    setStatus("■ Макрос остановлен", C.dim)
end, { size = 14 })
end

mkSection(pHome, "АВТОМАТИКА")
do
local c = mkCard(pHome, 162)
mkAutoSwitch(c, 8, "diff")
mkAutoSwitch(c, 58, "restart")
mkAutoSwitch(c, 108, "speed")
end

-- ══════════════════════════════
--     ВКЛАДКА 2: ЗАПИСЬ
-- ══════════════════════════════
local pRec = newPage("rec")

mkSection(pRec, "ЗАПИСЬ МАКРОСА")
local nameBox, recBtn
do
local c = mkCard(pRec, 92)
nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -20, 0, 34)
nameBox.Position = UDim2.new(0, 10, 0, 10)
nameBox.BackgroundColor3 = C.card2
nameBox.TextColor3 = C.text
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 12
nameBox.TextXAlignment = Enum.TextXAlignment.Left
nameBox.PlaceholderText = "Название макроса"
nameBox.PlaceholderColor3 = C.dim
nameBox.Text = ""
nameBox.ClearTextOnFocus = false
nameBox.BorderSizePixel = 0
nameBox.Parent = c
corner(nameBox, 9)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.Parent = nameBox
recBtn = mkButton(c, "⏺ НАЧАТЬ ЗАПИСЬ", UDim2.new(0, 10, 0, 50), UDim2.new(1, -20, 0, 34), C.red, nil, { size = 12 })
end

local function resetRecBtn()
    recBtn.Text = "⏺ НАЧАТЬ ЗАПИСЬ"
    recBtn.BackgroundColor3 = C.red
    recBtn.TextColor3 = C.text
end

mkSection(pRec, "МОИ МАКРОСЫ")
local listBox = Instance.new("Frame")
listBox.BackgroundTransparency = 1
listBox.Size = UDim2.new(1, 0, 0, 0)
listBox.AutomaticSize = Enum.AutomaticSize.Y
listBox.LayoutOrder = nextOrder(pRec)
listBox.Parent = pRec
do
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = listBox
end

-- ══════════════════════════════
--     ВКЛАДКА 3: НАСТРОЙКИ
-- ══════════════════════════════
local pSet = newPage("set")

mkSection(pSet, "ПАУЗЫ")
do
local c = mkCard(pSet, 152)
mkStepper(c, 108, "До смены скорости", function() return settings.speedDelay end,
    function(v) settings.speedDelay = v saveSettings() end, 0.5, 30, 0.5)
mkStepper(c, 6, "До рестарта", function() return settings.restartDelay end,
    function(v) settings.restartDelay = v saveSettings() end, 0.5, 30, 0.5)
mkStepper(c, 40, "До старта макроса", function() return settings.startDelay end,
    function(v) settings.startDelay = v saveSettings() end, 0.5, 30, 0.5)
mkStepper(c, 74, "Постановка (без t)", function() return DELAY_PLACE end,
    function(v) DELAY_PLACE = v end, 0.1, 5.0, 0.1)
end

mkSection(pSet, "ТЕЛЕПОРТ")
do
local c = mkCard(pSet, 62)
mkSwitch(c, 9, "♻ Автозагрузка после телепорта",
    function() return "queue_on_teleport, файл " .. tostring(settings.loaderFile) end,
    function() return settings.tpReload == true end,
    function()
        settings.tpReload = not settings.tpReload
        saveSettings()
        if settings.tpReload then
            if queueReload() then
                setStatus("✓ Автозагрузка включена", C.green)
            else
                setStatus("✗ В этом экзекьюторе нет queue_on_teleport", C.red)
            end
        end
        refreshAll()
    end)
end

-- заглушка на случай отсутствия доступа разработчика — reg() ниже всегда на что-то ссылается
local wireInfo = Instance.new("TextLabel")
wireInfo.Visible = false

-- ══════════════════════════════
--     ВКЛАДКА: РАЗРАБОТЧИК (только по ключу владельца)
-- ══════════════════════════════
local pDev = newPage("dev")
if ACCESS_LEVEL == "owner" then
mkSection(pDev, "WIRE ID")
do
local c = mkCard(pDev, 152)
wireInfo = mkLabel(c, "", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 34),
    { size = 10, color = C.text, wrap = true, yalign = Enum.TextYAlignment.Top })
mkButton(c, "Учить place", UDim2.new(0, 10, 0, 46), UDim2.new(0.5, -14, 0, 30), C.card2, function()
    learnPlaceUntil = os.clock() + 20
    setStatus("Поставь любую башню в игре (20 с)", C.yellow)
end, { size = 10 })
mkButton(c, "Учить skip", UDim2.new(0.5, 4, 0, 46), UDim2.new(0.5, -14, 0, 30), C.card2, function()
    skipVotes = {}
    setStatus("Нажми кнопку скипа в игре 2 раза", C.yellow)
end, { size = 10 })
mkButton(c, "Учить апгрейд", UDim2.new(0, 10, 0, 80), UDim2.new(0.5, -14, 0, 30), C.card2, function()
    startLearn("upgrade")
    setStatus("Улучши любую свою башню в игре (20 с)", C.yellow)
end, { size = 10 })
mkButton(c, "Учить продажу", UDim2.new(0.5, 4, 0, 80), UDim2.new(0.5, -14, 0, 30), C.card2, function()
    startLearn("sell")
    setStatus("Продай любую свою башню в игре (20 с)", C.yellow)
end, { size = 10 })
mkButton(c, "Сбросить все wire id", UDim2.new(0, 10, 0, 116), UDim2.new(1, -20, 0, 28), C.card2, function()
    for _, role in ipairs(WIRE_ROLES) do
        wire[role] = nil
        wireOk[role] = false
    end
    skipArgc = nil
    skipVotes = {}
    pcall(delfile, WIRE_FILE)
    onWireChanged()
    setStatus("Wire id сброшены; place определится при следующей постановке", C.yellow)
end, { size = 10 })
end

mkSection(pDev, "ЗАПИСЬ СЛОЖНОСТИ (выбор режима в лобби)")
do
local c = mkCard(pDev, 52)
mkDropdown(c, UDim2.new(0, 10, 0, 7), UDim2.new(1, -20, 0, 38), diffLabel, diffItems, diffPick)
end
mkRoutineCard(pDev, function() return "mode_" .. tostring(settings.modeName) end)

mkSection(pDev, "ЗАПИСЬ СКОРОСТИ (кнопка скорости в матче)")
do
local c = mkCard(pDev, 52)
mkDropdown(c, UDim2.new(0, 10, 0, 7), UDim2.new(1, -20, 0, 38), speedLabelText, speedItems, speedPick)
end
mkRoutineCard(pDev, function() return "speed_" .. tostring(settings.speedName) end)

mkSection(pDev, "ЗАПИСЬ РЕСТАРТА (кнопка на экране конца)")
mkRoutineCard(pDev, "restart")

-- общий "слушатель денег": слушает текстовые метки N секунд, помечает находки своим тегом.
-- Используется всеми тремя училками ниже — только тег и подсказка разные.
local function listenForMoney(tag, seconds, hint, onDone)
    local function moneyLike(t)
        return type(t) == "string" and (t:match("^%$?[%d][%d%s.,]*[KkMmBb]?$") or t:match("^[%d][%d%s.,]*[KkMmBb]$"))
    end
    local function note(d, t)
        dlog("[" .. tag .. "] " .. d:GetFullName():gsub("^.-%.PlayerGui%.", "") .. " -> '" .. tostring(t) .. "'")
    end
    local conns = {}
    local function watch(d)
        if not (d:IsA("TextLabel") or d:IsA("TextButton")) then return end
        if moneyLike(d.Text) then note(d, d.Text) end
        local ok, conn = pcall(function()
            return d:GetPropertyChangedSignal("Text"):Connect(function()
                if moneyLike(d.Text) then note(d, d.Text) end
            end)
        end)
        if ok then conns[#conns + 1] = conn end
    end
    for _, d in ipairs(PlayerGui:GetDescendants()) do watch(d) end
    conns[#conns + 1] = PlayerGui.DescendantAdded:Connect(function(d) task.defer(watch, d) end)
    dlog("[" .. tag .. "] слушаю " .. seconds .. " с: " .. hint)
    setStatus("👂 " .. hint, C.yellow)
    task.delay(seconds, function()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        if onDone then onDone() end
    end)
end

-- одна учи-секция: заголовок, поле пути, кнопка "учить", живое значение
local function mkMoneyTeacher(page, title, tag, hint, getPath, setPath, readFn)
    mkSection(page, title)
    do
    local c = mkCard(page, 128)
    local pathBox = Instance.new("TextBox")
    pathBox.Position = UDim2.new(0, 10, 0, 8)
    pathBox.Size = UDim2.new(1, -20, 0, 30)
    pathBox.BackgroundColor3 = C.card2
    pathBox.TextColor3 = C.text
    pathBox.Font = Enum.Font.Code
    pathBox.TextSize = 10
    pathBox.TextXAlignment = Enum.TextXAlignment.Left
    pathBox.ClearTextOnFocus = false
    pathBox.Text = getPath() or ""
    pathBox.PlaceholderText = "Players.Имя.PlayerGui.Main.Цена.Текст"
    pathBox.PlaceholderColor3 = C.dim
    pathBox.BorderSizePixel = 0
    pathBox.Parent = c
    corner(pathBox, 8)
    do
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8)
        pad.Parent = pathBox
    end
    pathBox.FocusLost:Connect(function()
        setPath(pathBox.Text)
        saveSettings()
        refreshAll()
    end)

    local btnText = "👂 Учить (15 с)"
    local listening = false
    local teachBtn = mkButton(c, btnText, UDim2.new(0, 10, 0, 44), UDim2.new(1, -20, 0, 28), C.accent, nil, { size = 10 })
    teachBtn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        teachBtn.Text = "👂 Идёт прослушка..."
        listenForMoney(tag, 15, hint, function()
            listening = false
            teachBtn.Text = btnText
            setStatus("👂 Готово, смотри журнал («Инфо»), путь впиши выше", C.dim)
        end)
    end)

    local liveLbl = mkLabel(c, "", UDim2.new(0, 12, 0, 80), UDim2.new(1, -24, 0, 42),
        { size = 10, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
    reg(function()
        local v = readFn()
        liveLbl.Text = "Сейчас читается: " .. (v and tostring(v) or "— (путь пуст или не найден)")
    end)
    end
end

mkSection(pDev, "БАЛАНС И ЦЕНЫ (чтобы макрос не ждал тайминг, а бил сразу по деньгам)")
do
local c = mkCard(pDev, 70)
mkLabel(c, "Три отдельных пути: общий баланс и цены двух действий. Жми «Учить», делай нужное в игре в это время, бери путь из журнала «Инфо» (строки [БАЛАНС]/[ЦЕНА УЛУЧШ]/[ЦЕНА ПОСТР]).",
    UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 1, -12), { size = 9, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
end

mkMoneyTeacher(pDev, "1. БАЛАНС", "БАЛАНС", "ничего не нажимай, просто дождись выдачи/изменения денег",
    function() return settings.moneyPath end,
    function(v) settings.moneyPath = v end,
    readBalance)

mkMoneyTeacher(pDev, "2. ЦЕНА УЛУЧШЕНИЯ", "ЦЕНА УЛУЧШ", "наведись/нажми на кнопку улучшения башни",
    function() return settings.upgradeCostPath end,
    function(v) settings.upgradeCostPath = v end,
    readUpgradeCost)

mkMoneyTeacher(pDev, "3. ЦЕНА ПОСТРОЙКИ", "ЦЕНА ПОСТР", "открой магазин/выбери башню для постройки",
    function() return settings.placeCostPath end,
    function(v) settings.placeCostPath = v end,
    readPlaceCost)

do
local c = mkCard(pDev, 64)
mkLabel(c, "Записанные макросы постановки/улучшения теперь несут price (прямая цена действия) и balance_before (запасной вариант). Воспроизведение бьёт действие сразу, как только живой баланс дорастёт до нужного числа, вместо ожидания записанного тайминга.",
    UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 1, -12), { size = 9, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
end
end

-- ══════════════════════════════
--     ВКЛАДКА 4: ИНФО
-- ══════════════════════════════
local pInfo = newPage("info")

mkSection(pInfo, "СОСТОЯНИЕ ИГРЫ")
local stateInfo = mkLabel(mkCard(pInfo, 70), "", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 1, -12),
    { size = 10, color = C.text, wrap = true, yalign = Enum.TextYAlignment.Top })

mkSection(pInfo, "СЛОЖНОСТИ И СКОРОСТИ: ЗАПИСАННЫЕ ПАКЕТЫ")
do
local c = mkCard(pInfo, 156)
local l = mkLabel(c, "", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 1, -12),
    { size = 10, color = C.text, wrap = true, yalign = Enum.TextYAlignment.Top })
l.Font = Enum.Font.Code
reg(function() l.Text = modeWiresText() .. "\n" .. modeWiresText(SPEEDS, "speed_") end)
end

mkSection(pInfo, "ЖУРНАЛ")
local logView
do
local c = mkCard(pInfo, 200)
logView = mkLabel(c, "", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 142),
    { size = 9, color = C.dim, wrap = true, yalign = Enum.TextYAlignment.Top })
logView.Font = Enum.Font.Code
mkButton(c, "📋 Копировать", UDim2.new(0, 10, 0, 162), UDim2.new(0.6, -14, 0, 30), C.accent, function()
    flushLog()
    local text = table.concat(logLines, "\n")
    if setclipboard then
        local ok = pcall(setclipboard, text)
        setStatus(ok and ("✓ Лог скопирован (" .. #logLines .. " строк)") or "✗ Не удалось скопировать",
            ok and C.green or C.red)
    else
        setStatus("Нет setclipboard; лог в файле " .. LOG_FILE, C.yellow)
    end
end)
mkButton(c, "🗑 Очистить", UDim2.new(0.6, 0, 0, 162), UDim2.new(0.4, -10, 0, 30), C.card2, function()
    logLines = {}
    flushLog()
    setStatus("Журнал очищен", C.dim)
end)
end

local function updateLogView()
    local from = math.max(1, #logLines - 13)
    local out = {}
    for i = from, #logLines do out[#out + 1] = logLines[i] end
    logView.Text = table.concat(out, "\n")
end

local function wireText()
    local parts = {}
    for _, role in ipairs(WIRE_ROLES) do
        local id = wire[role]
        parts[#parts + 1] = role .. " " .. (id and tostring(id) or "—") .. (id and (wireOk[role] and "✓" or "?") or "")
    end
    return table.concat(parts, "   ") .. "\n✓ подтверждён, ? предположение"
end

local function refreshState()
    local rs = roundState
    stateChip.Text = rs and tostring(rs) or "—"
    stateChip.TextColor3 = (rs == "TOWER_DEFENSE") and C.green or (rs and C.yellow or C.dim)
    stateInfo.Text = "round_state: " .. tostring(rs or "—")
        .. "\nтаймер перерыва: " .. tostring(intermissionTimer or "—")
        .. "\nPlaceId: " .. tostring(game.PlaceId) .. "   версия: " .. tostring(placeVersion)
end

reg(function() wireInfo.Text = wireText() end)
onWireChanged = function() wireInfo.Text = wireText() end
onAutoChanged = refreshAll
onStateChanged = refreshState
refreshState()

-- ══════════════════════════════
--     ВКЛАДКИ
-- ══════════════════════════════
local TAB_DEFS = {
    { id = "home", text = "🏠 Главная" },
    { id = "rec",  text = "⏺ Запись" },
}
if ACCESS_LEVEL == "owner" then
    table.insert(TAB_DEFS, { id = "dev", text = "🛠 Разраб." })
end
table.insert(TAB_DEFS, { id = "set", text = "⚙ Настр." })
table.insert(TAB_DEFS, { id = "info", text = "ℹ Инфо" })
local tabButtons = {}
local tabInd = Instance.new("Frame")
tabInd.Size = UDim2.new(1 / #TAB_DEFS, -4, 1, -4)
tabInd.Position = UDim2.new(0, 2, 0, 2)
tabInd.BackgroundColor3 = C.accent
tabInd.BorderSizePixel = 0
tabInd.Parent = tabBar
corner(tabInd, 9)
do
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(C.accent, C.accent2)
    g.Rotation = 20
    g.Parent = tabInd
end

setPage = function(id)
    closeDrop()
    for i, def in ipairs(TAB_DEFS) do
        local on = def.id == id
        pages[def.id].Visible = on
        tabButtons[def.id].TextColor3 = on and Color3.fromRGB(255, 255, 255) or C.dim
        if on then
            tween(tabInd, { Position = UDim2.new((i - 1) / #TAB_DEFS, 2, 0, 2) }, 0.18)
        end
    end
    if id == "info" then updateLogView() end
end

for i, def in ipairs(TAB_DEFS) do
    local b = mkButton(tabBar, def.text, UDim2.new((i - 1) / #TAB_DEFS, 0, 0, 0),
        UDim2.new(1 / #TAB_DEFS, 0, 1, 0), C.card, function() setPage(def.id) end, { size = 10, flat = true })
    b.ZIndex = 2
    tabButtons[def.id] = b
end

task.spawn(function()
    while sg.Parent do
        task.wait(1)
        if pages.info.Visible then updateLogView() end
    end
end)

-- ══════════════════════════════
--     МАКРОСЫ: СПИСОК, ЗАПИСЬ
-- ══════════════════════════════
local refreshList
refreshList = function()
    for _, c in ipairs(listBox:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end

    local macros = getMacros()
    if #macros == 0 then
        local el = mkLabel(listBox, "Макросов нет. Запиши первый выше.", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 28),
            { size = 11, color = C.dim, align = Enum.TextXAlignment.Center })
        el.LayoutOrder = 1
    end

    for i, macro in ipairs(macros) do
        local m = macro
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = C.card
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.Parent = listBox
        corner(row, 12)
        local rs = Instance.new("UIStroke")
        rs.Color = C.stroke
        rs.Transparency = 0.6
        rs.Parent = row

        local pick = mkButton(row, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, -92, 1, 0), C.card, function()
            settings.autoMacro = m.name
            saveSettings()
            refreshAll()
            setStatus("✓ Выбран макрос: " .. m.name, C.green)
        end, { flat = true, size = 11 })
        pick.TextXAlignment = Enum.TextXAlignment.Left
        do
            local pp = Instance.new("UIPadding")
            pp.PaddingLeft = UDim.new(0, 12)
            pp.Parent = pick
        end
        pick.TextTruncate = Enum.TextTruncate.AtEnd
        reg(function()
            local on = settings.autoMacro == m.name
            pick.Text = (on and "● " or "○ ") .. m.name
            pick.TextColor3 = on and C.green or C.text
        end)

        local pb = mkButton(row, "▶", UDim2.new(1, -82, 0.5, -15), UDim2.new(0, 36, 0, 30), C.green, nil,
            { size = 14, textColor = DARK_ON_GREEN, radius = 15 })
        local db = mkButton(row, "🗑", UDim2.new(1, -42, 0.5, -15), UDim2.new(0, 36, 0, 30), C.card2, nil,
            { size = 12, radius = 15 })

        pb.MouseButton1Click:Connect(function()
            if playing then
                setStatus("⚠ Уже запущено!", C.yellow)
                return
            end
            if recording or capture then
                setStatus("⚠ Сначала останови запись", C.yellow)
                return
            end
            local ok, raw = pcall(readfile, m.path)
            if not ok then
                setStatus("✗ Файл не найден", C.red)
                return
            end
            local ok2, acts = pcall(function() return HttpService:JSONDecode(raw) end)
            if not ok2 or type(acts) ~= "table" then
                setStatus("✗ Ошибка JSON", C.red)
                return
            end
            pb.BackgroundColor3 = Color3.fromRGB(30, 130, 95)
            playMacro(acts, function(st)
                setStatus("▶ " .. m.name .. ": " .. st, C.yellow)
            end, function()
                pb.BackgroundColor3 = C.green
            end)
        end)

        db.MouseButton1Click:Connect(function()
            pcall(delfile, m.path)
            if settings.autoMacro == m.name then
                settings.autoMacro = nil
                saveSettings()
            end
            setStatus("🗑 Удалено: " .. m.name, C.dim)
            refreshList()
            refreshAll()
        end)
    end
end

recBtn.MouseButton1Click:Connect(function()
    if playing then
        setStatus("⚠ Сначала останови воспроизведение", C.yellow)
        return
    end
    if capture then
        setStatus("⚠ Сначала останови запись пакетов", C.yellow)
        return
    end

    if not recording then
        recording = true
        recActions = {}
        waveCounter = 0
        recStart = os.clock()
        recBtn.Text = "⏹ ОСТАНОВИТЬ И СОХРАНИТЬ"
        recBtn.BackgroundColor3 = C.green
        recBtn.TextColor3 = DARK_ON_GREEN
        setStatus("⏺ Запись идёт... (начинай на чистой карте)", C.red)
    else
        recording = false
        resetRecBtn()
        setStatus("… сохраняю", C.yellow)

        task.spawn(function()
            local deadline = os.clock() + ENTITY_TIMEOUT + 0.5
            while pendingPlaces > 0 and os.clock() < deadline do task.wait(0.05) end

            local out, dropped = {}, 0
            for _, a in ipairs(recActions) do
                if a.action == "place" and not a.entity_id then
                    dropped += 1
                else
                    out[#out + 1] = a
                end
            end

            local macroName = sanitizeName(nameBox.Text)
            if macroName == "" then macroName = "macro_" .. os.time() end
            local path = FOLDER .. "/" .. macroName .. ".json"
            local ok = pcall(writefile, path, HttpService:JSONEncode(out))
            nameBox.Text = ""

            if ok then
                settings.autoMacro = macroName
                saveSettings()
                setStatus("✓ " .. macroName .. " (" .. #out .. " действий"
                    .. (dropped > 0 and (", потеряно place: " .. dropped) or "") .. ")", C.green)
            else
                setStatus("✗ Не удалось записать файл", C.red)
            end
            refreshList()
            refreshAll()
        end)
    end
end)

-- ══════════════════════════════
--     ШАПКА: СТОП И СВЕРНУТЬ
-- ══════════════════════════════
local function stopAll()
    local wasRecording = recording
    if settings.autoLoop or settings.autoDiff then
        settings.autoLoop = false
        settings.autoDiff = false
        applyAuto()
    end
    if capture then stopCapture() end
    playing = false
    recording = false
    resetRecBtn()
    setStatus(wasRecording and "■ Запись отменена (не сохранена)" or "■ Остановлено", C.red)
end

mkButton(header, "■", UDim2.new(1, -70, 0.5, -13), UDim2.new(0, 28, 0, 26), C.red, stopAll, { size = 12 })

local minimized = false
mkButton(header, "—", UDim2.new(1, -38, 0.5, -13), UDim2.new(0, 28, 0, 26), C.card2, function()
    closeDrop()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = minimized and UDim2.new(0, FRAME_W, 0, HEADER_H) or UDim2.new(0, FRAME_W, 0, FRAME_H)
end, { size = 14 })

-- ══════════════════════════════
--     СТАРТ
-- ══════════════════════════════
refreshList()
refreshAll()
setPage("home")

if settings.autoLoop or settings.autoDiff then
    task.delay(3, function()
        if settings.autoLoop or settings.autoDiff then applyAuto() end
    end)
end
startSpeedWatcher()
dlog("[OK] BTD Macro v14.2 загружен")
dlog("[UUID] Ball -> " .. tostring(uuidMap["Ball"]))
end

buildGui()
