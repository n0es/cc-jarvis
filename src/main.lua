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
        '-- The model to use. "gpt-4.1" is a good default for the new API.',
        'config.model = "gpt-4.1"',
        "",
        "return config",
        "--------------------------------------------------"
    }, "\n")
    error(err_msg, 0)
end

if not config.openai_api_key or config.openai_api_key == "YOUR_API_KEY_HERE" then
    error("API key is not set in " .. CONFIG_PATH_FS .. ". Please add your OpenAI API key.", 0)
end

-- Extract response content from the new API format
local function extract_response_content(response_data)
    -- The new API format might return content differently
    -- Try multiple possible response structures
    if response_data.content then
        if type(response_data.content) == "table" and #response_data.content > 0 then
            -- Content is an array of content objects
            local content_obj = response_data.content[1]
            if content_obj.text then
                return content_obj.text
            elseif content_obj.content then
                return content_obj.content
            end
        elseif type(response_data.content) == "string" then
            return response_data.content
        end
    end
    
    -- Fallback to standard OpenAI format if available
    if response_data.choices and #response_data.choices > 0 then
        local choice = response_data.choices[1]
        if choice.message and choice.message.content then
            return choice.message.content
        end
    end
    
    -- Another possible structure for the new API
    if response_data.output and response_data.output.content then
        if type(response_data.output.content) == "table" and #response_data.output.content > 0 then
            local content_obj = response_data.output.content[1]
            if content_obj.text then
                return content_obj.text
            end
        end
    end
    
    return nil
end

local function process_llm_response(response_data)
    -- Try to extract content using the new format
    local content = extract_response_content(response_data)
    if content then
        return content
    end
    
    -- If we can't extract content, return an error message
    return "I received a response but couldn't parse it properly."
end


local function main()
    local chatBox = peripheral.find("chatBox")
    if not chatBox then
        error("Could not find a 'chatBox' peripheral. Please place one next to the computer.", 0)
    end

    print("Jarvis is online. Waiting for messages.")
    print("Current bot name: " .. tools.get_bot_name())

    local messages = {
        { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Keep all answers concise and professional, as if you were a true AI assistant- overly cheerful responses are unneeded and unwanted. Refrain from using any special characters such as emojis. Also, no need to mention that we are in minecraft." }
    }
    -- Comment out tools for now to focus on basic chat
    -- local tool_schemas = tools.get_all_schemas()

    while true do
        local _, player, message_text = os.pullEvent("chat")
        local bot_name = tools.get_bot_name()

        -- Only respond if the message is addressed to the bot
        if tools.is_message_for_bot(message_text) then
            print(player .. " says: " .. message_text)
            table.insert(messages, { role = "user", content = message_text })

            -- Call the LLM (without tools for now)
            chatBox.sendMessage("Thinking...", bot_name, "<>")
            local ok, response = llm.request(config.openai_api_key, config.model, messages) -- removed tool_schemas parameter

            if not ok then
                printError("LLM Request Failed: " .. tostring(response))
                chatBox.sendMessage("Sorry, I encountered an error.", bot_name, "<>")
                table.remove(messages) -- Remove the failed user message
                goto continue
            end

            -- Process response using the new format
            local result = process_llm_response(response)
            chatBox.sendMessage(result, bot_name, "<>")
            table.insert(messages, { role = "assistant", content = result })

            --[[
            -- Comment out tool handling for now
            local result = process_llm_response(response)

            if type(result) == "table" then
                -- The LLM called a tool, so we add its output to the conversation and run again.
                for _, tool_output in ipairs(result) do
                    table.insert(messages, tool_output)
                end
                
                local final_ok, final_response = llm.request(config.openai_api_key, config.model, messages, tool_schemas)
                if final_ok then
                    local final_message = final_response.choices[1].message.content
                    chatBox.sendMessage(final_message, bot_name, "<>")  
                    table.insert(messages, { role = "assistant", content = final_message })
                else
                    printError("Second LLM Request Failed: " .. tostring(final_response))
                    chatBox.sendMessage("Sorry, I encountered an error after using my tool.", bot_name, "<>")
                end

            elseif type(result) == "string" then
                -- The LLM returned a direct message.
                chatBox.sendMessage(result, bot_name, "<>")
                table.insert(messages, { role = "assistant", content = result })
            end
            --]]

            ::continue::
        end
    end
end

main() 