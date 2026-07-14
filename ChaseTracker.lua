script_name('ChaseTracker')
script_author('Zhukoff Kevin_Zhukoff [Yuma]')
script_version('1.1')

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

local cur_version = '1.0'
local update_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/Update.json'
local script_url = 'https://raw.githubusercontent.com/Zhukoff42/ChaseTracker/main/ChaseTracker.lua'
local update_path = getWorkingDirectory() .. '/update_chase.json'
local script_path = thisScript().path

local update_state = "Îæèäàíèå ïðîâåðêè..."
local update_available = false
local new_version = ""

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

function getKeyName(id)
    if not id or id == 0 then return "ÍÅ ÍÀÇÍÀ×ÅÍÎ" end
    return keys[id] or tostring(id)
end

function check_update()
    update_state = "Ïðîâåðêà îáíîâëåíèé..."
    downloadUrlToFile(update_url, update_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            local file = io.open(update_path, "r")
            if file then
                local content = file:read("*a")
                file:close()
                os.remove(update_path)
                local data = decodeJson(content)
                if data and data.version then
                    if data.version ~= cur_version then
                        update_available = true
                        new_version = data.version
                        update_state = "Äîñòóïíî îáíîâëåíèå: v" .. new_version
                    else
                        update_state = "Ó âàñ óñòàíîâëåíà ïîñëåäíÿÿ âåðñèÿ."
                    end
                else
                    update_state = "Îøèáêà ïàðñèíãà Update.json"
                end
            end
        elseif status == dlstatus.STATUS_ENDDOWNLOADDATA then
            update_state = "Îøèáêà ñêà÷èâàíèÿ ôàéëà ïðîâåðêè."
        end
    end)
end

function perform_update()
    update_state = "Ñêà÷èâàíèå îáíîâëåíèÿ..."
    downloadUrlToFile(script_url, script_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            update_state = "Îáíîâëåíèå çàâåðøåíî! Ïåðåçàãðóçêà..."
            sampAddChatMessage("[ChaseTracker] Ñêðèïò îáíîâëåí äî âåðñèè " .. new_version .. ". Ïåðåçàãðóçêà...", 0x00FF00)
            thisScript():reload()
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
    local btn_text = (ui_waiting_bind == bind_key_name) and u8"ÆÄÅÌ ÍÀÆÀÒÈß (ESC - ÑÁÐÎÑ)" or (current_key == 0 and u8"ÍÅ ÍÀÇÍÀ×ÅÍÎ" or u8(getKeyName(current_key)))
    if imgui.Button(btn_text .. "##" .. bind_key_name, imgui.ImVec2(-1, 25)) then
        ui_waiting_bind = bind_key_name
    end
end

local render_menu = imgui.OnFrame(function() return ui_menu[0] end, function(player)
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(550, 520), imgui.Cond.FirstUseEver)
    
    if imgui.Begin(u8"Íàñòðîéêè ChaseTracker (Kevin_Zhukoff [Yuma])", ui_menu, imgui.WindowFlags.NoCollapse) then
        if imgui.BeginTabBar("Tabs") then
            
            if imgui.BeginTabItem(u8"Âíåøíèé âèä HUD") then
                imgui.Text(u8"Ýëåìåíòû íà ýêðàíå:")
                if imgui.Checkbox(u8"Ïîêàçûâàòü Íèê", cb_show_nick) then settings.main.show_nick = cb_show_nick[0] saveSettings() end
                if imgui.Checkbox(u8"Ïîêàçûâàòü ID", cb_show_id) then settings.main.show_id = cb_show_id[0] saveSettings() end
                if imgui.Checkbox(u8"Ïîêàçûâàòü Ñòàòóñ", cb_show_status) then settings.main.show_status = cb_show_status[0] saveSettings() end
                if imgui.Checkbox(u8"Ïîêàçûâàòü Òàéìåð /z", cb_show_z) then settings.main.show_z_timer = cb_show_z[0] saveSettings() end
                
                imgui.Separator()
                imgui.Text(u8"Òåêñò è Öâåòà:")
                if imgui.SliderFloat(u8"Ðàçìåð òåêñòà (Scale)", slider_scale, 0.5, 3.0) then settings.main.hud_scale = slider_scale[0] saveSettings() end
                if imgui.ColorEdit4(u8"Öâåò îñíîâíîãî òåêñòà", color_text) then
                    settings.main.text_color_r = color_text[0]; settings.main.text_color_g = color_text[1]; settings.main.text_color_b = color_text[2]; settings.main.text_color_a = color_text[3]; saveSettings()
                end
                if imgui.ColorEdit4(u8"Öâåò òàéìåðà /z", color_z) then
                    settings.main.z_color_r = color_z[0]; settings.main.z_color_g = color_z[1]; settings.main.z_color_b = color_z[2]; settings.main.z_color_a = color_z[3]; saveSettings()
                end
                
                imgui.Separator()
                imgui.Text(u8"Ñòðåëêà íàä ãîëîâîé:")
                if imgui.Checkbox(u8"Âêëþ÷èòü ìàðêåð íàä öåëüþ", cb_show_arrow) then settings.main.show_arrow = cb_show_arrow[0] saveSettings() end
                if imgui.Checkbox(u8"Àíèìàöèÿ (ïëàâàåò ââåðõ-âíèç)", cb_arrow_anim) then settings.main.arrow_anim = cb_arrow_anim[0] saveSettings() end
                if imgui.SliderFloat(u8"Ðàçìåð ìàðêåðà", slider_arrow_size, 5.0, 50.0) then settings.main.arrow_size = slider_arrow_size[0] saveSettings() end
                
                if imgui.ColorEdit4(u8"Öâåò ìàðêåðà", color_arrow) then
                    settings.main.arrow_color_r = color_arrow[0]; settings.main.arrow_color_g = color_arrow[1]; settings.main.arrow_color_b = color_arrow[2]; settings.main.arrow_color_a = color_arrow[3]; saveSettings()
                end
                
                imgui.Separator()
                if imgui.Button(ui_edit_hud[0] and u8"ÑÎÕÐÀÍÈÒÜ ÏÎÇÈÖÈÞ HUD" or u8"ÏÅÐÅÌÅÑÒÈÒÜ HUD", imgui.ImVec2(-1, 40)) then
                    ui_edit_hud[0] = not ui_edit_hud[0]
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Ñèñòåìíûå Áèíäû") then
                imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1), u8"Íàæìèòå íà êíîïêó, ÷òîáû íàçíà÷èòü êëàâèøó. Íàæìèòå ESC äëÿ ñáðîñà.")
                imgui.Separator()
                draw_sys_bind("/z", "bind_z")
                draw_sys_bind("/cuff", "bind_cuff")
                draw_sys_bind("/gotome", "bind_gotome")
                draw_sys_bind("/pull", "bind_pull")
                imgui.Separator()
                draw_sys_bind("/domkrat", "bind_domkrat")
                
                imgui.EndTabItem()
            end
            
            if imgui.BeginTabItem(u8"Ñâîè Êîìàíäû") then
                imgui.Text(u8"Äîáàâèòü êàñòîìíûé áèíä:")
                imgui.PushItemWidth(300)
                imgui.InputTextWithHint("##cmd", u8"/su {id} 3 Íåïîä÷èíåíèå", ui_inputCmd, 256)
                imgui.PopItemWidth()
                imgui.SameLine()
                
                local keyName = (ui_isWaitingKey) and u8"ÆÄÓ..." or (ui_currentKey == 0 and u8"ÂÛÁÐÀÒÜ" or u8(getKeyName(ui_currentKey)))
                if imgui.Button(keyName, imgui.ImVec2(100, 25)) then ui_isWaitingKey = true end
                
                if imgui.Button(u8"ÄÎÁÀÂÈÒÜ", imgui.ImVec2(-1, 30)) then
                    local cmdStr = u8:decode(ffi.string(ui_inputCmd))
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
                        imgui.Text(u8(tostring(bind.cmd or "Error")))
                        
                        imgui.SameLine(imgui.GetContentRegionAvail().x - 60) 
                        if imgui.Button(u8"Óäàëèòü") then
                            table.remove(settings.binds, i)
                            saveSettings()
                        end
                        imgui.PopID()
                    end
                imgui.EndChild()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem(u8"Èíôîðìàöèÿ") then
                imgui.Text(u8"Ñêðèïò: ChaseTracker")
                imgui.Text(u8"Àâòîð: Zhukoff Kevin_Zhukoff [Yuma]")
                imgui.Text(u8"Òåêóùàÿ âåðñèÿ: " .. cur_version)
                imgui.Separator()
                imgui.Text(u8"Ñòàòóñ: " .. u8(update_state))
                
                if imgui.Button(u8"Ïðîâåðèòü îáíîâëåíèÿ", imgui.ImVec2(-1, 35)) then
                    check_update()
                end
                
                if update_available then
                    if imgui.Button(u8"Óñòàíîâèòü îáíîâëåíèå", imgui.ImVec2(-1, 35)) then
                        perform_update()
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
            imgui.TextColored(imgui.ImVec4(1, 1, 0, 1), u8"ÐÅÆÈÌ ÐÅÄÀÊÒÈÐÎÂÀÍÈß (Äâèãàé îêíî)")
        end

        imgui.SetWindowFontScale(settings.main.hud_scale)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(settings.main.text_color_r, settings.main.text_color_g, settings.main.text_color_b, settings.main.text_color_a))

        if settings.main.show_nick then imgui.Text(u8("Öåëü: " .. tostring(chase.name or ""))) end
        if settings.main.show_id then imgui.Text(u8("ID: " .. tostring(chase.id or -1))) end
        if settings.main.show_status then 
            local st = (chase.status == nil or chase.status == "") and "Àêòèâíà" or chase.status
            imgui.Text(u8("Ñòàòóñ: " .. tostring(st))) 
        end
        
        imgui.PopStyleColor()

        if settings.main.show_z_timer then
            local zText = "Íåò"
            if chase.z_expiry and chase.z_expiry > 0 and chase.name == chase.z_name then
                local timeLeft = chase.z_expiry - os.time()
                if timeLeft > 0 then
                    zText = string.format("%02d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
                else
                    zText = "ÑÏÀËÀ!"
                end
            end
            imgui.Text(u8"Òàéìåð /z: ")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(settings.main.z_color_r, settings.main.z_color_g, settings.main.z_color_b, settings.main.z_color_a), u8(zText))
        end

        if chase.active and settings.main.show_arrow and sampIsPlayerConnected(chase.id) then
            local res, ped = sampGetCharHandleBySampPlayerId(chase.id)
            if res and doesCharExist(ped) and isCharOnScreen(ped) then
                local px, py, pz = getCharCoordinates(ped)
                local cx, cy, cz = getActiveCameraCoordinates()
                
                if isLineOfSightClear(cx, cy, cz, px, py, pz + 0.8, true, false, false, true, false, false, false) then
                    local rX, rY = convert3DCoordsToScreen(px, py, pz + 1.0)
                    
                    if rX and rY then
                        local size = settings.main.arrow_size or 18.0
                        local yOffset = 15.0
                        
                        if settings.main.arrow_anim then
                            yOffset = 15.0 + (math.sin(os.clock() * 6.0) * 5.0)
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
    
    sampAddChatMessage("[ChaseTracker] v" .. cur_version .. " by Kevin_Zhukoff [Yuma] çàãðóæåí. Ìåíþ: {FFFF00}/chase", 0x00FF00)
    
    sampRegisterChatCommand("chase", function() ui_menu[0] = not ui_menu[0] end)
    
    sampRegisterChatCommand("trg", function(arg)
        arg = arg or ""
        if #arg == 0 then
            resetChase()
            sampAddChatMessage("[ChaseTracker] Ðó÷íàÿ öåëü ñáðîøåíà.", 0xFFFF00)
            return
        end
        local id = tonumber(arg:match("%d+"))
        if id and sampIsPlayerConnected(id) then 
            setTarget(id, "Ðó÷íîé òàðãåò (/trg)")
        else
            sampAddChatMessage("[ChaseTracker] Èãðîê ñ òàêèì ID íå íàéäåí!", 0xFF0000)
        end
    end)
    
    sampRegisterChatCommand("pursuit", function(arg)
        arg = arg or ""
        sampSendChat("/pursuit " .. arg)
        local id = tonumber(arg:match("%d+"))
        if id and sampIsPlayerConnected(id) then 
            setTarget(id, "Ïîãîíÿ (/pursuit)") 
        end
    end)

    check_update()

    while true do
        wait(0)
        
        render_hud.HideCursor = not ui_edit_hud[0]
        
        if chase.active then
            if not sampIsPlayerConnected(chase.id) or sampGetPlayerNickname(chase.id) ~= chase.name then
                resetChase()
                sampAddChatMessage("[ChaseTracker] Öåëü ïîêèíóëà ñåðâåð èëè ñìåíèëà ID. Îòñëåæèâàíèå çàâåðøåíî.", 0xFF6347)
            end
        end

        if ui_menu[0] and ui_waiting_bind then
            for k = 1, 255 do
                if wasKeyPressed(k) and k ~= 1 and k ~= 2 and k ~= vk.VK_ESCAPE then
                    settings.main[ui_waiting_bind] = k
                    ui_waiting_bind = nil
                    saveSettings()
                    break
                elseif wasKeyPressed(vk.VK_ESCAPE) then
                    settings.main[ui_waiting_bind] = 0
                    ui_waiting_bind = nil
                    saveSettings()
                    break
                end
            end
        end

        if ui_menu[0] and ui_isWaitingKey then
            for k = 1, 255 do
                if wasKeyPressed(k) and k ~= 1 and k ~= 2 then 
                    ui_currentKey = k
                    ui_isWaitingKey = false
                    break
                end
            end
        end

        if not sampIsChatInputActive() and not sampIsDialogActive() and not isSampfuncsConsoleActive() then
            if wasKeyPressed(vk.VK_RBUTTON) then
                local now = os.clock()
                if now - lastRmbPress < 0.35 then
                    rmbTargetWindow = now + 0.4
                    lastRmbPress = 0
                else
                    lastRmbPress = now
                end
            end

            if rmbTargetWindow > 0 and os.clock() <= rmbTargetWindow then
                local res, targetPed = getCharPlayerIsTargeting(PLAYER_HANDLE)
                if res and targetPed and doesCharExist(targetPed) then
                    local resId, targetId = sampGetPlayerIdByCharHandle(targetPed)
                    if resId and targetId ~= -1 then
                        setTarget(targetId, "Òàðãåò (2x ÏÊÌ)")
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
                        sampSendChat("/me ñíÿë íàðó÷íèêè ñ òàêòè÷åñêîãî ïîÿñà è ðåçêèì äâèæåíèåì çàêîâàë ðóêè ïîäîçðåâàåìîãî")
                        sampProcessChatInput("/cuff " .. chase.id) 
                    end
                    
                    if (settings.main.bind_pull or 0) ~= 0 and wasKeyPressed(settings.main.bind_pull) then 
                        sampSendChat("/me ñèëîé îòêðûë äâåðü òðàíñïîðòà è âûòàùèë ïîäîçðåâàåìîãî íàðóæó")
                        sampProcessChatInput("/pull " .. chase.id) 
                    end
                    
                    if (settings.main.bind_gotome or 0) ~= 0 and wasKeyPressed(settings.main.bind_gotome) then 
                        sampSendChat("/me âçÿë çàäåðæàííîãî çà çàëîìëåííóþ ðóêó è óâåðåííî ïîâåë çà ñîáîé")
                        sampProcessChatInput("/gotome " .. chase.id) 
                    end
                    
                    for _, bind in ipairs(settings.binds) do
                        if bind.key ~= 0 and wasKeyPressed(bind.key) then
                            local cmdToSend = (bind.cmd or ""):gsub("{id}", tostring(chase.id))
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
        chase.status = statusText or "Ðó÷íîé òàðãåò"
        sampAddChatMessage(string.format("[ChaseTracker] Óñòàíîâëåíà öåëü: %s [%d]", chase.name, chase.id), 0x00FF00)
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
    if cleanText:find("Âû óñïåøíî íà÷àëè ïîãîíþ çà èãðîêîì") or cleanText:find("íà÷àëè îòñëåæèâàòü") or cleanText:find("íà÷àëè ïðåñëåäîâàíèå") then
        local name, id = cleanText:match("([A-Za-z0-9_]+)%s*%[ID:%s*(%d+)%]")
        if not name or not id then
            name, id = cleanText:match("èãðîêîì%s+([A-Za-z0-9_]+).*ID:%s*(%d+)")
        end
        if name and id then 
            chase.active = true; chase.name = name; chase.id = tonumber(id); chase.status = "Ïîãîíÿ (/pursuit)" 
        end
    end
    if cleanText:find("Âû óñïåøíî ïîìåòèëè èãðîêà") and cleanText:find("òå÷åíèå") then
        local name = cleanText:match("ïîìåòèëè èãðîêà%s+(.+)%.%s+Åñëè")
        local minutes = cleanText:match("òå÷åíèå%s+(%d+)%s+ìèíóò")
        if name and minutes then chase.z_expiry = os.time() + (tonumber(minutes) * 60); chase.z_name = name end
    end
    if cleanText:find("Ïðåñëåäîâàíèå.*ïðèîñòàíîâëåíî") or cleanText:find("îòïðàâèë%(à%) ïîäîçðåâàåìîãî.*â ÊÏÇ") or cleanText:find("ïîòåðÿëè èç âèäó") or cleanText:find("ïîãîíÿ áûëà ïðåêðàùåíà") then 
        resetChase() 
    end
end
