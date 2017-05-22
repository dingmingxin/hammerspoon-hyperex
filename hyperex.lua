
--  hyperex.lua
--  version: 0.1

local log=hs.logger.new('hyperex', 'debug')

-- 比較の手間を省くためにあらかじめ数値にしておく
local function realKeyCode(v)
    if type(v) == 'string' then
        v = hs.keycodes.map[v]
    end
    if type(v) == 'number' then
        return v
    end
    return nil
end

-- 2つの引数から modifiers と key を取得する。返り値は modifiers, key
-- ({'mod','mod'}, key) (key, {'mod','mod'}) -> 順不同で OK
-- ('key', nil)  -> modifiers は {}
-- ('mod+mod+key') -> オリジナル
local parseKey = function(a1, a2)
    local parseSingle = function(a)
        if type(a) == 'number' then return {}, a end
        if type(a) == 'string' then
            local k = realKeyCode(a)
            if k ~= nil then return {}, k end
            -- parse mod+mod+k style
            k = a:lower()
            local words = hs.fnutils.split(k, '+')
            local key = nil
            local mods = hs.fnutils.imap(words, function(v)
                if v == 'cmd' or v == 'command' or v == '⌘' then
                    return 'cmd' 
                elseif v == 'ctrl' or v == 'control' or v == '⌃' or v == 'ctl' then
                    return 'ctrl' 
                elseif v == 'alt' or v == 'option' or v == '⌥' or v == 'opt' then
                    return 'alt' 
                elseif v == 'shift' or v == '⇧' or v == 'shft' then
                    return 'shift' 
                end
                if v == '' then
                    if key == 'pad' then key = 'pad+' end
                else
                    key = v
                end
                return nil
            end)
            return mods, realKeyCode(key)
        end
    end

    if a2 == nil then return parseSingle(a1) end

    local m = nil
    local k = nil

    if type(a1) == 'table' then
        m = a1
        k = a2
    elseif type(a2) == 'table' then
        m = a2
        k = a1
    end
    if k ~= nil then
        k = realKeyCode(k)
        return m, k
    end

    return {}, nil
end

local function modifiersToFlags(modifiers)
    local flags = {}
    for i, v in pairs(modifiers) do
        flags[v] = true
    end
    return flags
end

local CModifier = {}
CModifier.new = function(hyperInstance)
    local _self = {
        _modFlags = {},
        _targetKeys = {},
        _anyTarget = false,
        message = nil,
        alertDuration = 0.4,
    }

   _self.mod = function(self, modifiers)
        if type(modifiers) == 'string' then
            modifiers = {modifiers}
        end
        self._modFlags = modifiersToFlags(modifiers)
        return self
    end

    _self.withMessage = function(self, m, t)
        self.message = m
        if type(t) == 'number' then
            self.alertDuration = t
        end
        return self
    end

    _self.showMessage = function(self)
        if type(self.message) == 'string' then 
            hs.alert(self.message, self.alertDuration or 0)
        end
    end

    _self.to = function(self, keys)
        if type(keys) == 'string' then
            if keys == 'any' or keys == 'all' then
                self._anyTarget = true
                return self
            end
            keys = {keys}
        elseif type(keys) == 'number' then
            keys = {keys}
        end
        local keyNumbers = {}
        for i, v in pairs(keys) do
            local specials = nil
            if v == 'atoz' then
                specials = {'a','b','c','d','e','f','g','h','i','j','k','l','m',
                    'n','o','p','q','r','s','t','u','v','w','x','y','z'}
            elseif v == 'fkeys' then
                specials = {'f1','f2','f3','f4','f5','f6','f7','f8','f9','f10','f11','f12','f13','f14','f15'}
            else
                v = realKeyCode(v)
                if type(v) == 'number' then
                    table.insert(keyNumbers, v)
                end
            end
            if specials ~= nil then
                for i, v in pairs(specials) do
                    table.insert(keyNumbers, realKeyCode(v))
                end
            end
        end
        self._targetKeys = keyNumbers
        return self
    end

    _self.flagsForKey = function(self, key)
        if self._anyTarget then
            return self._modFlags
        end
        for i, v in pairs(self._targetKeys) do
            if key == v then
                return self._modFlags
            end
        end
        return nil
    end

    return _self
end

local CBinder = {}
CBinder.new = function(hyperInstance)
    local _self = {
        fromKey = nil,
        fromMod = {},
        toKey = nil,
        toFlags = {},
        toFunc = nil,
        message = nil,
        alertDuration = 0.4,
    }

    _self.withMessage = function(self, m, t)
        self.message = m
        if type(t) == 'number' then
            self.alertDuration = t
        end
        return self
    end

    _self.showMessage = function(self)
        if type(self.message) == 'string' then 
            hs.alert(self.message, self.alertDuration or 0)
        end
    end

    _self.bind = function(self, fromKey, fromMod)
        self.fromMod, self.fromKey = parseKey(fromKey, fromMod)
        return self
    end

    _self.to = function(self, a1, a2)
        if type(a1) == 'function' then
            self.toFunc = a1
            self.toKey = nil
            return self
        end

        self.toFlags, self.toKey = parseKey(a1, a2)
        if self.toKey ~= nil then
            self.toFlags = modifiersToFlags(self.toFlags)
            self.toFunc = nil
        end
        return self
    end

    return _self
end

local CHyper = {}

CHyper.new = function(triggerKey)
    local _self = {
        message = nil,
        leaveMessage = nil,
        alertDuration = 0.4,

        _triggered = false,
        _binders = {},
        _modifiers = {},
        _emptyHitFunc = nil,
        _initialHitFunc = nil,

        _triggerKey = nil,
        _triggerMod = {}, -- unused now
        _trigger = nil,

        _tap = nil,
        _nop = function() end
    }

    _self.withMessage = function(self, m, t, z)
        if type(m) == 'string' and #m > 0 then
            self.message = m
        end
        if type(t) == 'number' then
            self.alertDuration = t
        elseif type(t) == 'string' and #t > 0 then
            self.leaveMessage = t
            if type(z) == 'number' then
                self.alertDuration = z
            end
        end
        return self
    end

    _self.setInitialFunc = function(self, func)
        if (type(func) == 'function') then
            self._initialHitFunc = func
        end
        return self
    end

    _self.setInitialKey = function(self, key, modifiers)
        modifiers, key = parseKey(key, modifiers)
        if key == self._triggerKey then
            return self
        end
        self._initialHitFunc = function()
            hs.eventtap.event.newKeyEvent(modifiers, key, true):post()
            hs.timer.usleep(600)
            hs.eventtap.event.newKeyEvent(modifiers, key, false):post()
        end
        return self
    end

    _self.setEmptyHitFunc = function(self, func)
        if type(func) == 'function' then
            self._emptyHitFunc = func
        end
        return self
    end

    _self.setEmptyHitKey = function(self, key, modifiers)
        modifiers, key = parseKey(key, modifiers)
        if key == self._triggerKey then
            return self
        end
        self._emptyHitFunc = function()
            hs.eventtap.event.newKeyEvent(modifiers, key, true):post()
            hs.timer.usleep(600)
            hs.eventtap.event.newKeyEvent(modifiers, key, false):post()
        end
        return self
    end

    _self.enter = function(self)
        self = self or _self
        if self._tap:isEnabled() then
            log.d('try to re-enter')
            return
        end
        if type(self.message) == 'string' then 
            hs.alert(self.message, self.alertDuration or 0)
        end
        self._tap:start()
        if self._initialHitFunc then
            self._initialHitFunc()
        end
        self._triggered = false
    end

    _self.exit = function(self)
        self = self or _self
        if not self._tap:isEnabled() then
            log.d('try to re-exit')
            return
        end
        if type(self.leaveMessage) == 'string' then 
            hs.alert(self.leaveMessage, self.alertDuration or 0)
        end
        self._tap:stop()
        -- stop した後に呼ばないとキーイベントが発生しない
        if (not self._triggered) and self._emptyHitFunc then
            self._emptyHitFunc()
        end
    end

    _self.bind = function(self, fromKey, fromMod)
        local b = CBinder.new(self):bind(fromKey, fromMod)
        table.insert(self._binders, 1, b)
        return b
    end

    _self.mod = function (self, modifiers)
        local m = CModifier.new(self):mod(modifiers)
        table.insert(self._modifiers, 1, m)
        return m
    end


    _self._handleTap = function (e)
        local self = _self
        local keyCode = e:getKeyCode()
        -- キーボードからの直接入力だけを扱う
        local stateID = e:getProperty(hs.eventtap.event.properties['eventSourceStateID'])
        if stateID ~= 1 then
            return false
        end

        local isFirstKeyDown = false
        if e:getType() == hs.eventtap.event.types.keyDown then
            -- ややこしいことになるので triggerKey と同じものは無視
            -- hotkey 最初の keyDown は来ないが、押下中の keyRepeat は来る
            -- true/false どちらを返しても同じみたいだけど一応 true を返しておく
            if keyCode == self._triggerKey then
                return true
            end
            if e:getProperty(hs.eventtap.event.properties['keyboardEventAutorepeat']) == 0 then
                isFirstKeyDown = true
            end
        else
            -- triggerKey の keyUp は確実に逃がさないとモードを抜け出せない
            if keyCode == self._triggerKey then
                return false
            end
        end

        -- binder
        for i, v in ipairs(self._binders) do
            if keyCode == v.fromKey then
                -- remap 型
                if v.toKey ~= nil then
                    e:setKeyCode(v.toKey)
                    e:setFlags(v.toFlags)
                    if isFirstKeyDown then
                        self._triggered = true
                        v:showMessage()
                    end
                    return false
                -- func 型
                elseif v.toFunc ~= nil then
                    if isFirstKeyDown then
                        self._triggered = true
                        v:showMessage()
                        v.toFunc()
                    end
                    return true
                end
            end
        end

        -- modifier
        for i, v in ipairs(self._modifiers) do
            local flag = v:flagsForKey(keyCode)
            if flag ~= nil then
                e:setFlags(flag)
                if isFirstKeyDown then
                    self._triggered = true
                end
                return false
            end
        end

        return false
    end

    _self._triggerMod, _self._triggerKey = parseKey(triggerKey)
    if _self._triggerKey ~= nil then
        _self._trigger = hs.hotkey.bind( _self._triggerMod, _self._triggerKey, 0, _self.enter, _self.exit, nil )
        _self._tap = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp}, _self._handleTap)
    end

    return _self
end

return CHyper
