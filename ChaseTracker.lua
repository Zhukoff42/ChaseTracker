script_name('ChaseTracker')
script_author('Zhukoff')
script_version('1')

require 'lib.moonloader'
local sampev = require 'lib.samp.events'
local vk = require 'lib.vkeys'
local inicfg = require 'inicfg'
local imgui = require 'mimgui'
local ffi = require 'ffi' 
local encoding = require 'encoding'
local bit = require 'bit'
local dlstatus = require('moonloader').download_status

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local cur_version = thisScript().version or '1.1'
local update_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/Update.json'
local script_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/ChaseTracker.lua'
local update_path = getWorkingDirectory() .. '\\update_chase.json'
local script_path = thisScript().path

local update_state = "Ожидание проверки..."
local update_available = false
local new_version = ""
local need_reload = false

local ini_file = 'ChaseTracker_UI.ini'

local default_cfg = {
    main = {
        hud_x = 500, hud_y = 500,
        hud_scale = 1.0, 
        show_nick = true, show_id = true, show_status = true, show_z_timer = true, show_arrow = true,
        arrow_size = 18.0,
        arrow_anim = false,
        z_color_r = 0.0, z_color_g = 1.0, z_color_b = 0.0, z_color_a = 1.0,
        arrow_color_r = 1.0, arrow_color_g = 0.0, arrow_color_b = 0.0, arrow_color_a = 1.0,
        text_color_r = 0.95, text_color_g = 0.95, text_color_b = 0.95, text_color_a = 1.0,
        bind_z = 49,
        bind_cuff = 0,
        bind_pull = 0,
        bind_gotome = 0,
        bind_domkrat = 53,
        binds_data = "[]"
    }
}
local settings = { main = {}, binds = {} }

local chase = {
    active = false, name = "", id = -1, status = "", z_expiry = 0, z_name = "" 
}

local ui_menu = imgui.new.bool(false)
local ui_edit_hud = imgui.new.bool(false)
local ui_inputCmd = imgui.new.char[256]()
local ui_currentKey = 0
local ui_isWaitingKey = false
local ui_waiting_bind = nil 

local cb_show_nick = imgui.new.bool(default_cfg.main.show_nick)
local cb_show_id = imgui.new.bool(default_cfg.main.show_id)
local cb_show_status = imgui.new.bool(default_cfg.main.show_status)
local cb_show_z = imgui.new.bool(default_cfg.main.show_z_timer)
local cb_show_arrow = imgui.new.bool(default_cfg.main.show_arrow)

local slider_arrow_size = imgui.new.float[1](default_cfg.main.arrow_size)
local cb_arrow_anim = imgui.new.bool(default_cfg.main.arrow_anim)

local color_z = imgui.new.float[4](default_cfg.main.z_color_r, default_cfg.main.z_color_g, default_cfg.main.z_color_b, default_cfg.main.z_color_a)
local color_arrow = imgui.new.float[4](default_cfg.main.arrow_color_r, default_cfg.main.arrow_color_g, default_cfg.main.arrow_color_b, default_cfg.main.arrow_color_a)
local color_text = imgui.new.float[4](default_cfg.main.text_color_r, default_cfg.main.text_color_g, default_cfg.main.text_color_b, default_cfg.main.text_color_a)
local slider_scale = imgui.new.float[1](default_cfg.main.hud_scale)

local lastRmbPress = 0
local rmbTargetWindow = 0

local keys = {}
for k, v in pairs(vk) do keys[v] = k:gsub("VK_", "") end

local sampIsPlayerConnected = sampIsPlayerConnected
local sampGetPlayerNickname = sampGetPlayerNickname
local isCharOnScreen = isCharOnScreen
local getCharCoordinates = getCharCoordinates
local getActiveCameraCoordinates = getActiveCameraCoordinates
local isLineOfSightClear = isLineOfSightClear
local convert3DCoordsToScreen = convert3DCoordsToScreen
local math_sin = math.sin
local os_clock = os.clock
local os_time = os.time
local string_format = string.format
local getScreenResolution = getScreenResolution

function getKeyName(id)
    if not id or id == 0 then return "НЕ НАЗНАЧЕНО" end
    return keys[id] or tostring(id)
end

function check_update()
    update_state = "Проверка обновлений..."
    local no_cache_url = update_url .. "?t=" .. tostring(os_time())
    downloadUrlToFile(no_cache_url, update_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            if doesFileExist(update_path) then
                local file = io.open(update_path, "r")
                if file then
                    local content = file:read("*a")
                    file:close()
                    os.remove(update_path)
                    local data = decodeJson(content)
                    if data and data.version then
                        if tostring(data.version) ~= tostring(cur_version) then
                            update_available = true
                            new_version = tostring(data.version)
                            update_state = "Доступно обновление: v" .. new_version
                        else
                            update_state = "У вас установлена последняя версия."
                            update_available = false
                        end
                    else
                        update_state = "Ошибка: неверный формат Update.json"
                    end
                else
                    update_state = "Ошибка чтения файла проверки."
                end
            else
                update_state = "Файл обновления не был сохранен."
            end
        elseif status == dlstatus.STATUSEX_ERROR then
            update_state = "Ошибка соединения при проверке."
        end
    end)
end

function perform_update()
    update_state = "Скачивание обновления..."
    local no_cache_url = script_url .. "?t=" .. tostring(os_time())
    downloadUrlToFile(no_cache_url, script_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            need_reload = true
        elseif status == dlstatus.STATUSEX_ERROR then
            update_state = "Ошибка при скачивании обновления."
            sampAddChatMessage("[ChaseTracker] Не удалось скачать обновление!", 0xFF0000)
        end
    end)
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors
    
    style.WindowRounding = 6.0
    style.FrameRounding = 4.0
    style.PopupRounding = 4.0
    style.ScrollbarRounding = 4.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.FramePadding = imgui.ImVec2(6, 4)
    style.ItemSpacing = imgui.ImVec2(8, 6)

    colors[imgui.Col.WindowBg]        = imgui.ImVec4(0.08, 0.08, 0.08, 0.98)
    colors[imgui.Col.TitleBg]         = imgui.ImVec4(0.04, 0.04, 0.04, 1.00)
    colors[imgui.Col.TitleBgActive]   = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    colors[imgui.Col.Button]          = imgui.ImVec4(0.15, 0.15, 0.15, 1.00)
    colors[imgui.Col.ButtonHovered]   = imgui.ImVec4(0.22, 0.22, 0.22, 1.00)
    colors[imgui.Col.ButtonActive]    = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    colors[imgui.Col.FrameBg]         = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
    colors[imgui.Col.FrameBgHovered]  = imgui.ImVec4(0.18, 0.18, 0.18, 1.00)
    colors[imgui.Col.FrameBgActive]   = imgui.ImVec4(0.25, 0.25, 0.25, 1.00)
    colors[imgui.Col.CheckMark]       = imgui.ImVec4(0.90, 0.90, 0.90, 1.00)
    colors[imgui.Col.SliderGrab]      = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[imgui.Col.SliderGrabActive]= imgui.ImVec4(0.70, 0.70, 0.70, 1.00)
    colors[imgui.Col.Text]            = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[imgui.Col.Tab]             = imgui.ImVec4(0.10, 0.10, 0.10, 1.00)
    colors[imgui.Col.TabHovered]      = imgui.ImVec4(0.18, 0.18, 0.18, 1.00)
    colors[imgui.Col.TabActive]       = imgui.ImVec4(0.24, 0.24, 0.24, 1.00)
end)

local function draw_sys_bind(label, bind_key_name)
    imgui.Text(u8(label))
    imgui.SameLine(150)
    local current_key = settings.main[bind_key_name] or 0
    local btn_text = (ui_waiting_bind == bind_key_name) and u8"ЖДЕМ НАЖАТИЯ (ESC - СБРОС)" or (current_key == 0 and u8"НЕ НАЗНАЧЕНО" or u8(getKeyName(current_key)))
    if imgui.Button(btn_text .. "##" .. bind_key_name, imgui.ImVec2(-1, 25)) then
        ui_waiting_bind = bind_key_name
    end
end

local render_update_window = imgui.OnFrame(function() return update_available end, function(player)
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(380, 210), imgui.Cond.Always)
    
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.1, 0.1, 0.1, 1.0))
    
    if imgui.Begin(u8"Доступно обновление ChaseTracker", nil, bit.bor(imgui.WindowFlags.NoCollapse, imgui.WindowFlags.NoResize, imgui.WindowFlags.NoSavedSettings)) then
        imgui.Text(u8("Текущая версия: v" .. cur_version))
        imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8("Новая версия: v" .. new_version))
        imgui.Separator()
        imgui.TextWrapped(u8"Рекомендуется обновить скрипт для получения новых функций и исправления ошибок.")
        
        imgui.Spacing()
        if imgui.Button(u8"ОБНОВИТЬ СЕЙЧАС", imgui.ImVec2(-1, 35)) then
            perform_update()
            update_available = false
        end
        imgui.Spacing()
        if imgui.Button(u8"Напомнить позже", imgui.ImVec2(-1, 25)) then
            update_available = false
        end
    end
    imgui.End()
    imgui.PopStyleColor()
end)

local render_menu = imgui.OnFrame(function() return ui_menu[0] end, function(player)
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(550, 520), imgui.Cond.FirstUseEver)
    
    if imgui.Begin(u8"Настройки ChaseTracker", ui_menu, imgui.WindowFlags.NoCollapse) then
        if imgui.BeginTabBar("Tabs") then
            
            if imgui.BeginTabItem(u8"Внешний вид HUD") then
                imgui.Text(u8"Элементы на экране:")
                if imgui.Checkbox(u8"Показывать Ник", cb_show_nick) then settings.main.show_nick = cb_show_nick[0] saveSettings() end
                if imgui.Checkbox(u8"Показывать ID", cb_show_id) then settings.main.show_id = cb_show_id[0] saveSettings() end
                if imgui.Checkbox(u8"Показывать Статус", cb_show_status) then settings.main.show_status = cb_show_status[0] saveSettings() end
                if imgui.Checkbox(u8"Показывать Таймер /z", cb_show_z) then settings.main.show_z_timer = cb_show_z[0] saveSettings() end
                
                imgui.Separator()
                imgui.Text(u8"Текст и Цвета:")
                if imgui.SliderFloat(u8"Размер текста (Scale)", slider_scale, 0.5, 3.0) then settings.main.hud_scale = slider_scale[0] saveSettings() end
                if imgui.ColorEdit4(u8"Цвет основного текста", color_text) then
                    settings.main.text_color_r = color_text[0]; settings.main.text_color_g = color_text[1]; settings.main.text_color_b = color_text[2]; settings.main.text_color_a = color_text[3]; saveSettings()
                end
                if imgui.ColorEdit4(u8"Цвет таймера /z", color_z) then
                    settings.main.z_color_r = color_z[0]; settings.main.z_color_g = color_z[1]; settings.main.z_color_b = color_z[2]; settings.main.z_color_a = color_z[3]; saveSettings()
                end
                
                imgui.Separator()
                imgui.Text(u8"Стрелка над головой:")
                if imgui.Checkbox(u8"Включить маркер над целью", cb_show_arrow) then settings.main.show_arrow = cb_show_arrow[0] saveSettings() end
                if imgui.Checkbox(u8"Анимация (плавает вверх-вниз)", cb_arrow_anim) then settings.main.arrow_anim = cb_arrow_anim[0] saveSettings() end
                if imgui.SliderFloat(u8"Размер маркера", slider_arrow_size, 5.0, 50.0) then settings.main.arrow_size = slider_arrow_size[0] saveSettings() end
                
                if imgui.ColorEdit4(u8"Цвет маркера", color_arrow) then
                    settings.main.arrow_color_r = color_arrow[0]; settings.main.arrow_color_g = color_arrow[1]; settings.main.arrow_color_b = color_arrow[2]; settings.main.arrow_color_a = color_arrow[3]; saveSettings()
                end
                
                imgui.Separator()
                if imgui.Button(ui_edit_hud[0] and u8"СОХРАНИТЬ ПОЗИЦИЮ HUD" or u8"ПЕРЕМЕСТИТЬ HUD", imgui.ImVec2(-1, 40)) then
                    ui_edit_hud[0] = not ui_edit_hud[0]
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Системные Бинды") then
                imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1), u8"Нажмите на кнопку, чтобы назначить клавишу. Нажмите ESC для сброса.")
                imgui.Separator()
                draw_sys_bind("/z", "bind_z")
                draw_sys_bind("/cuff", "bind_cuff")
                draw_sys_bind("/gotome", "bind_gotome")
                draw_sys_bind("/pull", "bind_pull")
                imgui.Separator()
                draw_sys_bind("/domkrat", "bind_domkrat")
                
                imgui.EndTabItem()
            end
            
            if imgui.BeginTabItem(u8"Свои Команды") then
                imgui.Text(u8"Добавить кастомный бинд:")
                imgui.PushItemWidth(300)
                imgui.InputTextWithHint("##cmd", u8"/su {id} 3 Неподчинение", ui_inputCmd, 256)
                imgui.PopItemWidth()
                imgui.SameLine()
                
                local keyName = (ui_isWaitingKey) and u8"ЖДУ..." or (ui_currentKey == 0 and u8"ВЫБРАТЬ" or u8(getKeyName(ui_currentKey)))
                if imgui.Button(keyName, imgui.ImVec2(100, 25)) then ui_isWaitingKey = true end
                
                if imgui.Button(u8"ДОБАВИТЬ", imgui.ImVec2(-1, 30)) then
                    -- Сохраняем строку в оригинальном UTF-8, чтобы encodeJson не ломался при сохранении
                    local cmdStr = ffi.string(ui_inputCmd)
                    if cmdStr and #cmdStr > 0 and ui_currentKey ~= 0 then
                        table.insert(settings.binds, {key = ui_currentKey, cmd = cmdStr})
                        saveSettings()
                        ui_currentKey = 0
                        ui_inputCmd[0] = 0
                    end
                end
                
                imgui.Separator()
                imgui.BeginChild("BindList", imgui.ImVec2(0, -10), true)
                    for i, bind in ipairs(settings.binds) do
                        imgui.PushIDInt(i)
                        imgui.TextColored(imgui.ImVec4(0.4, 0.8, 0.4, 1), "[" .. getKeyName(bind.key or 0) .. "]")
                        imgui.SameLine()
                        -- Отрисовываем строку напрямую (она уже в UTF-8)
                        imgui.Text(tostring(bind.cmd or "Error"))
                        
                        imgui.SameLine(imgui.GetContentRegionAvail().x - 60) 
                        if imgui.Button(u8"Удалить") then
                            table.remove(settings.binds, i)
                            saveSettings()
                        end
                        imgui.PopID()
                    end
                imgui.EndChild()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Информация") then
                imgui.Text(u8"Скрипт: ChaseTracker")
                imgui.Text(u8"Автор: Zhukoff")
                imgui.Text(u8"Текущая версия: v" .. cur_version)
                imgui.Separator()
                imgui.Text(u8"Статус: " .. u8(update_state))
                
                if imgui.Button(u8"Проверить обновления", imgui.ImVec2(-1, 35)) then
                    check_update()
                end
                
                if update_available then
                    if imgui.Button(u8"Установить обновление", imgui.ImVec2(-1, 35)) then
                        perform_update()
                        update_available = false
                    end
                end
                
                imgui.EndTabItem()
            end
            
            imgui.EndTabBar()
        end
    end
    imgui.End()
end)

local render_hud = imgui.OnFrame(function() return chase.active or ui_edit_hud[0] end, function(player)
    local flags = bit.bor(imgui.WindowFlags.NoTitleBar, imgui.WindowFlags.NoResize, imgui.WindowFlags.NoCollapse, 
                          imgui.WindowFlags.AlwaysAutoResize, imgui.WindowFlags.NoFocusOnAppearing, imgui.WindowFlags.NoBringToFrontOnFocus)
    
    if not ui_edit_hud[0] then
        flags = bit.bor(flags, imgui.WindowFlags.NoMove, imgui.WindowFlags.NoInputs)
    end

    imgui.SetNextWindowPos(imgui.ImVec2(settings.main.hud_x, settings.main.hud_y), imgui.Cond.FirstUseEver)
    
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.04, 0.04, 0.04, 0.85))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
    
    if imgui.Begin("ChaseHUD", nil, flags) then
        if ui_edit_hud[0] then
            local pos = imgui.GetWindowPos()
            settings.main.hud_x = pos.x
            settings.main.hud_y = pos.y
            imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"РЕЖИМ РЕДАКТИРОВАНИЯ (Двигай окно)")
        end

        imgui.SetWindowFontScale(settings.main.hud_scale)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(settings.main.text_color_r, settings.main.text_color_g, settings.main.text_color_b, settings.main.text_color_a))

        if settings.main.show_nick then imgui.Text(u8("Цель: " .. tostring(chase.name or ""))) end
        if settings.main.show_id then imgui.Text(u8("ID: " .. tostring(chase.id or -1))) end
        if settings.main.show_status then 
            local st = (chase.status == nil or chase.status == "") and "Активна" or chase.status
            imgui.Text(u8("Статус: " .. tostring(st))) 
        end
        
        imgui.PopStyleColor()

        if settings.main.show_z_timer then
            local zText = "Нет"
            if chase.z_expiry and chase.z_expiry > 0 and chase.name == chase.z_name then
                local timeLeft = chase.z_expiry - os_time()
                if timeLeft > 0 then
                    zText = string_format("%02d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
                else
                    zText = "СПАЛА!"
                end
            end
            imgui.Text(u8"Таймер /z: ")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(settings.main.z_color_r, settings.main.z_color_g, settings.main.z_color_b, settings.main.z_color_a), u8(zText))
        end

        if chase.active and settings.main.show_arrow and sampIsPlayerConnected(chase.id) then
            local _, ped = sampGetCharHandleBySampPlayerId(chase.id)
            if ped and doesCharExist(ped) and isCharOnScreen(ped) then
                local px, py, pz = getCharCoordinates(ped)
                local cx, cy, cz = getActiveCameraCoordinates()
                
                if isLineOfSightClear(cx, cy, cz, px, py, pz + 0.8, true, false, false, true, false, false, false) then
                    local rX, rY = convert3DCoordsToScreen(px, py, pz + 1.0)
                    
                    if rX and rY then
                        local size = settings.main.arrow_size or 18.0
                        local yOffset = 15
                        
                        if settings.main.arrow_anim then
                            yOffset = 15 + math_sin(os_clock() * 6) * 5
                        end

                        local draw_list = imgui.GetBackgroundDrawList()
                        local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                            settings.main.arrow_color_r,
                            settings.main.arrow_color_g,
                            settings.main.arrow_color_b,
                            settings.main.arrow_color_a
                        ))
                        
                        local p1 = imgui.ImVec2(rX, rY - yOffset)
                        local p2 = imgui.ImVec2(rX - size / 2, rY - yOffset - size)
                        local p3 = imgui.ImVec2(rX + size / 2, rY - yOffset - size)
                        
                        draw_list:AddTriangleFilled(p1, p2, p3, col)
                    end
                end
            end
        end
    end
    imgui.End()
    
    imgui.PopStyleVar(2)
    imgui.PopStyleColor()
end)

function main()
    if not isSampLoaded() then return end
    while not isSampAvailable() do wait(100) end
    loadSettings()
    
    sampAddChatMessage("[ChaseTracker] v" .. cur_version .. " by Zhukoff загружен. Меню: {FFFF00}/chase", 0x00FF00)
    
    sampRegisterChatCommand("chase", function() ui_menu[0] = not ui_menu[0] end)
    
    sampRegisterChatCommand("trg", function(arg)
        arg = arg or ""
        if #arg == 0 then
            resetChase()
            sampAddChatMessage("[ChaseTracker] Ручная цель сброшена.", 0xFFFF00)
            return
        end
        local id = tonumber(arg:match("%d+"))
        if id and sampIsPlayerConnected(id) then 
            setTarget(id, "Ручной таргет (/trg)")
        else
            sampAddChatMessage("[ChaseTracker] Игрок с таким ID не найден!", 0xFF0000)
        end
    end)
    
    sampRegisterChatCommand("pursuit", function(arg)
        arg = arg or ""
        sampSendChat("/pursuit " .. arg)
        local id = tonumber(arg:match("%d+"))
        if id and sampIsPlayerConnected(id) then 
            setTarget(id, "Погоня (/pursuit)") 
        end
    end)

    check_update()

    while true do
        wait(0)
        
        if need_reload then
            sampAddChatMessage("[ChaseTracker] Скрипт успешно обновлен до версии " .. new_version .. ". Перезагрузка...", 0x00FF00)
            thisScript():reload()
        end
        
        render_hud.HideCursor = not ui_edit_hud[0]
        
        if chase.active then
            if not sampIsPlayerConnected(chase.id) or sampGetPlayerNickname(chase.id) ~= chase.name then
                resetChase()
                sampAddChatMessage("[ChaseTracker] Цель покинула сервер или сменила ID. Отслеживание завершено.", 0xFF6347)
            end
        end

        if ui_menu[0] and ui_waiting_bind then
            for _, keyVal in pairs(vk) do
                if wasKeyPressed(keyVal) then
                    if keyVal == vk.VK_ESCAPE then
                        settings.main[ui_waiting_bind] = 0
                        ui_waiting_bind = nil
                        saveSettings()
                        break
                    elseif keyVal ~= vk.VK_LBUTTON and keyVal ~= vk.VK_RBUTTON then
                        settings.main[ui_waiting_bind] = keyVal
                        ui_waiting_bind = nil
                        saveSettings()
                        break
                    end
                end
            end
        end

        if ui_menu[0] and ui_isWaitingKey then
            for _, keyVal in pairs(vk) do
                if wasKeyPressed(keyVal) and keyVal ~= vk.VK_LBUTTON and keyVal ~= vk.VK_RBUTTON and keyVal ~= vk.VK_ESCAPE then 
                    ui_currentKey = keyVal
                    ui_isWaitingKey = false
                    break
                end
            end
        end

        if not sampIsChatInputActive() and not sampIsDialogActive() and not isSampfuncsConsoleActive() then
            if wasKeyPressed(vk.VK_RBUTTON) then
                local now = os_clock()
                if now - lastRmbPress < 0.35 then
                    rmbTargetWindow = now + 0.4
                    lastRmbPress = 0
                else
                    lastRmbPress = now
                end
            end

            if rmbTargetWindow > 0 and os_clock() <= rmbTargetWindow then
                local res, targetPed = getCharPlayerIsTargeting(PLAYER_HANDLE)
                if res and targetPed and doesCharExist(targetPed) then
                    local resId, targetId = sampGetPlayerIdByCharHandle(targetPed)
                    if resId and targetId ~= -1 then
                        setTarget(targetId, "Таргет (2x ПКМ)")
                        rmbTargetWindow = 0
                    end
                end
            end

            if not ui_edit_hud[0] and not ui_menu[0] then
                -- Домкрат работает всегда
                if (settings.main.bind_domkrat or 0) ~= 0 and wasKeyPressed(settings.main.bind_domkrat) then 
                    sampSendChat("/domkrat") 
                end

                -- Системные бинды (только во время погони)
                if chase.active then
                    if (settings.main.bind_z or 0) ~= 0 and wasKeyPressed(settings.main.bind_z) then 
                        sampProcessChatInput("/z " .. chase.id) 
                    end
                    
                    if (settings.main.bind_cuff or 0) ~= 0 and wasKeyPressed(settings.main.bind_cuff) then 
                        sampSendChat("/me снял наручники с тактического пояса и резким движением заковал руки подозреваемого")
                        sampProcessChatInput("/cuff " .. chase.id) 
                    end
                    
                    if (settings.main.bind_pull or 0) ~= 0 and wasKeyPressed(settings.main.bind_pull) then 
                        sampSendChat("/me силой открыл дверь транспорта и вытащил подозреваемого наружу")
                        sampProcessChatInput("/pull " .. chase.id) 
                    end
                    
                    if (settings.main.bind_gotome or 0) ~= 0 and wasKeyPressed(settings.main.bind_gotome) then 
                        sampSendChat("/me взял задержанного за заломленную руку и уверенно повел за собой")
                        sampProcessChatInput("/gotome " .. chase.id) 
                    end
                end
                
                -- Кастомные бинды: теперь вынесены из блока chase.active и работают всегда
                for _, bind in ipairs(settings.binds) do
                    if bind.key ~= 0 and wasKeyPressed(bind.key) then
                        local cmdRaw = bind.cmd or ""
                        -- Декодируем команду в кодировку SAMP (CP1251) прямо перед отправкой
                        local cmdToSend = u8:decode(cmdRaw)
                        
                        -- Если бинд содержит {id}, проверяем, есть ли активная цель
                        if cmdToSend:find("{id}") then
                            if chase.active then
                                cmdToSend = cmdToSend:gsub("{id}", tostring(chase.id))
                                sampProcessChatInput(cmdToSend)
                            else
                                sampAddChatMessage("[ChaseTracker] Ошибка: нет активной цели для использования кастомного бинда с {id}!", 0xFF0000)
                            end
                        else
                            -- Обычный бинд без привязки к ID (сработает в любой момент)
                            if #cmdToSend > 0 then
                                sampProcessChatInput(cmdToSend)
                            end
                        end
                    end
                end
            end
        end
    end
end

function setTarget(id, statusText)
    if id and sampIsPlayerConnected(id) then
        chase.active = true
        chase.id = id
        chase.name = sampGetPlayerNickname(chase.id) or "Unknown"
        chase.status = statusText or "Ручной таргет"
        sampAddChatMessage(string_format("[ChaseTracker] Установлена цель: %s [%d]", chase.name, chase.id), 0x00FF00)
    end
end

function resetChase()
    chase.active = false; chase.name = ""; chase.id = -1; chase.status = ""
end

function loadSettings()
    local loaded = inicfg.load(default_cfg, ini_file)
    if not loaded then loaded = default_cfg end
    settings.main = loaded.main or default_cfg.main
    settings.binds = decodeJson(settings.main.binds_data or "[]") or {}
    
    settings.main.hud_x = settings.main.hud_x or default_cfg.main.hud_x
    settings.main.hud_y = settings.main.hud_y or default_cfg.main.hud_y
    settings.main.hud_scale = settings.main.hud_scale or default_cfg.main.hud_scale
    settings.main.arrow_size = settings.main.arrow_size or default_cfg.main.arrow_size
    if settings.main.arrow_anim == nil then settings.main.arrow_anim = default_cfg.main.arrow_anim end

    saveSettings()
    
    cb_show_nick[0] = settings.main.show_nick
    cb_show_id[0] = settings.main.show_id
    cb_show_status[0] = settings.main.show_status
    cb_show_z[0] = settings.main.show_z_timer
    cb_show_arrow[0] = settings.main.show_arrow
    slider_scale[0] = settings.main.hud_scale or 1.0
    
    slider_arrow_size[0] = settings.main.arrow_size
    cb_arrow_anim[0] = settings.main.arrow_anim

    color_z[0] = settings.main.z_color_r; color_z[1] = settings.main.z_color_g; color_z[2] = settings.main.z_color_b; color_z[3] = settings.main.z_color_a
    color_arrow[0] = settings.main.arrow_color_r; color_arrow[1] = settings.main.arrow_color_g; color_arrow[2] = settings.main.arrow_color_b; color_arrow[3] = settings.main.arrow_color_a
    color_text[0] = settings.main.text_color_r; color_text[1] = settings.main.text_color_g; color_text[2] = settings.main.text_color_b; color_text[3] = settings.main.text_color_a
end

function saveSettings()
    settings.main.binds_data = encodeJson(settings.binds)
    inicfg.save({ main = settings.main }, ini_file)
end

function cleanString(str)
    if not str then return "" end
    return str:gsub('%{......%}', '')
end

function sampev.onServerMessage(color, text)
    local cleanText = cleanString(text)
    if cleanText:find("Вы успешно начали погоню за игроком") or cleanText:find("начали отслеживать") or cleanText:find("начали преследование") then
        local name, id = cleanText:match("(%w+_%w+)%s*%[ID:%s*(%d+)%]")
        if not name or not id then
            name, id = cleanText:match("игроком%s+(%w+_%w+).*ID:%s*(%d+)")
        end
        if name and id then 
            chase.active = true; chase.name = name; chase.id = tonumber(id); chase.status = "Погоня (/pursuit)" 
        end
    end
    if cleanText:find("Вы успешно пометили игрока") and cleanText:find("течение") then
        local name = cleanText:match("пометили игрока%s+(.+)%.%s+Если")
        local minutes = cleanText:match("течение%s+(%d+)%s+минут")
        if name and minutes then chase.z_expiry = os_time() + (tonumber(minutes) * 60); chase.z_name = name end
    end
    if cleanText:find("Преследование.*приостановлено") or cleanText:find("отправил%(а%) подозреваемого.*в КПЗ") or cleanText:find("потеряли из виду") or cleanText:find("погоня была прекращена") then 
        resetChase() 
    end
end