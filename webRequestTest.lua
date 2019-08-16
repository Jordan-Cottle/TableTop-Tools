
-- Initialize Block with button to start web request
buttonParameters = {
    click_function = 'startWebRequest',
    label = 'Hello',
    position = {0, 0.5, 0},
    width = 400,
    height = 400,
    function_owner = self
}
self.createButton(buttonParameters)

-- JSON decode library

--[[
-- json.lua
--
-- Copyright (c) 2019 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--]]

local escape_char_map = {
    [ "\\" ] = "\\\\",
    [ "\"" ] = "\\\"",
    [ "\b" ] = "\\b",
    [ "\f" ] = "\\f",
    [ "\n" ] = "\\n",
    [ "\r" ] = "\\r",
    [ "\t" ] = "\\t",
}

local escape_char_map_inv = { [ "\\/" ] = "/" }
for k, v in pairs(escape_char_map) do
    escape_char_map_inv[v] = k
end

local parse

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
        res[ select(i, ...) ] = true
    end
    return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
    [ "true"  ] = true,
    [ "false" ] = false,
    [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
    for i = idx, #str do
        if set[str:sub(i, i)] ~= negate then
        return i
        end
    end
    return #str + 1
end


local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
        col_count = col_count + 1
        if str:sub(i, i) == "\n" then
            line_count = line_count + 1
            col_count = 1
        end
    end
    error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
    --[[ http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa ]]
    local f = math.floor
    if n <= 0x7f then
        return string.char(n)
    elseif n <= 0x7ff then
        return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
        return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
    elseif n <= 0x10ffff then
        return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                            f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
    local n1 = tonumber( s:sub(3, 6),  16 )
    local n2 = tonumber( s:sub(9, 12), 16 )
    if n2 then
        return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
        return codepoint_to_utf8(n1)
    end
end


local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
        local x = str:byte(j)

        if x < 32 then
            decode_error(str, j, "control character in string")
        end

        if last == 92 then --[[ "\\" (escape char)]]
            if x == 117 then --[[ "u" (unicode escape sequence)]]
                local hex = str:sub(j + 1, j + 5)
                if not hex:find("%x%x%x%x") then
                    decode_error(str, j, "invalid unicode escape in string")
                end
                if hex:find("^[dD][89aAbB]") then
                    has_surrogate_escape = true
                else
                    has_unicode_escape = true
                end
            else
                local c = string.char(x)
                if not escape_chars[c] then
                    decode_error(str, j, "invalid escape char '" .. c .. "' in string")
                end
                has_escape = true
            end
            last = nil
        elseif x == 34 then --[[ '"' (end of string) ]]
            local s = str:sub(i + 1, j - 1)
            if has_surrogate_escape then
                s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
            end
            if has_unicode_escape then
                s = s:gsub("\\u....", parse_unicode_escape)
            end
            if has_escape then
                s = s:gsub("\\.", escape_char_map_inv)
            end
            return s, j + 1

        else
            last = x
        end
    end
    decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then
        decode_error(str, i, "invalid number '" .. s .. "'")
    end
    return n, x
end


local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
        decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
end
  
  
local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
        local x
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) == "]" then
            i = i + 1
        break
        end
        x, i = parse(str, i)
        res[n] = x
        n = n + 1
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "]" then break end
        if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
end

local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
        local key, val
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) == "}" then
        i = i + 1
        print("Empty Object")
        break
        end
        if str:sub(i, i) ~= '"' then
        decode_error(str, i, "expected string for key")
        end
        key, i = parse(str, i)
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) ~= ":" then
        decode_error(str, i, "expected ':' after key")
        end
        i = next_char(str, i + 1, space_chars, true)
        val, i = parse(str, i)
        res[key] = val
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "}" then
            break 
        end
        if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
end
  
  
local char_func_map = {
    [ '"' ] = parse_string,
    [ "0" ] = parse_number,
    [ "1" ] = parse_number,
    [ "2" ] = parse_number,
    [ "3" ] = parse_number,
    [ "4" ] = parse_number,
    [ "5" ] = parse_number,
    [ "6" ] = parse_number,
    [ "7" ] = parse_number,
    [ "8" ] = parse_number,
    [ "9" ] = parse_number,
    [ "-" ] = parse_number,
    [ "t" ] = parse_literal,
    [ "f" ] = parse_literal,
    [ "n" ] = parse_literal,
    [ "[" ] = parse_array,
    [ "{" ] = parse_object,
}
  
parseCount = 0
parse = function(str, idx)
    -- yield after a number of parses to avoid stalling game
    if parseCount == 100 then
        --print("Parsing yielded", Time.delta_time)
        coroutine.yield(0)
        parseCount = 0
    else
        parseCount = parseCount + 1
    end

    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then
        return f(str, idx)
    end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
end
  
  
function decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
        decode_error(str, idx, "trailing garbage")
    end
    return res
end
-- End JSON decode library

characterData = {
    name = "",

    stats = {
        strength = 0,
        dexterity = 0,
        constitution = 0,
        intelligence = 0,
        wisdom = 0,
        charisma = 0
    },

    classes = {
        -- Example
        -- Cleric = 3  [Class] = [Level]
    },

    -- total character level and associated proficiency bonus
    totalLevel = 0,
    proficiencyBonus = 0,

    -- weapon/armor/tool proficiencies
    proficiencies = {

    },

    languages = {

    },

    -- skill proficiencies
    skills = {
        strength = {
            athletics = 0
        },
        dexterity = {
            acrobatics = 0,
            sleightOfHand = 0,
            stealth = 0
        },
        intelligence = {
            arcana = 0,
            history = 0,
            investigation = 0,
            nature = 0,
            religion = 0
        },
        wisdom = {
            animalHandling = 0,
            insight = 0,
            medicine = 0,
            perception = 0,
            survival = 0
        },
        charisma = {
            deception = 0,
            intimidation = 0,
            performance = 0,
            persuasion = 0
        }
    }

}


-- pull base stats out of the json table received
function parseStats(statsIn)
    print("Looking through stats")
    for k, v in pairs(statsIn) do
        local id = v['id']
        local value = v['value']
        local stats = characterData.stats

        if id == 1 then
            stats.strength = value
        elseif id == 2 then
            stats.dexterity = value
        elseif id == 3 then
            stats.constitution = value
        elseif id == 4 then
            stats.intelligence = value
        elseif id == 5 then
            stats.wisdom = value
        elseif id == 6 then
            stats.charisma = value
        else
            print(id, 'not recognized')
        end
    end
end

function addStatBonus(stat, bonus)
    local stats = characterData.stats

    if stat == "strength-score" then
        stats.strength = stats.strength + bonus
    elseif stat == "dexterity-score" then
        stats.dexterity = stats.dexterity + bonus
    elseif stat == "consitution-score" then
        stats.constitution = stats.consitution + bonus
    elseif stat == "intelligence-score" then
        stats.intelligence = stats.intelligence + bonus
    elseif stat == "wisdom-score" then
        stats.wisdom = stats.wisdom + bonus
    elseif stat == "charisma-score" then
        stats.charisma = stats.charisma + bonus
    else
        print(stat, " not recognized as a stat")
    end
end

function addSkillProficiency(skill)
    local bonus = characterData.proficiencyBonus
    -- TODO Add proficiency bonus to selected skills
    print(skill, bonus)
end

function parseModifiers(modifiers)
    -- loop through each modifier type
    for type, values in pairs(modifiers) do
        -- loop through array of objects
        for index, modifier in pairs(values) do
            if modifier.type == "bonus" then
                addStatBonus(modifier.subType, modifier.value)                

            elseif modifier.type == "proficiency" then
                -- TODO select only skill proficiencies
                addSkillProficiency(modifier.subType)

                -- TODO add saving-throw proficiencies

                -- TODO add weapon/armor/tool proficiencies

            elseif modifier.type == "language" then
                print("Language: ", modifier.subType)
                -- TODO Add languages to table
            end
        end
    end
end

-- computes proficiency bonus based on total level
function getProficiencyBonus(level)
    return math.floor((7 + level) / 4)
end

-- gathers level and related class information, sets proficiency bonus based on total level
function parseClasses(classes)
    print("Classes: ")
    -- loop through all classes and pull relevant data
    for index, class in pairs(classes) do
        local name = class.definition.name
        local level = class.level
        
        characterData.classes[name] = level
    end

    local total = 0
    for class, lvl in pairs(characterData.classes) do
        total = total + lvl
    end

    characterData.totalLevel = total
    characterData.proficiencyBonus = getProficiencyBonus(total)
end

function addBonuses()
    -- TODO compute modifiers based on stats
end

function webRequestCallBack(webReturn)
    print('Data Received')

    function decodeWebJson()
        -- Decode json received into a lua table
        print("Starting JSON decode")
        character =  decode(webReturn.text)
        print("JSON decoded")

        characterData.name = character.name
        self.setName(character.name)
        
        parseStats(character.stats)

        parseClasses(character.classes)

        parseModifiers(character.modifiers)

        addBonuses()

        -- TODO Remove this after testing is done
        for k, v in pairs(characterData.stats) do
            print(k, v)
        end
    
        return 1
    end

    startLuaCoroutine(self, "decodeWebJson")
end

-- Arwin
-- https://www.dndbeyond.com/character/1828892/json

-- Korwin
-- https://www.dndbeyond.com/character/12044609/json

function download()
    request = WebRequest.get('https://www.dndbeyond.com/character/1828892/json', webRequestCallBack)

    while(not request.is_done) do
        print("Waiting for download")
        print(request.download_progress * 100, "%")
        coroutine.yield(0)
    end

    return 1
end

function startWebRequest(object, color)
    print(self.getName(), ': Starting web request')

    startLuaCoroutine(self, "download")
end