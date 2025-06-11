
    -- Jarvis Installer

    local files = {}

    -- Packed files will be inserted here by the build script.
    files["programs/jarvis"] = [[
-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")

-- Load config
local CONFIG_PATH_LUA = "etc.jarvis.config"
local CONFIG_PATH_FS = "/etc/jarvis/config.lua"

local config
if fs.exists(CONFIG_PATH_FS) then
    local config_func, err = loadfile(CONFIG_PATH_FS)
    if config_func then
        config = config_func()
    else
        error("Failed to load config file: " .. tostring(err), 0)
    end
else
    local err_msg = table.concat({
        "Could not load config from '" .. CONFIG_PATH_FS .. "'.",
        "Please create this file and add your OpenAI API key.",
        "",
        "Example to paste into the new file:",
        "--------------------------------------------------",
        "local config = {}",
        "",
        '-- Your OpenAI API key from https://platform.openai.com/api-keys',
        'config.openai_api_key = "YOUR_API_KEY_HERE"',
        "",
        '-- The model to use. "gpt-4o" is a good default.',
        'config.model = "gpt-4o"',
        "",
        "return config",
        "--------------------------------------------------"
    }, "\n")
    error(err_msg, 0)
end

if not config.openai_api_key or config.openai_api_key == "YOUR_API_KEY_HERE" then
    error("API key is not set in " .. CONFIG_PATH_FS .. ". Please add your OpenAI API key.", 0)
end


local function process_llm_response(response_data)
    local message = response_data.choices[1].message
    local finish_reason = response_data.choices[1].finish_reason

    if finish_reason == "tool_calls" then
        -- The model wants to call one or more tools.
        local tool_calls = message.tool_calls
        local tool_outputs = {}

        for _, tool_call in ipairs(tool_calls) do
            local func_name = tool_call["function"]["name"]
            local func_args_json = tool_call["function"]["arguments"]
            
            print("LLM wants to call tool: " .. func_name)
            local tool_func = tools.get_tool(func_name)

            if tool_func then
                local args = nil
                if func_args_json and func_args_json ~= "" and func_args_json ~= "{}" then
                    args = textutils.unserialiseJSON(func_args_json)
                end
                
                local result = tool_func(args)
                
                table.insert(tool_outputs, {
                    tool_call_id = tool_call.id,
                    role = "tool",
                    name = func_name,
                    content = textutils.serialiseJSON(result),
                })
            end
        end
        return tool_outputs
    end

    -- If it's not a tool call, it's a regular message for the user.
    return message.content
end


local function main()
    local chatBox = peripheral.find("chatBox")
    if not chatBox then
        error("Could not find a 'chatBox' peripheral. Please place one next to the computer.", 0)
    end

    print("Jarvis is online. Waiting for messages.")
    print("Current bot name: " .. tools.get_bot_name())

    local messages = {
        { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Only respond when someone addresses you by name." }
    }
    local tool_schemas = tools.get_all_schemas()

    while true do
        local _, player, message_text = os.pullEvent("chat")

        -- Only respond if the message is addressed to the bot
        if tools.is_message_for_bot(message_text) then
            print(player .. " says: " .. message_text)
            table.insert(messages, { role = "user", content = message_text })

            -- Call the LLM
            chatBox.sendMessageToPlayer("Thinking...", player)
            local ok, response = llm.request(config.openai_api_key, config.model, messages, tool_schemas)

            if not ok then
                printError("LLM Request Failed: " .. tostring(response))
                chatBox.sendMessageToPlayer("Sorry, I encountered an error.", player)
                table.remove(messages) -- Remove the failed user message
                goto continue
            end

            local result = process_llm_response(response)

            if type(result) == "table" then
                -- The LLM called a tool, so we add its output to the conversation and run again.
                for _, tool_output in ipairs(result) do
                    table.insert(messages, tool_output)
                end
                
                local final_ok, final_response = llm.request(config.openai_api_key, config.model, messages, tool_schemas)
                if final_ok then
                    local final_message = final_response.choices[1].message.content
                    chatBox.sendMessageToPlayer(final_message, player)
                    table.insert(messages, { role = "assistant", content = final_message })
                else
                    printError("Second LLM Request Failed: " .. tostring(final_response))
                    chatBox.sendMessageToPlayer("Sorry, I encountered an error after using my tool.", player)
                end

            elseif type(result) == "string" then
                -- The LLM returned a direct message.
                chatBox.sendMessageToPlayer(result, player)
                table.insert(messages, { role = "assistant", content = result })
            end

            ::continue::
        end
    end
end

main() 
]]
files["programs/lib/jarvis/tools.lua"] = [[
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
    
    -- Test with a simple HTTP request
    local test_url = "https://httpbin.org/get"
    print("Testing HTTP connectivity to " .. test_url)
    
    local success, response = http.get(test_url)
    if success then
        local body = response.readAll()
        response.close()
        return { 
            success = true, 
            message = "HTTP connectivity is working", 
            test_response_size = #body 
        }
    else
        local error_msg = "HTTP test failed"
        if response then
            if type(response) == "string" then
                error_msg = error_msg .. ": " .. response
            else
                error_msg = error_msg .. ": Unknown error"
            end
        end
        return { success = false, error = error_msg }
    end
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
]]
files["programs/lib/jarvis/llm.lua"] = [[
-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/chat/completions"

function LLM.request(api_key, model, messages, tools)
    print("[DEBUG] Starting LLM request...")
    
    -- Check if HTTP is enabled
    if not http then
        print("[DEBUG] HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    print("[DEBUG] HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    if api_key and #api_key > 8 then
        print("[DEBUG] API key format: " .. api_key:sub(1,4) .. "..." .. api_key:sub(-4))
    else
        print("[DEBUG] API key appears invalid or too short")
    end
    
    print("[DEBUG] Model: " .. tostring(model))
    print("[DEBUG] Messages count: " .. #messages)
    print("[DEBUG] Tools count: " .. (tools and #tools or 0))
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
    }
    print("[DEBUG] Headers prepared")

    local body = {
        model = model,
        messages = messages,
    }

    if tools and #tools > 0 then
        body.tools = tools
        body.tool_choice = "auto"
        print("[DEBUG] Tools added to request")
    end

    print("[DEBUG] Serializing request body...")
    local body_json = textutils.serialiseJSON(body)
    print("[DEBUG] Request body serialized successfully")
    print("[DEBUG] Request size: " .. #body_json .. " bytes")
    
    -- Show first 200 chars of request for debugging
    print("[DEBUG] Request preview: " .. body_json:sub(1, 200) .. (#body_json > 200 and "..." or ""))
    
    print("[DEBUG] Making HTTP POST request to: " .. API_URL)
    local success, response = http.post(API_URL, body_json, headers)
    print("[DEBUG] HTTP request completed. Success: " .. tostring(success))

    if not success then
        print("[DEBUG] HTTP request failed")
        local err_msg = "HTTP request failed."
        if response then
            print("[DEBUG] Response type: " .. type(response))
            if type(response) == "string" then
                print("[DEBUG] Error response: " .. response)
                err_msg = err_msg .. " Error: " .. response
            elseif response.readAll then
                local error_body = response.readAll()
                print("[DEBUG] Error response body: " .. error_body)
                err_msg = err_msg .. " Response: " .. error_body
                response.close()
            else
                print("[DEBUG] Response object has no readAll method")
            end
        else
            print("[DEBUG] No response object returned")
            err_msg = err_msg .. " No response received. Check internet connection and HTTP settings."
        end
        return false, err_msg
    end

    print("[DEBUG] HTTP request successful, reading response...")
    local response_body = response.readAll()
    response.close()
    print("[DEBUG] Response received: " .. #response_body .. " bytes")
    
    -- Show first 200 chars of response for debugging
    print("[DEBUG] Response preview: " .. response_body:sub(1, 200) .. (#response_body > 200 and "..." or ""))
    
    print("[DEBUG] Parsing JSON response...")
    local response_data = textutils.unserialiseJSON(response_body)

    if not response_data then
        print("[DEBUG] Failed to parse JSON response")
        return false, "Failed to decode JSON response from API: " .. tostring(response_body)
    end
    print("[DEBUG] JSON response parsed successfully")
    
    if response_data.error then
        print("[DEBUG] API returned error: " .. response_data.error.message)
        return false, "API Error: " .. response_data.error.message
    end

    print("[DEBUG] LLM request completed successfully")
    return true, response_data
end

return LLM 
]]

    local function install()
        print("Removing old version if it exists...")
        -- Delete the main program file and the library directory to ensure a clean install.
        local program_path = "programs/jarvis"
        local lib_path = "programs/lib/jarvis"
        if fs.exists(program_path) then
            print("  Deleting " .. program_path)
            fs.delete(program_path)
        end
        if fs.exists(lib_path) then
            print("  Deleting " .. lib_path)
            fs.delete(lib_path)
        end

        print("Installing Jarvis...")

        for path, content in pairs(files) do
            print("Writing " .. path)
            local dir = path:match("(.*)/")
            if dir and not fs.exists(dir) then
                fs.makeDir(dir)
            end

            -- No need to check for existence, we are performing a clean install.
            local file, err = fs.open(path, "w")
            if not file then
                printError("Failed to open " .. path .. ": " .. tostring(err))
                return
            end
            file.write(content)
            file.close()
        end

        -- Create placeholder config file if it doesn't exist
        local config_path = "/etc/jarvis/config.lua"
        if not fs.exists(config_path) then
            print("Creating placeholder config file at " .. config_path)
            local config_dir = "/etc/jarvis"
            if not fs.exists(config_dir) then
                fs.makeDir(config_dir)
            end

            local config_content = [[-- Configuration for Jarvis
local config = {}

-- Your OpenAI API key from https://platform.openai.com/api-keys
-- Replace YOUR_API_KEY_HERE with your actual API key
config.openai_api_key = "YOUR_API_KEY_HERE"

-- The model to use. "gpt-4o" is a good default.
config.model = "gpt-4o"

return config
]]

            local config_file = fs.open(config_path, "w")
            if config_file then
                config_file.write(config_content)
                config_file.close()
                print("Placeholder config created. Edit " .. config_path .. " and add your API key.")
            else
                printError("Failed to create config file at " .. config_path)
            end
        else
            print("Config file already exists at " .. config_path)
        end

        local startup_path = "startup.lua"
        local program_to_run = "programs/jarvis"

        local current_startup_content
        if fs.exists(startup_path) then
            local f = fs.open(startup_path, "r")
            current_startup_content = f.readAll()
            f.close()
        end

        if not current_startup_content or not current_startup_content:find(program_to_run, 1, true) then
            print("Adding Jarvis to startup file.")
            local startup_file = fs.open(startup_path, "a")
            startup_file.write(('shell.run("%s")\n'):format(program_to_run))
            startup_file.close()
        else
            print("Jarvis already in startup file.")
        end

        print([[

    Installation complete!
    IMPORTANT: Edit /etc/jarvis/config.lua and add your OpenAI API key.
    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: 'programs/jarvis'
    ]])
    end

    install()
