-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}
local debug = require("debug")

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

-- Tool Definition: change_name
-- This function changes the bot's name.
function Tools.change_name(new_name)
    return Tools.set_bot_name(new_name)
end

-- Tool Definition: test_connection
-- This function tests HTTP connectivity.
function Tools.test_connection()
    if not http then
        return { success = false, error = "HTTP API is not available. Check computercraft-common.toml settings." }
    end
    
    local results = {}
    
    -- Test 1: General HTTP connectivity
    local test_url = "https://httpbin.org/get"
    debug.info("Testing HTTP connectivity to " .. test_url)
    
    local success, response = http.get(test_url)
    if success then
        local body = response.readAll()
        response.close()
        results.general_http = { 
            success = true, 
            message = "General HTTP connectivity is working", 
            response_size = #body 
        }
    else
        local error_msg = "General HTTP test failed"
        if response then
            if type(response) == "string" then
                error_msg = error_msg .. ": " .. response
            end
        end
        results.general_http = { success = false, error = error_msg }
    end
    
    -- Test 2: OpenAI domain connectivity
    debug.info("Testing connectivity to OpenAI domain...")
    local openai_success, openai_response = http.get("https://api.openai.com/")
    if openai_success then
        local openai_body = openai_response.readAll()
        openai_response.close()
        results.openai_domain = {
            success = true,
            message = "OpenAI domain is reachable",
            response_size = #openai_body
        }
    else
        local openai_error = "OpenAI domain test failed"
        if openai_response then
            if type(openai_response) == "string" then
                openai_error = openai_error .. ": " .. openai_response
            end
        end
        results.openai_domain = { success = false, error = openai_error }
    end
    
    -- Overall result
    local overall_success = results.general_http.success and results.openai_domain.success
    
    return {
        success = overall_success,
        message = overall_success and "All connectivity tests passed" or "Some connectivity tests failed",
        results = results
    }
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

-- Register the test_connection tool
registry.test_connection = {
    func = Tools.test_connection,
    schema = {
        type = "function",
        ["function"] = {
            name = "test_connection",
            description = "Test HTTP connectivity to diagnose connection issues.",
            parameters = {
                type = "object",
                properties = {},
                required = {},
            },
        },
    },
}

-- Tool Definition: get_time
-- This function gets the current in-game time.
function Tools.get_time()
    return { time = textutils.formatTime(os.time("ingame"), false) }
end

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