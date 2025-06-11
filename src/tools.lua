-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}

-- A registry to hold the function definitions and their callable implementations.
local registry = {}

-- Bot name management
local BOT_NAME_FILE = "/etc/jarvis/botname.txt"
local DEFAULT_BOT_NAME = "jarvis"

-- Function to get the current bot name
function Tools.get_bot_name()
    if fs.exists(BOT_NAME_FILE) then
        local file = fs.open(BOT_NAME_FILE, "r")
        if file then
            local name = file.readAll():gsub("%s+", ""):lower() -- trim whitespace and lowercase
            file.close()
            return name ~= "" and name or DEFAULT_BOT_NAME
        end
    end
    return DEFAULT_BOT_NAME
end

-- Function to set the bot name
function Tools.set_bot_name(new_name)
    if not new_name or new_name == "" then
        return { success = false, message = "Name cannot be empty" }
    end
    
    -- Ensure the directory exists
    local dir = BOT_NAME_FILE:match("(.*)/")
    if dir and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(BOT_NAME_FILE, "w")
    if file then
        file.write(new_name:lower()) -- store in lowercase
        file.close()
        return { success = true, message = "Bot name changed to: " .. new_name }
    else
        return { success = false, message = "Failed to save name to file" }
    end
end

-- Function to check if a message is addressing the bot
function Tools.is_message_for_bot(message)
    local bot_name = Tools.get_bot_name()
    local msg_lower = message:lower():gsub("^%s+", "") -- trim leading whitespace and lowercase
    
    -- Check if message starts with bot name followed by space, comma, colon, or question mark
    return msg_lower:match("^" .. bot_name .. "[%s,:%?]") ~= nil
end

-- Tool Definition: get_time
-- This function gets the current in-game time.
function Tools.get_time()
    return { time = textutils.formatTime(os.time("ingame"), false) }
end

-- Tool Definition: change_name
-- This function changes the bot's name.
function Tools.change_name(new_name)
    return Tools.set_bot_name(new_name)
end

-- Register the get_time tool with its implementation and schema for the LLM.
registry.get_time = {
    func = Tools.get_time,
    schema = {
        type = "function",
        ["function"] = {
            name = "get_time",
            description = "Get the current in-game time.",
            parameters = {
                type = "object",
                properties = {},
                required = {},
            },
        },
    },
}

-- Register the change_name tool
registry.change_name = {
    func = function(args)
        local new_name = args and args.new_name
        return Tools.change_name(new_name)
    end,
    schema = {
        type = "function",
        ["function"] = {
            name = "change_name",
            description = "Change the bot's name that it responds to.",
            parameters = {
                type = "object",
                properties = {
                    new_name = {
                        type = "string",
                        description = "The new name for the bot"
                    }
                },
                required = {"new_name"},
            },
        },
    },
}


-- Function to get all tool schemas to send to the LLM.
function Tools.get_all_schemas()
    local schemas = {}
    for name, tool in pairs(registry) do
        table.insert(schemas, tool.schema)
    end
    return schemas
end

-- Function to get a tool's implementation by name.
function Tools.get_tool(name)
    if registry[name] then
        return registry[name].func
    end
    return nil
end

return Tools 