-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")
local chatbox_queue = require("lib.jarvis.chatbox_queue")
local debug = require("debug")

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
    -- Based on the actual response structure: response.output[0].content[0].text
    if response_data.output and type(response_data.output) == "table" and #response_data.output > 0 then
        local message = response_data.output[1]
        if message.content and type(message.content) == "table" and #message.content > 0 then
            local content_obj = message.content[1]
            if content_obj.text then
                return content_obj.text
            end
        end
    end
    
    -- Fallback to standard OpenAI format if available
    if response_data.choices and #response_data.choices > 0 then
        local choice = response_data.choices[1]
        if choice.message and choice.message.content then
            return choice.message.content
        end
    end
    
    return nil
end

local function process_llm_response(response_data)
    -- Try to extract content using the new format
    debug.debug("Processing LLM response...")
    local content = extract_response_content(response_data)
    if content then
        debug.debug("Successfully extracted content: " .. content)
        return content
    end
    
    -- If we can't extract content, return an error message
    debug.error("Failed to extract content from response")
    return "I received a response but couldn't parse it properly."
end


local function main()
    local chatBox = peripheral.find("chatBox")
    if not chatBox then
        error("Could not find a 'chatBox' peripheral. Please place one next to the computer.", 0)
    end

    -- Initialize the chatbox queue with 1 second delay
    chatbox_queue.init(chatBox, 1)
    
    -- Create a simple chat interface
    local chat = chatbox_queue.chat

    debug.info("Jarvis is online. Waiting for messages.")
    debug.info("Current bot name: " .. tools.get_bot_name())

    local messages = {
        { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Keep all answers concise and professional, as if you were a true AI assistant- overly cheerful responses are unneeded and unwanted. Refrain from using any special characters such as emojis. Also, no need to mention that we are in minecraft." }
    }
    -- Comment out tools for now to focus on basic chat
    -- local tool_schemas = tools.get_all_schemas()

    -- Time-based context and listening mode variables
    local CONTEXT_TIMEOUT = 5 * 60 * 20  -- 5 minutes in ticks (20 ticks per second)
    local LISTEN_MODE_TIMEOUT = 2 * 60 * 20  -- 2 minutes in ticks
    local last_message_time = os.clock() * 20  -- Convert to ticks
    local listen_mode_end_time = 0  -- When to stop listening to all messages
    local in_listen_mode = false

    -- Function to check if bot name is mentioned anywhere in message
    local function is_bot_mentioned(message)
        local bot_name = tools.get_bot_name()
        local msg_lower = message:lower()
        return msg_lower:find(bot_name, 1, true) ~= nil
    end

    -- Function to clear context if too much time has passed
    local function check_context_timeout()
        local current_time = os.clock() * 20
        if current_time - last_message_time > CONTEXT_TIMEOUT then
            debug.info("Context cleared due to timeout (" .. CONTEXT_TIMEOUT / 20 / 60 .. " minutes)")
            -- Reset to just the system message
            messages = {
                { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Keep all answers concise and professional, as if you were a true AI assistant- overly cheerful responses are unneeded and unwanted. Refrain from using any special characters such as emojis. Also, no need to mention that we are in minecraft." }
            }
            return true
        end
        return false
    end

    -- Function to check if we should listen to all messages
    local function should_listen_to_message(message)
        local current_time = os.clock() * 20
        
        -- Check if listen mode has expired
        if in_listen_mode and current_time > listen_mode_end_time then
            in_listen_mode = false
            debug.info("Listen mode ended")
        end
        
        -- If bot is mentioned, enter listen mode
        if is_bot_mentioned(message) then
            in_listen_mode = true
            listen_mode_end_time = current_time + LISTEN_MODE_TIMEOUT
            debug.info("Bot mentioned - entering listen mode for " .. LISTEN_MODE_TIMEOUT / 20 / 60 .. " minutes")
            return true
        end
        
        -- If in listen mode, listen to all messages
        if in_listen_mode then
            debug.debug("Listening due to active listen mode")
            return true
        end
        
        return false
    end

    -- Advanced chat handling variables
    local pending_messages = {}  -- Messages waiting to be processed
    local llm_request_active = false  -- Track if LLM request is in progress
    local llm_request_start_time = 0  -- When the current LLM request started
    local LLM_TIMEOUT = 30 * 20  -- 30 seconds in ticks

    while true do
        -- Process the chatbox queue
        chatbox_queue.process()
        
        -- Show queue status if there are messages waiting
        local queue_size = chatbox_queue.getQueueSize()
        if queue_size > 0 then
            debug.debug("Messages in queue: " .. queue_size)
        end
        
        -- Use timer-based event handling for proper timeout support
        local timer_id = os.startTimer(0.05)  -- 50ms timer for queue processing
        local event_data = {os.pullEvent()}
        
        if event_data[1] == "timer" and event_data[2] == timer_id then
            -- Timer event - just continue to process queue
            goto continue
        elseif event_data[1] == "chat" then
            local _, player, message_text = table.unpack(event_data)
            local bot_name = tools.get_bot_name()
            local current_time = os.clock() * 20

            -- Check for context timeout before processing message
            check_context_timeout()

            -- Check if we should respond to this message
            if should_listen_to_message(message_text) then
                debug.info(player .. " says: " .. message_text)
                
                -- Update last message time
                last_message_time = current_time
                
                -- Add message to pending queue
                table.insert(pending_messages, {
                    player = player,
                    text = message_text,
                    timestamp = current_time
                })
                
                -- If LLM is currently processing, cancel it and restart with all pending messages
                if llm_request_active then
                    debug.warn("New message received while processing. Cancelling current request...")
                    llm_request_active = false
                    -- Note: We can't actually cancel HTTP requests in ComputerCraft, 
                    -- but we'll ignore the response when it comes back
                end
                
                -- Process all pending messages
                if not llm_request_active then
                    -- Add all pending messages to conversation
                    for _, pending_msg in ipairs(pending_messages) do
                        local formatted_msg = pending_msg.player .. ": " .. pending_msg.text
                        table.insert(messages, { role = "user", content = formatted_msg })
                    end
                    
                    -- Clear pending messages
                    pending_messages = {}
                    
                    -- Start LLM request
                    llm_request_active = true
                    llm_request_start_time = current_time
                    debug.info("Thinking...")
                    
                    -- Use parallel.waitForAny to handle the LLM request with timeout
                    local function llm_task()
                        local ok, response = llm.request(config.openai_api_key, config.model, messages)
                        return ok, response
                    end
                    
                    local function timeout_task()
                        sleep(LLM_TIMEOUT / 20)  -- Convert ticks to seconds
                        return false, "timeout"
                    end
                    
                    local ok, response
                    parallel.waitForAny(
                        function()
                            ok, response = llm_task()
                        end,
                        timeout_task
                    )
                    
                    llm_request_active = false
                    
                    if not ok then
                        if response == "timeout" then
                            printError("LLM Request Timed Out")
                            chat.send("Sorry, my response took too long.")
                        else
                            printError("LLM Request Failed: " .. tostring(response))
                            chat.send("Sorry, I encountered an error.")
                        end
                        -- Remove the failed user messages
                        while #messages > 1 and messages[#messages].role == "user" do
                            table.remove(messages)
                        end
                        goto continue
                    end

                    -- Process response using the new format
                    local result = process_llm_response(response)
                    debug.debug("About to send message to chat: " .. tostring(result))
                    chat.send(tostring(result))
                    debug.debug("Message queued for chat")
                    table.insert(messages, { role = "assistant", content = result })
                end
            end
        end
        
        ::continue::
    end
end

main() 