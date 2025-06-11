
-- Jarvis Installer

local files = {}

-- Packed files will be inserted here by the build script.
files["programs/lib/jarvis/tools.lua"] = [[
-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}

-- A registry to hold the function definitions and their callable implementations.
local registry = {}

-- Tool Definition: get_time
-- This function gets the current in-game time.
function Tools.get_time()
    return { time = textutils.formatTime(os.time("ingame"), false) }
end

-- Register the get_time tool with its implementation and schema for the LLM.
registry.get_time = {
    func = Tools.get_time,
    schema = {
        type = "function",
        function = {
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
files["programs/jarvis"] = [[
-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")

-- Load config
local CONFIG_PATH_LUA = "etc.jarvis.config"
local CONFIG_PATH_FS = "/etc/jarvis/config.lua"

local ok, config = pcall(require, CONFIG_PATH_LUA)
if not ok then
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
                -- In this simple example, we don't use arguments, but a real implementation would pass them.
                -- local args = textutils.unserialiseJSON(func_args_json)
                local result = tool_func()
                
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

    local messages = {
        { role = "system", content = "You are Jarvis, a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world." }
    }
    local tool_schemas = tools.get_all_schemas()

    while true do
        local _, player, message_text = os.pullEvent("chat")

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

main() 
]]
files["programs/lib/jarvis/llm.lua"] = [[
-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/chat/completions"

function LLM.request(api_key, model, messages, tools)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
    }

    local body = {
        model = model,
        messages = messages,
    }

    if tools and #tools > 0 then
        body.tools = tools
        body.tool_choice = "auto"
    end

    local body_json = textutils.serialiseJSON(body)

    local success, response = http.post(API_URL, body_json, headers)

    if not success then
        local err_msg = "HTTP request failed."
        if response then
            err_msg = err_msg .. " Response: " .. response.readAll()
        end
        return false, err_msg
    end

    local response_body = response.readAll()
    local response_data = textutils.unserialiseJSON(response_body)

    if not response_data then
        return false, "Failed to decode JSON response from API: " .. tostring(response_body)
    end
    
    if response_data.error then
        return false, "API Error: " .. response_data.error.message
    end

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
Reboot the computer to start Jarvis automatically.
Or, to run Jarvis now, execute: 'programs/jarvis'
]])
end

install()
