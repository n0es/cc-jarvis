-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")
local chatbox_queue = require("lib.jarvis.chatbox_queue")
local debug = require("lib.jarvis.debug")

-- Load config
local CONFIG_PATH_FS = "/etc/jarvis/config.lua"
local config = {}
if fs.exists(CONFIG_PATH_FS) then
    local config_func, err = loadfile(CONFIG_PATH_FS)
    if config_func then
        config = config_func() or {}
    else
        error("Failed to load config file: " .. tostring(err), 0)
    end
else
    error("Config file not found at " .. CONFIG_PATH_FS, 0)
end

-- Validate config
if not config.gemini_api_key or config.gemini_api_key == "YOUR_GEMINI_KEY_HERE" then
    debug.warn("Gemini API key is not set. Gemini provider will not be available.")
end
if not config.openai_api_key or config.openai_api_key == "YOUR_OPENAI_KEY_HERE" then
    debug.warn("OpenAI API key is not set. OpenAI provider will not be available.")
end

-- Global state variables
local messages = {}
local listen_mode_active = false
local listen_until = 0
local chatBox -- Declare here to make it accessible in main_loop and the final pcall

-- Helper function to get the appropriate API key for the current provider
local function get_api_key_for_provider()
    local current_provider = llm.get_current_provider()
    if current_provider == "openai" then
        return config.openai_api_key
    elseif current_provider == "gemini" then
        return config.gemini_api_key
    else
        debug.error("Unknown or unconfigured provider: " .. tostring(current_provider))
        return nil
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
    local bot_name = tools.get_bot_name():lower()
    local msg_lower = message_text:lower()
    local is_mention = msg_lower:find(bot_name, 1, true) ~= nil

    if is_mention then
        listen_mode_active = true
        listen_until = os.time() + (config.listen_duration or 120)
        debug.info("Bot mentioned - entering listen mode for " .. (config.listen_duration or 120) .. " seconds")
    end

    if not listen_mode_active then
        return -- Ignore messages if not in listen mode
    end

    debug.info(username .. " says: " .. message_text)
    table.insert(messages, { role = "user", content = username .. ": " .. message_text })

    -- Request response from LLM
    debug.info("Thinking...")
    local api_key = get_api_key_for_provider()
    if not api_key then
        chatbox_queue.add_message("API key for the current provider is not configured.")
        return
    end

    local success, response_data = llm.request(api_key, config.model, messages, tools.get_all_schemas())
    
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

    -- Trim history
    local history_limit = config.history_limit or 20
    if #messages > history_limit then
        local trimmed_messages = {}
        table.insert(trimmed_messages, messages[1]) -- Keep system prompt
        for i = #messages - history_limit + 2, #messages do
            table.insert(trimmed_messages, messages[i])
        end
        messages = trimmed_messages
        debug.info("History trimmed.")
    end
end

local function initialize()
    -- Initialize modem for door control and tools
    local modem_channel = config.bot_channel or 32
    local modem = peripheral.find("modem")
    if modem and modem.isOpen(modem_channel) then
        modem.close(modem_channel)
    end
    if modem then
        modem.open(modem_channel)
        debug.info("Modem initialized on channel " .. modem_channel)
    else
        debug.warn("Modem not found. Door control and other modem-based tools will be unavailable.")
    end
    tools.set_modem(modem, modem_channel)

    -- Initialize chatbox queue
    chatbox_queue.init(config.chat_delay or 1)
    debug.info("ChatBox Queue initialized with " .. (config.chat_delay or 1) .. " second delay")
    
    -- Find chatbox peripheral
    chatBox = peripheral.find("chatBox")
    if not chatBox then
        error("ChatBox peripheral not found. Please attach a chat box.", 0)
    end

    -- Initialize message history with system prompt
    messages = {
        { role = "system", content = llm.get_system_prompt(tools.get_bot_name()) }
    }

    print("Jarvis is online. Waiting for messages.")
    debug.info("Current bot name: " .. tools.get_bot_name())
    local build_info = fs.open("/etc/jarvis/build_info.txt", "r")
    if build_info then
        debug.info("Build: " .. build_info.readAll())
        build_info.close()
    end
end

local function main_loop()
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "chat" then
            handle_chat_message(p1, p2)
        end
        
        if listen_mode_active and os.time() > listen_until then
            debug.info("Listen mode expired.")
            listen_mode_active = false
        end
        
        chatbox_queue.process(chatBox)
        
        sleep(0.1)
    end
end

-- Main execution
local ok, err = pcall(function()
    initialize()
    main_loop()
end)

if not ok then
    debug.error("A critical error occurred: " .. tostring(err))
    if chatBox then
        pcall(function() chatBox.send("I've encountered a critical error and need to shut down.") end)
    end
    printError(err)
end 