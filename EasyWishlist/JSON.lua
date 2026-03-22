-- EasyWishlist - JSON.lua
-- Minimal recursive descent JSON parser
-- Entry point: EWL.ParseJSON(str) -> table, nil  |  nil, errorMessage

local function JSONError(msg, pos, str)
    local snippet = str:sub(math.max(1, pos - 10), pos + 10)
    return nil, string.format("JSON error at pos %d near '%s': %s", pos, snippet, msg)
end

local function SkipWhitespace(str, pos)
    return str:match("^%s*()", pos)
end

local ParseValue  -- forward declaration

local function ParseString(str, pos)
    -- pos points at opening "
    local result = {}
    local i = pos + 1
    while i <= #str do
        local c = str:sub(i, i)
        if c == '"' then
            return table.concat(result), i + 1
        elseif c == '\\' then
            local esc = str:sub(i + 1, i + 1)
            if esc == '"'  then result[#result+1] = '"';  i = i + 2
            elseif esc == '\\' then result[#result+1] = '\\'; i = i + 2
            elseif esc == '/'  then result[#result+1] = '/';  i = i + 2
            elseif esc == 'n'  then result[#result+1] = '\n'; i = i + 2
            elseif esc == 'r'  then result[#result+1] = '\r'; i = i + 2
            elseif esc == 't'  then result[#result+1] = '\t'; i = i + 2
            elseif esc == 'b'  then result[#result+1] = '\b'; i = i + 2
            elseif esc == 'f'  then result[#result+1] = '\f'; i = i + 2
            elseif esc == 'u'  then
                -- \uXXXX — basic BMP only, just skip for our use case
                result[#result+1] = '?'
                i = i + 6
            else
                return JSONError("Unknown escape \\" .. esc, i, str)
            end
        else
            result[#result+1] = c
            i = i + 1
        end
    end
    return JSONError("Unterminated string", pos, str)
end

local function ParseNumber(str, pos)
    local numStr, newPos = str:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)()", pos)
    if not numStr then
        return JSONError("Invalid number", pos, str)
    end
    return tonumber(numStr), newPos
end

local function ParseArray(str, pos)
    -- pos points at [
    local arr = {}
    pos = SkipWhitespace(str, pos + 1)
    if str:sub(pos, pos) == ']' then
        return arr, pos + 1
    end
    while true do
        local val, err
        val, pos, err = ParseValue(str, pos)
        if err then return nil, pos, err end
        arr[#arr + 1] = val
        pos = SkipWhitespace(str, pos)
        local c = str:sub(pos, pos)
        if c == ']' then
            return arr, pos + 1
        elseif c == ',' then
            pos = SkipWhitespace(str, pos + 1)
        else
            return JSONError("Expected ',' or ']' in array", pos, str)
        end
    end
end

local function ParseObject(str, pos)
    -- pos points at {
    local obj = {}
    pos = SkipWhitespace(str, pos + 1)
    if str:sub(pos, pos) == '}' then
        return obj, pos + 1
    end
    while true do
        pos = SkipWhitespace(str, pos)
        if str:sub(pos, pos) ~= '"' then
            return JSONError("Expected '\"' for object key", pos, str)
        end
        local key, err
        key, pos, err = ParseString(str, pos)
        if err then return nil, pos, err end
        pos = SkipWhitespace(str, pos)
        if str:sub(pos, pos) ~= ':' then
            return JSONError("Expected ':' after key", pos, str)
        end
        pos = SkipWhitespace(str, pos + 1)
        local val
        val, pos, err = ParseValue(str, pos)
        if err then return nil, pos, err end
        obj[key] = val
        pos = SkipWhitespace(str, pos)
        local c = str:sub(pos, pos)
        if c == '}' then
            return obj, pos + 1
        elseif c == ',' then
            pos = SkipWhitespace(str, pos + 1)
        else
            return JSONError("Expected ',' or '}' in object", pos, str)
        end
    end
end

ParseValue = function(str, pos)
    pos = SkipWhitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == '"' then
        return ParseString(str, pos)
    elseif c == '{' then
        return ParseObject(str, pos)
    elseif c == '[' then
        return ParseArray(str, pos)
    elseif c == 't' then
        if str:sub(pos, pos + 3) == "true" then
            return true, pos + 4
        end
        return JSONError("Invalid token", pos, str)
    elseif c == 'f' then
        if str:sub(pos, pos + 4) == "false" then
            return false, pos + 5
        end
        return JSONError("Invalid token", pos, str)
    elseif c == 'n' then
        if str:sub(pos, pos + 3) == "null" then
            return nil, pos + 4  -- Lua nil; caller must handle
        end
        return JSONError("Invalid token", pos, str)
    elseif c == '-' or c:match("%d") then
        return ParseNumber(str, pos)
    elseif c == '' then
        return JSONError("Unexpected end of input", pos, str)
    else
        return JSONError("Unexpected character '" .. c .. "'", pos, str)
    end
end

function EWL.ParseJSON(str)
    if type(str) ~= "string" or #str == 0 then
        return nil, "Input is empty or not a string"
    end
    local val, pos, err = ParseValue(str, 1)
    if err then return nil, err end
    -- Check for trailing non-whitespace
    pos = SkipWhitespace(str, pos)
    if pos <= #str then
        return nil, string.format("Unexpected trailing content at pos %d", pos)
    end
    return val
end
