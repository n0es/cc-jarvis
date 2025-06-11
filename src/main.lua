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
        local bot_name = tools.get_bot_name()

        -- Only respond if the message is addressed to the bot
        if tools.is_message_for_bot(message_text) then
            print(player .. " says: " .. message_text)
            table.insert(messages, { role = "user", content = message_text })

            -- Call the LLM 
            chatBox.sendMessage("Thinking...", bot_name)
            local ok, response = llm.request(config.openai_api_key, config.model, messages, tool_schemas)

            if not ok then
                printError("LLM Request Failed: " .. tostring(response))
                chatBox.sendMessage("Sorry, I encountered an error.", bot_name)
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
                    chatBox.sendMessage(final_message, bot_name)
                    table.insert(messages, { role = "assistant", content = final_message })
                else
                    printError("Second LLM Request Failed: " .. tostring(final_response))
                    chatBox.sendMessage("Sorry, I encountered an error after using my tool.", bot_name)
                end

            elseif type(result) == "string" then
                -- The LLM returned a direct message.
                chatBox.sendMessage(result, bot_name)
                table.insert(messages, { role = "assistant", content = result })
            end

            ::continue::
        end
    end
end

main() 