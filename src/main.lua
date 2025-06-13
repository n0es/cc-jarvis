-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")
local chatbox_queue = require("lib.jarvis.chatbox_queue")
local debug = require("lib.jarvis.debug")

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
        "-- Bot's modem channel for door control (default: 32)",
        "config.bot_channel = 32",
        "",
        "return config",
        "--------------------------------------------------"
    }, "\n")
    error(err_msg, 0)
end

if not config.openai_api_key or config.openai_api_key == "YOUR_OPENAI_KEY_HERE" then
    error("OpenAI API key is not set in " .. CONFIG_PATH_FS .. ". Please add your OpenAI API key.", 0)
end

if not config.gemini_api_key or config.gemini_api_key == "YOUR_GEMINI_KEY_HERE" then
    error("Gemini API key is not set in " .. CONFIG_PATH_FS .. ". Please add your Gemini API key.", 0)
end

-- Helper function to get the appropriate API key for the current provider
local function get_api_key_for_provider()
    local current_provider = llm.get_current_provider()
    if current_provider == "openai" then
        return config.openai_api_key
    elseif current_provider == "gemini" then
        return config.gemini_api_key
    else
        error("Unknown provider: " .. tostring(current_provider), 0)
    end
end

local function process_llm_response(response_parts, messages_history)
    debug.debug("Processing LLM response with " .. #response_parts .. " parts...")
    if #response_parts == 0 then
        debug.error("LLM response was empty.")
        chatbox_queue.add_message("I'm sorry, I seem to be having trouble thinking straight right now.")
        return
    end

    local assistant_message_content = {} -- Collects text parts for a single assistant message
    local tool_calls_for_this_turn = {}

    for _, part in ipairs(response_parts) do
        if part.type == "message" then
            debug.info("LLM response part: message")
            chatbox_queue.add_message(part.content)
            table.insert(assistant_message_content, part.content)

        elseif part.type == "tool_call" then
            debug.info("LLM response part: tool_call - " .. part.tool_name)
            
            local tool_func = tools.get_tool(part.tool_name)
            local tool_call_id = "call_" .. os.epoch("utc") .. math.random(1000, 9999)
            
            table.insert(tool_calls_for_this_turn, {
                id = tool_call_id,
                type = "function",
                ["function"] = {
                    name = part.tool_name,
                    arguments = part.tool_args_json or "{}"
                }
            })
            
            if not tool_func then
                local error_msg = "Unknown tool: " .. part.tool_name
                debug.error(error_msg)
                table.insert(messages_history, {
                    tool_call_id = tool_call_id,
                    role = "tool",
                    content = error_msg
                })
            else
                local arguments = textutils.unserializeJSON(part.tool_args_json or "{}") or {}
                local success, result = pcall(tool_func, arguments)
                local result_text = ""

                if success then
                    result_text = type(result) == "table" and textutils.serializeJSON(result) or tostring(result)
                    debug.info("Tool " .. part.tool_name .. " executed successfully. Result: " .. result_text)
                    if type(result) == "table" and result.message then
                        chatbox_queue.add_message(result.message)
                    end
                else
                    result_text = "Tool execution failed: " .. tostring(result)
                    debug.error(result_text)
                    chatbox_queue.add_message(result_text)
                end
                table.insert(messages_history, {
                    tool_call_id = tool_call_id,
                    role = "tool",
                    content = result_text
                })
            end
        end
    end
    
    -- Store the assistant's turn (text and tool calls combined)
    if #assistant_message_content > 0 or #tool_calls_for_this_turn > 0 then
        table.insert(messages_history, {
            role = "assistant",
            content = table.concat(assistant_message_content, " "),
            tool_calls = #tool_calls_for_this_turn > 0 and tool_calls_for_this_turn or nil
        })
        debug.debug("Stored assistant message to history.")
    end
end

local function handle_chat_message(username, message_text)
    -- Check if the bot was mentioned or if it should be actively listening
    local bot_name = tools.get_bot_name()
    local msg_lower = message_text:lower()
    if msg_lower:find(bot_name, 1, true) ~= nil then
        debug.info("Bot mentioned - entering listen mode")
        -- Enter listen mode
        -- Implement listen mode logic here
    else
        debug.info("Thinking...")
        local success, response_data = llm.request(get_api_key_for_provider(), config.model, messages, tools.get_tools())
        
        if success then
            process_llm_response(response_data, messages)
        else
            local error_message = "Sorry, I encountered an error."
            if type(response_data) == "string" then
                error_message = response_data
            end
            chatbox_queue.add_message(error_message)
            debug.error("LLM request failed: " .. error_message)
        end
    end

    -- Trim history if it gets too long
    if #messages > (config.history_limit or 20) then
        local trimmed_messages = {}
        table.insert(trimmed_messages, messages[1]) -- Keep system prompt
        for i = #messages - (config.history_limit or 20) + 2, #messages do
            table.insert(trimmed_messages, messages[i])
        end
        messages = trimmed_messages
        debug.info("History trimmed.")
    end
end

local function initialize()
    local chatBox = peripheral.find("chatBox")
    if not chatBox then
        error("Could not find a 'chatBox' peripheral. Please place one next to the computer.", 0)
    end

    local modem = peripheral.find("modem")
    if not modem then
        error("Could not find a 'modem' peripheral. Please place one next to the computer.", 0)
    end

    -- Open the bot's channel for listening
    local bot_channel = config.bot_channel or 32
    modem.open(bot_channel)
    debug.info("Modem initialized on channel " .. bot_channel)

    -- Initialize the chatbox queue with 1 second delay
    chatbox_queue.init(chatBox, 1)
    
    -- Create a simple chat interface
    local chat = chatbox_queue.chat

    debug.info("Jarvis is online. Waiting for messages.")
    debug.info("Current bot name: " .. tools.get_bot_name())
    debug.info("Build: #{{BUILD_NUMBER}} ({{BUILD_DATE}})")

    local messages = {
        { role = "system", content = llm.get_system_prompt(tools.get_bot_name()) }
    }
    -- Initialize tools with modem access
    tools.set_modem(modem, bot_channel)
    
    -- Get available tool schemas for the LLM  
    local tool_schemas = tools.get_all_schemas()

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
                { role = "system", content = llm.get_system_prompt(tools.get_bot_name()) }
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
                        local ok, response = llm.request(get_api_key_for_provider(), config.model, messages, tool_schemas)
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
                    process_llm_response(response, messages)
                    
                    -- Trim history if it gets too long
                    if #messages > (config.history_limit or 20) then
                        local trimmed_messages = {}
                        table.insert(trimmed_messages, messages[1]) -- Keep system prompt
                        for i = #messages - (config.history_limit or 20) + 2, #messages do
                            table.insert(trimmed_messages, messages[i])
                        end
                        messages = trimmed_messages
                        debug.info("History trimmed.")
                    end
                end
            end
        end
        
        ::continue::
    end
end

initialize() 