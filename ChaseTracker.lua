script_name('ChaseTracker')
script_author('Zhukoff')
script_version('1.6')

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

local cur_version = thisScript().version or '1.6'
local ini_file = 'ChaseTracker'

local update_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/Update.json'
local script_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/ChaseTracker.lua'
local update_path = getWorkingDirectory() .. '\\update_chase.json'
local script_path = thisScript().path

local update_state = "Ожидание проверки..."
local update_available = false
local new_version = ""
local need_reload = false

local hud_themes = {
    [0] = {
        name = u8"Тёмная",
        bg = {0.07, 0.07, 0.08, 0.90},
        text = {0.95, 0.95, 0.95, 1.00},
        arrow = {0.90, 0.25, 0.25, 1.00},
        z_timer = {0.30, 0.85, 0.40, 1.00},
        menu_bg = {0.08, 0.08, 0.10, 0.98},
        menu_title = {0.05, 0.05, 0.06, 1.00},
        menu_active = {0.15, 0.17, 0.22, 1.00},
        button = {0.18, 0.20, 0.26, 1.00}
    },
    [1] = {
        name = u8"Зелёная",
        bg = {0.05, 0.10, 0.06, 0.90},
        text = {0.60, 1.00, 0.60, 1.00},
        arrow = {0.95, 0.40, 0.20, 1.00},
        z_timer = {0.20, 0.90, 0.50, 1.00},
        menu_bg = {0.06, 0.11, 0.07, 0.98},
        menu_title = {0.03, 0.07, 0.04, 1.00},
        menu_active = {0.12, 0.25, 0.15, 1.00},
        button = {0.15, 0.30, 0.18, 1.00}
    },
    [2] = {
        name = u8"Синяя",
        bg = {0.05, 0.08, 0.14, 0.90},
        text = {0.40, 0.90, 1.00, 1.00},
        arrow = {0.30, 0.65, 1.00, 1.00},
        z_timer = {0.10, 0.85, 0.95, 1.00},
        menu_bg = {0.06, 0.09, 0.16, 0.98},
        menu_title = {0.04, 0.06, 0.11, 1.00},
        menu_active = {0.14, 0.22, 0.38, 1.00},
        button = {0.16, 0.28, 0.48, 1.00}
    },
    [3] = {
        name = u8"Фиолетовая",
        bg = {0.11, 0.06, 0.14, 0.90},
        text = {0.95, 0.50, 0.95, 1.00},
        arrow = {0.80, 0.35, 0.95, 1.00},
        z_timer = {0.95, 0.45, 0.75, 1.00},
        menu_bg = {0.12, 0.07, 0.16, 0.98},
        menu_title = {0.07, 0.04, 0.10, 1.00},
        menu_active = {0.26, 0.15, 0.36, 1.00},
        button = {0.32, 0.18, 0.45, 1.00}
    }
}

local default_cfg = {
    main = {
        hud_x = 500, hud_y = 500,
        hud_scale = 1.0, 
        hud_mode = 0,
        hud_theme = 0,
        hud_bg_r = 0.07, hud_bg_g = 0.07, hud_bg_b = 0.08, hud_bg_a = 0.90,
        show_hud = true,
        show_nick = true, show_id = true, show_status = true, show_z_timer = true, show_arrow = true,
        auto_pursuit = false,
        auto_chat_alerts = false,
        arrow_size = 18.0,
        arrow_anim = false,
        z_color_r = 0.30, z_color_g = 0.85, z_color_b = 0.40, z_color_a = 1.0,
        arrow_color_r = 0.90, arrow_color_g = 0.25, arrow_color_b = 0.25, arrow_color_a = 1.0,
        text_color_r = 0.92, text_color_g = 0.92, text_color_b = 0.94, text_color_a = 1.0,
        bind_z = 49,
        bind_cuff = 0,
        bind_pull = 0,
        bind_gotome = 0,
        bind_domkrat = 53,
        binds_data = "[]"
    },
    rp = {
        cuff = "/me снял наручники с тактического пояса и резким движением заковал руки подозреваемого",
        pull = "/me силой открыл дверь транспорта и вытащил подозреваемого наружу",
        gotome = "/me взял задержанного за заломленную руку и уверенно повел за собой"
    }
}
local settings = { main = {}, binds = {}, rp = {} }

local chase = {
    active = false, name = "", id = -1, status = "", z_expiry = 0, z_name = "",
    alert_60_sent = false, alert_30_sent = false, alert_10_sent = false, alert_0_sent = false,
    sx = nil, sy = nil, sz = nil
}

local ui_menu = imgui.new.bool(false)
local ui_edit_hud = imgui.new.bool(false)
local ui_inputCmd = imgui.new.char[256]()
local ui_currentKey = 0
local ui_isWaitingKey = false
local ui_waiting_bind = nil 

local combo_hud_mode = imgui.new.int(default_cfg.main.hud_mode)
local combo_hud_theme = imgui.new.int(default_cfg.main.hud_theme)

local cb_show_hud = imgui.new.bool(default_cfg.main.show_hud)
local cb_show_nick = imgui.new.bool(default_cfg.main.show_nick)
local cb_show_id = imgui.new.bool(default_cfg.main.show_id)
local cb_show_status = imgui.new.bool(default_cfg.main.show_status)
local cb_show_z = imgui.new.bool(default_cfg.main.show_z_timer)
local cb_show_arrow = imgui.new.bool(default_cfg.main.show_arrow)
local cb_auto_pursuit = imgui.new.bool(default_cfg.main.auto_pursuit)
local cb_auto_chat_alerts = imgui.new.bool(default_cfg.main.auto_chat_alerts)

local slider_arrow_size = imgui.new.float[1](default_cfg.main.arrow_size)
local cb_arrow_anim = imgui.new.bool(default_cfg.main.arrow_anim)

local color_hud_bg = imgui.new.float[4](default_cfg.main.hud_bg_r, default_cfg.main.hud_bg_g, default_cfg.main.hud_bg_b, default_cfg.main.hud_bg_a)
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

function sendTripleAlert(text)
    for i = 1, 3 do
        sampAddChatMessage("[ChaseTracker] " .. text, 0xFF6347)
    end
end

function applyTheme(theme_id)
    local t = hud_themes[theme_id] or hud_themes[0]
    
    color_hud_bg[0], color_hud_bg[1], color_hud_bg[2], color_hud_bg[3] = t.bg[1], t.bg[2], t.bg[3], t.bg[4]
    color_text[0], color_text[1], color_text[2], color_text[3] = t.text[1], t.text[2], t.text[3], t.text[4]
    color_arrow[0], color_arrow[1], color_arrow[2], color_arrow[3] = t.arrow[1], t.arrow[2], t.arrow[3], t.arrow[4]
    color_z[0], color_z[1], color_z[2], color_z[3] = t.z_timer[1], t.z_timer[2], t.z_timer[3], t.z_timer[4]
    
    settings.main.hud_bg_r, settings.main.hud_bg_g, settings.main.hud_bg_b, settings.main.hud_bg_a = t.bg[1], t.bg[2], t.bg[3], t.bg[4]
    settings.main.text_color_r, settings.main.text_color_g, settings.main.text_color_b, settings.main.text_color_a = t.text[1], t.text[2], t.text[3], t.text[4]
    settings.main.arrow_color_r, settings.main.arrow_color_g, settings.main.arrow_color_b, settings.main.arrow_color_a = t.arrow[1], t.arrow[2], t.arrow[3], t.arrow[4]
    settings.main.z_color_r, settings.main.z_color_g, settings.main.z_color_b, settings.main.z_color_a = t.z_timer[1], t.z_timer[2], t.z_timer[3], t.z_timer[4]
    
    local style = imgui.GetStyle()
    local colors = style.Colors
    colors[imgui.Col.WindowBg]      = imgui.ImVec4(t.menu_bg[1], t.menu_bg[2], t.menu_bg[3], t.menu_bg[4])
    colors[imgui.Col.TitleBg]       = imgui.ImVec4(t.menu_title[1], t.menu_title[2], t.menu_title[3], t.menu_title[4])
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(t.menu_active[1], t.menu_active[2], t.menu_active[3], t.menu_active[4])
    colors[imgui.Col.Button]        = imgui.ImVec4(t.button[1], t.button[2], t.button[3], t.button[4])
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(t.button[1] + 0.08, t.button[2] + 0.08, t.button[3] + 0.08, 1.00)
    colors[imgui.Col.ButtonActive]  = imgui.ImVec4(t.button[1] + 0.15, t.button[2] + 0.15, t.button[3] + 0.15, 1.00)
    
    settings.main.hud_theme = theme_id
    saveSettings()
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
    
    style.WindowRounding = 8.0
    style.FrameRounding = 5.0
    style.PopupRounding = 5.0
    style.ScrollbarRounding = 5.0
    style.ChildRounding = 6.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.FramePadding = imgui.ImVec2(8, 5)
    style.ItemSpacing = imgui.ImVec2(8, 8)

    colors[imgui.Col.ChildBg]         = imgui.ImVec4(0.10, 0.10, 0.12, 0.60)
    colors[imgui.Col.FrameBg]         = imgui.ImVec4(0.13, 0.14, 0.18, 1.00)
    colors[imgui.Col.FrameBgHovered]  = imgui.ImVec4(0.20, 0.22, 0.28, 1.00)
    colors[imgui.Col.FrameBgActive]   = imgui.ImVec4(0.28, 0.30, 0.38, 1.00)
    colors[imgui.Col.CheckMark]       = imgui.ImVec4(0.40, 0.75, 1.00, 1.00)
    colors[imgui.Col.SliderGrab]      = imgui.ImVec4(0.40, 0.75, 1.00, 0.80)
    colors[imgui.Col.SliderGrabActive]= imgui.ImVec4(0.40, 0.75, 1.00, 1.00)
    colors[imgui.Col.Text]            = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[imgui.Col.Tab]             = imgui.ImVec4(0.10, 0.11, 0.15, 1.00)
    colors[imgui.Col.TabHovered]      = imgui.ImVec4(0.24, 0.27, 0.36, 1.00)
    colors[imgui.Col.TabActive]       = imgui.ImVec4(0.20, 0.22, 0.30, 1.00)
    colors[imgui.Col.Separator]       = imgui.ImVec4(0.20, 0.22, 0.28, 0.60)
    
    applyTheme(settings.main.hud_theme or 0)
end)

local function draw_sys_bind(label, bind_key_name)
    imgui.Text(u8(label))
    imgui.SameLine(160)
    local current_key = settings.main[bind_key_name] or 0
    local btn_text = (ui_waiting_bind == bind_key_name) and u8"ЖДЕМ НАЖАТИЯ (ESC - СБРОС)" or (current_key == 0 and u8"НЕ НАЗНАЧЕНО" or u8(getKeyName(current_key)))
    if imgui.Button(btn_text .. "##" .. bind_key_name, imgui.ImVec2(-1, 26)) then
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
    imgui.SetNextWindowSize(imgui.ImVec2(620, 580), imgui.Cond.FirstUseEver)
    
    if imgui.Begin(u8"ChaseTracker", ui_menu, imgui.WindowFlags.NoCollapse) then
        if imgui.BeginTabBar("Tabs") then
            
            if imgui.BeginTabItem(u8"Настройки HUD") then
                imgui.BeginChild("HudSettingsChild", imgui.ImVec2(0, -45), true)
                
                if imgui.Checkbox(u8"Отображать окно HUD", cb_show_hud) then 
                    settings.main.show_hud = cb_show_hud[0] 
                    saveSettings() 
                end
                
                imgui.Separator()
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Режим настройки интерфейса:")
                if imgui.Button(combo_hud_mode[0] == 0 and u8"Простой режим" or u8"Простой режим", imgui.ImVec2(230, 28)) then
                    combo_hud_mode[0] = 0
                    settings.main.hud_mode = 0
                    applyTheme(combo_hud_theme[0])
                end
                imgui.SameLine()
                if imgui.Button(combo_hud_mode[0] == 1 and u8"Расширенный режим" or u8"Расширенный режим", imgui.ImVec2(240, 28)) then
                    combo_hud_mode[0] = 1
                    settings.main.hud_mode = 1
                    saveSettings()
                end
                
                imgui.Separator()
                
                if combo_hud_mode[0] == 0 then
                    imgui.Text(u8"Выберите готовую тему оформления")
                    imgui.PushItemWidth(250)
                    if imgui.BeginCombo(u8"##ThemeCombo", hud_themes[combo_hud_theme[0]].name) then
                        for i = 0, 3 do
                            local is_selected = (combo_hud_theme[0] == i)
                            if imgui.Selectable(hud_themes[i].name, is_selected) then
                                combo_hud_theme[0] = i
                                applyTheme(i)
                            end
                            if is_selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                else
                    imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.3, 1.0), u8"Ручная настройка палитры (ползунок 'A' отвечает за прозрачность):")
                    if imgui.ColorEdit4(u8"Фон окна HUD", color_hud_bg) then
                        settings.main.hud_bg_r, settings.main.hud_bg_g, settings.main.hud_bg_b, settings.main.hud_bg_a = color_hud_bg[0], color_hud_bg[1], color_hud_bg[2], color_hud_bg[3]; saveSettings()
                    end
                    if imgui.ColorEdit4(u8"Основной текст", color_text) then
                        settings.main.text_color_r, settings.main.text_color_g, settings.main.text_color_b, settings.main.text_color_a = color_text[0], color_text[1], color_text[2], color_text[3]; saveSettings()
                    end
                    if imgui.ColorEdit4(u8"Текст и таймер /z", color_z) then
                        settings.main.z_color_r, settings.main.z_color_g, settings.main.z_color_b, settings.main.z_color_a = color_z[0], color_z[1], color_z[2], color_z[3]; saveSettings()
                    end
                    if imgui.ColorEdit4(u8"3D-маркер", color_arrow) then
                        settings.main.arrow_color_r, settings.main.arrow_color_g, settings.main.arrow_color_b, settings.main.arrow_color_a = color_arrow[0], color_arrow[1], color_arrow[2], color_arrow[3]; saveSettings()
                    end
                end
                
                imgui.Separator()
                
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Отображаемые элементы:")
                if imgui.Checkbox(u8"Ник цели", cb_show_nick) then settings.main.show_nick = cb_show_nick[0] saveSettings() end
                imgui.SameLine(150)
                if imgui.Checkbox(u8"ID игрока", cb_show_id) then settings.main.show_id = cb_show_id[0] saveSettings() end
                imgui.SameLine(280)
                if imgui.Checkbox(u8"Статус погони", cb_show_status) then settings.main.show_status = cb_show_status[0] saveSettings() end
                
                if imgui.Checkbox(u8"Таймер /z", cb_show_z) then settings.main.show_z_timer = cb_show_z[0] saveSettings() end
                imgui.SameLine(150)
                if imgui.Checkbox(u8"Маркер", cb_show_arrow) then settings.main.show_arrow = cb_show_arrow[0] saveSettings() end
                imgui.SameLine(280)
                if imgui.Checkbox(u8"Анимация маркера", cb_arrow_anim) then settings.main.arrow_anim = cb_arrow_anim[0] saveSettings() end
                
                imgui.Separator()
                
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Размеры и масштаб:")
                imgui.PushItemWidth(250)
                if imgui.SliderFloat(u8"Масштаб окна HUD", slider_scale, 0.5, 2.5) then settings.main.hud_scale = slider_scale[0] saveSettings() end
                if imgui.SliderFloat(u8"Размер 3D-маркера", slider_arrow_size, 5.0, 50.0) then settings.main.arrow_size = slider_arrow_size[0] saveSettings() end
                imgui.PopItemWidth()
                
                imgui.EndChild()
                
                if imgui.Button(ui_edit_hud[0] and u8"СОХРАНИТЬ ПОЗИЦИЮ HUD" or u8"ПЕРЕМЕСТИТЬ ОКНО HUD", imgui.ImVec2(-1, 35)) then
                    ui_edit_hud[0] = not ui_edit_hud[0]
                end
                
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Основные настройки") then
                imgui.BeginChild("MainSettingsChild", imgui.ImVec2(0, -10), true)
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Автоматизация сервера:")
                if imgui.Checkbox(u8"Автоматически начинать преследование при выдаче розыска", cb_auto_pursuit) then 
                    settings.main.auto_pursuit = cb_auto_pursuit[0] 
                    saveSettings() 
                end
                if imgui.Checkbox(u8"Авто-оповещение в чат о таймере /z", cb_auto_chat_alerts) then 
                    settings.main.auto_chat_alerts = cb_auto_chat_alerts[0] 
                    saveSettings() 
                end
                
                imgui.Separator()
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Управление позицией HUD:")
                if imgui.Button(ui_edit_hud[0] and u8"Завершить редактирование позиции" or u8"Разблокировать перемещение HUD на экране", imgui.ImVec2(-1, 35)) then
                    ui_edit_hud[0] = not ui_edit_hud[0]
                end
                imgui.EndChild()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Системные Бинды") then
                imgui.BeginChild("BindsChild", imgui.ImVec2(0, -10), true)
                imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1.0), u8"Нажмите на кнопку, чтобы назначить клавишу. Нажмите ESC для сброса.")
                imgui.Separator()
                draw_sys_bind("/z", "bind_z")
                draw_sys_bind("/cuff", "bind_cuff")
                draw_sys_bind("/gotome", "bind_gotome")
                draw_sys_bind("/pull", "bind_pull")
                imgui.Separator()
                draw_sys_bind("/domkrat", "bind_domkrat")
                imgui.EndChild()
                imgui.EndTabItem()
            end
            
            if imgui.BeginTabItem(u8"Свои Команды") then
                imgui.BeginChild("CustomCmdsChild", imgui.ImVec2(0, -10), true)
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"Добавление пользовательского бинда:")
                imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1.0), u8"Используйте тег {id}, чтобы автоматически подставлять ID текущей цели погони.")
                
                imgui.PushItemWidth(310)
                imgui.InputTextWithHint("##cmd", u8"Например: /su {id} 3 Неподчинение", ui_inputCmd, 256)
                imgui.PopItemWidth()
                imgui.SameLine()
                
                local keyName = (ui_isWaitingKey) and u8"ЖДУ..." or (ui_currentKey == 0 and u8"КЛАВИША" or u8(getKeyName(ui_currentKey)))
                if imgui.Button(keyName, imgui.ImVec2(100, 26)) then ui_isWaitingKey = true end
                imgui.SameLine()
                
                if imgui.Button(u8"ДОБАВИТЬ", imgui.ImVec2(-1, 26)) then
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
                        imgui.TextColored(imgui.ImVec4(0.4, 0.85, 0.4, 1), "[" .. getKeyName(bind.key or 0) .. "]")
                        imgui.SameLine()
                        imgui.Text(tostring(bind.cmd or "Error"))
                        
                        imgui.SameLine(imgui.GetContentRegionAvail().x - 70) 
                        if imgui.Button(u8"Удалить", imgui.ImVec2(70, 22)) then
                            table.remove(settings.binds, i)
                            saveSettings()
                        end
                        imgui.PopID()
                    end
                imgui.EndChild()
                imgui.EndChild()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Информация") then
                imgui.BeginChild("InfoChild", imgui.ImVec2(0, -10), true)
                imgui.TextColored(imgui.ImVec4(0.4, 0.75, 1.0, 1.0), u8"ChaseTracker - Умный помощник для погонь")
                imgui.Text(u8"Автор: Zhukoff")
                imgui.Text(u8"Версия скрипта: " .. cur_version)
                imgui.Separator()
                imgui.Text(u8"Быстрые команды чата:")
                imgui.BulletText(u8"/chase - Открыть меню настроек")
                imgui.BulletText(u8"/trg [ID] - Установить ручную цель (без ID сброс)")
                imgui.BulletText(u8"/pursuit [ID] - Начать погоню и захватить цель")
                imgui.BulletText(u8"Двойной клик ПКМ по игроку - Быстрый захват цели в прицеле")
                
                imgui.Separator()
                imgui.Text(u8"Статус обновлений: " .. u8(update_state))
                
                if imgui.Button(u8"Проверить обновления", imgui.ImVec2(-1, 35)) then
                    check_update()
                end
                
                if update_available then
                    if imgui.Button(u8"Установить обновление", imgui.ImVec2(-1, 35)) then
                        perform_update()
                        update_available = false
                    end
                end

                imgui.EndChild()
                imgui.EndTabItem()
            end
            
            imgui.EndTabBar()
        end
    end
    imgui.End()
end)

local render_hud = imgui.OnFrame(function() return (chase.active and settings.main.show_hud) or ui_edit_hud[0] end, function(player)
    local flags = bit.bor(imgui.WindowFlags.NoTitleBar, imgui.WindowFlags.NoResize, imgui.WindowFlags.NoCollapse, 
                          imgui.WindowFlags.AlwaysAutoResize, imgui.WindowFlags.NoFocusOnAppearing, imgui.WindowFlags.NoBringToFrontOnFocus)
    
    if not ui_edit_hud[0] then
        flags = bit.bor(flags, imgui.WindowFlags.NoMove, imgui.WindowFlags.NoInputs)
    end

    imgui.SetNextWindowPos(imgui.ImVec2(settings.main.hud_x, settings.main.hud_y), imgui.Cond.FirstUseEver)
    
    local bg_col = imgui.ImVec4(color_hud_bg[0], color_hud_bg[1], color_hud_bg[2], color_hud_bg[3])
    local text_col = imgui.ImVec4(color_text[0], color_text[1], color_text[2], color_text[3])
    local arrow_col = {color_arrow[0], color_arrow[1], color_arrow[2], color_arrow[3]}
    local z_col = imgui.ImVec4(color_z[0], color_z[1], color_z[2], color_z[3])
    
    imgui.PushStyleColor(imgui.Col.WindowBg, bg_col)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
    
    if imgui.Begin("ChaseHUD", nil, flags) then
        if ui_edit_hud[0] then
            local pos = imgui.GetWindowPos()
            settings.main.hud_x = pos.x
            settings.main.hud_y = pos.y
            imgui.TextColored(imgui.ImVec4(1, 0.8, 0.2, 1), u8"РЕЖИМ РЕДАКТИРОВАНИЯ (Перетаскивайте окно)")
        end

        imgui.SetWindowFontScale(settings.main.hud_scale)

        if settings.main.show_nick then imgui.TextColored(text_col, u8("Цель: " .. tostring(chase.name or ""))) end
        if settings.main.show_id then imgui.TextColored(text_col, u8("ID: " .. tostring(chase.id or -1))) end
        if settings.main.show_status then 
            local st = (chase.status == nil or chase.status == "") and "Активна" or chase.status
            imgui.TextColored(text_col, u8("Статус: " .. tostring(st))) 
        end
        
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
            imgui.TextColored(z_col, u8("Таймер /z: " .. zText))
        end

        if chase.active and settings.main.show_arrow and sampIsPlayerConnected(chase.id) then
            local _, ped = sampGetCharHandleBySampPlayerId(chase.id)
            if ped and doesCharExist(ped) and isCharOnScreen(ped) then
                local px, py, pz = getCharCoordinates(ped)
                
                if not chase.sx then 
                    chase.sx, chase.sy, chase.sz = px, py, pz 
                else
                    chase.sx = chase.sx + (px - chase.sx) * 0.15
                    chase.sy = chase.sy + (py - chase.sy) * 0.15
                    chase.sz = chase.sz + (pz - chase.sz) * 0.15
                end

                local cx, cy, cz = getActiveCameraCoordinates()
                if isLineOfSightClear(cx, cy, cz, px, py, pz + 0.8, true, false, false, true, false, false, false) then
                    local draw_list = imgui.GetBackgroundDrawList()
                    local r, g, b, a = arrow_col[1], arrow_col[2], arrow_col[3], arrow_col[4]
                    
                    local fill_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r * 0.6, g * 0.6, b * 0.6, a * 0.5))
                    local edge_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a))
                    
                    local size = (settings.main.arrow_size or 18.0) / 40.0
                    local rot = os_clock() * 3.0
                    local hover = settings.main.arrow_anim and (math_sin(os_clock() * 5.0) * 0.15) or 0
                    
                    local mx, my, mz = chase.sx, chase.sy, chase.sz + 1.2 + hover
                    
                    local bw = size * 0.5
                    local p1 = {mx, my, mz - size}
                    local p2 = {mx + math.cos(rot) * bw, my + math.sin(rot) * bw, mz + size * 0.5}
                    local p3 = {mx + math.cos(rot + 1.5708) * bw, my + math.sin(rot + 1.5708) * bw, mz + size * 0.5}
                    local p4 = {mx + math.cos(rot + 3.1415) * bw, my + math.sin(rot + 3.1415) * bw, mz + size * 0.5}
                    local p5 = {mx + math.cos(rot + 4.7123) * bw, my + math.sin(rot + 4.7123) * bw, mz + size * 0.5}
                    local p6 = {mx, my, mz + size * 1.5}
                    
                    local function w2s(x, y, z)
                        local sx, sy = convert3DCoordsToScreen(x, y, z)
                        return (sx and sy) and imgui.ImVec2(sx, sy) or nil
                    end
                    
                    local sp1 = w2s(p1[1], p1[2], p1[3])
                    local sp2 = w2s(p2[1], p2[2], p2[3])
                    local sp3 = w2s(p3[1], p3[2], p3[3])
                    local sp4 = w2s(p4[1], p4[2], p4[3])
                    local sp5 = w2s(p5[1], p5[2], p5[3])
                    local sp6 = w2s(p6[1], p6[2], p6[3])
                    
                    local function drawFace(pA, pB, pC)
                        if (pB.x - pA.x) * (pC.y - pA.y) - (pB.y - pA.y) * (pC.x - pA.x) > 0 then
                            draw_list:AddTriangleFilled(pA, pB, pC, fill_col)
                            draw_list:AddTriangle(pA, pB, pC, edge_col, 1.5)
                        end
                    end
                    
                    if sp1 and sp2 and sp3 and sp4 and sp5 and sp6 then
                        drawFace(sp1, sp3, sp2)
                        drawFace(sp1, sp4, sp3)
                        drawFace(sp1, sp5, sp4)
                        drawFace(sp1, sp2, sp5)
                        drawFace(sp6, sp2, sp3)
                        drawFace(sp6, sp3, sp4)
                        drawFace(sp6, sp4, sp5)
                        drawFace(sp6, sp5, sp2)
                    end
                end
            else
                chase.sx = nil 
            end
        else
            chase.sx = nil
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
            
            if settings.main.auto_chat_alerts and chase.z_expiry > 0 and chase.name == chase.z_name then
                local timeLeft = chase.z_expiry - os_time()
                if timeLeft == 60 and not chase.alert_60_sent then
                    sendTripleAlert("Метка /z с подозреваемого спадет через 1 минуту!")
                    chase.alert_60_sent = true
                elseif timeLeft == 30 and not chase.alert_30_sent then
                    sendTripleAlert("Метка /z с подозреваемого спадет через 30 секунд!")
                    chase.alert_30_sent = true
                elseif timeLeft == 10 and not chase.alert_10_sent then
                    sendTripleAlert("Метка /z с подозреваемого спадет через 10 секунд!")
                    chase.alert_10_sent = true
                elseif timeLeft <= 0 and not chase.alert_0_sent then
                    sendTripleAlert("ВНИМАНИЕ! Метка /z с подозреваемого СПАЛА!")
                    chase.alert_0_sent = true
                end
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
                if (settings.main.bind_domkrat or 0) ~= 0 and wasKeyPressed(settings.main.bind_domkrat) then 
                    sampSendChat("/domkrat") 
                end

                if chase.active then
                    if (settings.main.bind_z or 0) ~= 0 and wasKeyPressed(settings.main.bind_z) then 
                        sampProcessChatInput("/z " .. chase.id) 
                    end
                    
                    if (settings.main.bind_cuff or 0) ~= 0 and wasKeyPressed(settings.main.bind_cuff) then 
                        if settings.rp.cuff and settings.rp.cuff ~= "" then 
                            sampSendChat(settings.rp.cuff) 
                        end
                        sampProcessChatInput("/cuff " .. chase.id) 
                    end
                    
                    if (settings.main.bind_pull or 0) ~= 0 and wasKeyPressed(settings.main.bind_pull) then 
                        if settings.rp.pull and settings.rp.pull ~= "" then 
                            sampSendChat(settings.rp.pull) 
                        end
                        sampProcessChatInput("/pull " .. chase.id) 
                    end
                    
                    if (settings.main.bind_gotome or 0) ~= 0 and wasKeyPressed(settings.main.bind_gotome) then 
                        if settings.rp.gotome and settings.rp.gotome ~= "" then 
                            sampSendChat(settings.rp.gotome) 
                        end
                        sampProcessChatInput("/gotome " .. chase.id) 
                    end
                end
                
                for _, bind in ipairs(settings.binds) do
                    if bind.key ~= 0 and wasKeyPressed(bind.key) then
                        local cmdRaw = bind.cmd or ""
                        local cmdToSend = u8:decode(cmdRaw)
                        
                        if cmdToSend:find("{id}") then
                            if chase.active then
                                cmdToSend = cmdToSend:gsub("{id}", tostring(chase.id))
                                sampProcessChatInput(cmdToSend)
                            else
                                sampAddChatMessage("[ChaseTracker] Ошибка: нет активной цели для использования кастомного бинда с {id}!", 0xFF0000)
                            end
                        else
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
    chase.alert_60_sent = false; chase.alert_30_sent = false; chase.alert_10_sent = false; chase.alert_0_sent = false
    chase.sx = nil; chase.sy = nil; chase.sz = nil
end

function loadSettings()
    local loaded = inicfg.load(default_cfg, ini_file)
    if not loaded then loaded = default_cfg end
    settings.main = loaded.main or default_cfg.main
    settings.rp = loaded.rp or default_cfg.rp
    settings.binds = decodeJson(settings.main.binds_data or "[]") or {}
    
    settings.main.hud_x = settings.main.hud_x or default_cfg.main.hud_x
    settings.main.hud_y = settings.main.hud_y or default_cfg.main.hud_y
    settings.main.hud_scale = settings.main.hud_scale or default_cfg.main.hud_scale
    settings.main.arrow_size = settings.main.arrow_size or default_cfg.main.arrow_size
    settings.main.hud_mode = settings.main.hud_mode or default_cfg.main.hud_mode
    settings.main.hud_theme = settings.main.hud_theme or default_cfg.main.hud_theme
    
    if settings.main.show_hud == nil then settings.main.show_hud = default_cfg.main.show_hud end
    if settings.main.arrow_anim == nil then settings.main.arrow_anim = default_cfg.main.arrow_anim end
    if settings.main.auto_pursuit == nil then settings.main.auto_pursuit = default_cfg.main.auto_pursuit end
    if settings.main.auto_chat_alerts == nil then settings.main.auto_chat_alerts = default_cfg.main.auto_chat_alerts end

    saveSettings()
    
    combo_hud_mode[0] = settings.main.hud_mode
    combo_hud_theme[0] = settings.main.hud_theme
    
    cb_show_hud[0] = settings.main.show_hud
    cb_show_nick[0] = settings.main.show_nick
    cb_show_id[0] = settings.main.show_id
    cb_show_status[0] = settings.main.show_status
    cb_show_z[0] = settings.main.show_z_timer
    cb_show_arrow[0] = settings.main.show_arrow
    cb_auto_pursuit[0] = settings.main.auto_pursuit
    cb_auto_chat_alerts[0] = settings.main.auto_chat_alerts
    slider_scale[0] = settings.main.hud_scale or 1.0
    
    slider_arrow_size[0] = settings.main.arrow_size
    cb_arrow_anim[0] = settings.main.arrow_anim

    if settings.main.hud_mode == 0 then
        applyTheme(settings.main.hud_theme)
    else
        color_hud_bg[0] = settings.main.hud_bg_r or 0.07; color_hud_bg[1] = settings.main.hud_bg_g or 0.07; color_hud_bg[2] = settings.main.hud_bg_b or 0.08; color_hud_bg[3] = settings.main.hud_bg_a or 0.90
        color_z[0] = settings.main.z_color_r; color_z[1] = settings.main.z_color_g; color_z[2] = settings.main.z_color_b; color_z[3] = settings.main.z_color_a
        color_arrow[0] = settings.main.arrow_color_r; color_arrow[1] = settings.main.arrow_color_g; color_arrow[2] = settings.main.arrow_color_b; color_arrow[3] = settings.main.arrow_color_a
        color_text[0] = settings.main.text_color_r; color_text[1] = settings.main.text_color_g; color_text[2] = settings.main.text_color_b; color_text[3] = settings.main.text_color_a
    end
end

function saveSettings()
    settings.main.binds_data = encodeJson(settings.binds)
    inicfg.save({ main = settings.main, rp = settings.rp }, ini_file)
end

function cleanString(str)
    if not str then return "" end
    return str:gsub('%{......%}', '')
end

function sampev.onSendCommand(cmd)
    if settings.main.auto_pursuit then
        local id = cmd:match("^%s*/?[sS][uU]%s+(%d+)")
        if id then
            local numId = tonumber(id)
            if numId and sampIsPlayerConnected(numId) then
                lua_thread.create(function()
                    wait(1500)
                    if sampIsPlayerConnected(numId) then
                        sampProcessChatInput("/pursuit " .. numId)
                    end
                end)
            end
        end
    end
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
        if name and minutes then 
            chase.z_expiry = os_time() + (tonumber(minutes) * 60)
            chase.z_name = name 
            chase.alert_60_sent = false; chase.alert_30_sent = false; chase.alert_10_sent = false; chase.alert_0_sent = false
        end
    end
    
    if cleanText:find("Преследование.*приостановлено") or cleanText:find("отправил%(а%) подозреваемого.*в КПЗ") or cleanText:find("потеряли из виду") or cleanText:find("погоня была прекращена") then 
        resetChase() 
    end

    if settings.main.auto_pursuit then
        if cleanText:find("%[Розыск%]") and cleanText:find("Обвинитель:") then
            local targetId, accuserName = cleanText:match("%[Розыск%]%s+[%w_]+%[(%d+)%].*Обвинитель:%s+([%w_]+)")
            if targetId and accuserName then
                local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED) 
                if res then
                    local myName = sampGetPlayerNickname(myId)
                    if accuserName == myName then
                        local numId = tonumber(targetId)
                        if numId and sampIsPlayerConnected(numId) then
                            lua_thread.create(function()
                                wait(1500)
                                if sampIsPlayerConnected(numId) then
                                    sampProcessChatInput("/pursuit " .. numId)
                                end
                            end)
                        end
                    end
                end
            end
        end
    end
end