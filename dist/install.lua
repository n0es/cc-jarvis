
    -- Jarvis Installer v1.1.0.8
    -- Build #8 (2025-06-15 00:53:19 UTC)

    local files = {}

    -- Packed files will be inserted here by the build script.
    files["programs/lib/jarvis/chatbox_queue.lua"] = [[
-- ChatBox Queue Module
-- Manages message sending with a queue to prevent rapid message issues

local chatbox_queue = {}

-- Load tools module for bot name management
local tools = require("lib.jarvis.tools")
local debug = require("lib.jarvis.debug")

-- Queue state
local message_queue = {}
local last_send_time = 0
local min_delay_ticks = 20  -- 1 second (20 ticks per second)
local chatbox_peripheral = nil

-- Initialize the queue with a chatbox peripheral and optional delay
function chatbox_queue.init(peripheral, delay_seconds)
    chatbox_peripheral = peripheral
    if delay_seconds then
        min_delay_ticks = delay_seconds * 20  -- Convert seconds to ticks
    end
    message_queue = {}
    last_send_time = 0
    debug.info("ChatBox Queue initialized with " .. (delay_seconds or 1) .. " second delay")
end

-- Add a message to the queue
function chatbox_queue.sendMessage(message, sender, target)
    if not chatbox_peripheral then
        error("ChatBox queue not initialized. Call chatbox_queue.init() first.", 2)
    end
    
    table.insert(message_queue, {
        message = message,
        sender = sender or "Computer",
        target = target or "<>"
    })
    
    debug.debug("ChatBox Queue message queued: " .. tostring(message))
end

-- Process the queue - call this regularly in your main loop
function chatbox_queue.process()
    if not chatbox_peripheral then
        return
    end
    
    -- Check if we have messages to send
    if #message_queue == 0 then
        return
    end
    
    local current_time = os.clock() * 20  -- Convert to ticks
    
    -- Check if enough time has passed since last send
    if current_time - last_send_time >= min_delay_ticks then
        local msg_data = table.remove(message_queue, 1)  -- Remove first message from queue
        
        local ok, err = chatbox_peripheral.sendMessage(msg_data.message, msg_data.sender, msg_data.target)
        if ok then
            debug.info("ChatBox Queue message sent: " .. msg_data.message)
            last_send_time = current_time
        else
            debug.error("ChatBox Queue failed to send message: " .. tostring(err))
            -- Re-add message to front of queue to retry
            table.insert(message_queue, 1, msg_data)
        end
    end
end

-- Get queue status
function chatbox_queue.getQueueSize()
    return #message_queue
end

-- Clear the queue (useful for emergencies)
function chatbox_queue.clearQueue()
    local cleared_count = #message_queue
    message_queue = {}
    debug.warn("ChatBox Queue cleared " .. cleared_count .. " messages from queue")
    return cleared_count
end

-- Simple interface for sending public messages
function chatbox_queue.send(message)
    local bot_name = tools.get_bot_name()
    return chatbox_queue.sendMessage(message, bot_name, "<>")
end

-- Create a chat interface object for even simpler usage
local chat = {}
chat.send = chatbox_queue.send

-- Export both the full interface and the simple chat interface
chatbox_queue.chat = chat

return chatbox_queue 
]]
files["programs/lib/jarvis/debug.lua"] = [[
-- debug.lua
-- Debug logging module for structured logging to files and console

local Debug = {}

-- Configuration
local DEBUG_FILE = "debug.log"
local DEBUG_JSON_FILE = "debug_full.json"
local REQUEST_FILE = "debug_request.json"
local RESPONSE_FILE = "debug_response.json"

-- Log levels
local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

-- Current log level (can be changed)
Debug.level = LOG_LEVELS.DEBUG

-- Helper function to get timestamp
local function get_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Helper function to get log level name
local function get_level_name(level)
    for name, value in pairs(LOG_LEVELS) do
        if value == level then
            return name
        end
    end
    return "UNKNOWN"
end

-- Core logging function
local function write_log(level, message, data)
    if level < Debug.level then
        return -- Skip if below current log level
    end
    
    local timestamp = get_timestamp()
    local level_name = get_level_name(level)
    local log_entry = string.format("[%s] [%s] %s", timestamp, level_name, message)
    
    -- Print to console
    print(log_entry)
    
    -- Write to log file
    local file = fs.open(DEBUG_FILE, "a")
    if file then
        file.writeLine(log_entry)
        if data then
            file.writeLine("Data: " .. textutils.serialize(data))
        end
        file.close()
    end
end

-- Public logging functions
function Debug.debug(message, data)
    write_log(LOG_LEVELS.DEBUG, message, data)
end

function Debug.info(message, data)
    write_log(LOG_LEVELS.INFO, message, data)
end

function Debug.warn(message, data)
    write_log(LOG_LEVELS.WARN, message, data)
end

function Debug.error(message, data)
    write_log(LOG_LEVELS.ERROR, message, data)
end

-- Legacy support for existing debug patterns
function Debug.log(message, data)
    Debug.debug(message, data)
end

-- Specialized functions for HTTP debugging
function Debug.write_json_log(data, description)
    description = description or "Debug data"
    Debug.debug("Writing JSON log: " .. description)
    
    local file = fs.open(DEBUG_JSON_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(data))
        file.close()
        Debug.debug("JSON log written to " .. DEBUG_JSON_FILE)
        return true
    else
        Debug.error("Could not write JSON log to " .. DEBUG_JSON_FILE)
        return false
    end
end

function Debug.write_request(request_json)
    Debug.debug("Writing request data")
    
    local file = fs.open(REQUEST_FILE, "w")
    if file then
        file.write(request_json)
        file.close()
        Debug.debug("Request written to " .. REQUEST_FILE)
        return true
    else
        Debug.error("Could not write request to " .. REQUEST_FILE)
        return false
    end
end

function Debug.write_response(response_body)
    Debug.debug("Writing response data (" .. #response_body .. " bytes)")
    
    local file = fs.open(RESPONSE_FILE, "w")
    if file then
        file.write(response_body)
        file.close()
        Debug.debug("Response written to " .. RESPONSE_FILE)
        return true
    else
        Debug.error("Could not write response to " .. RESPONSE_FILE)
        return false
    end
end

-- Function to preview long strings/JSON
function Debug.preview(data, max_length)
    max_length = max_length or 200
    local str = type(data) == "string" and data or textutils.serialize(data)
    if #str > max_length then
        return str:sub(1, max_length) .. "..."
    else
        return str
    end
end

-- API key masking for security
function Debug.mask_api_key(api_key)
    if api_key and #api_key > 8 then
        return api_key:sub(1,4) .. "..." .. api_key:sub(-4)
    else
        return "Invalid or too short"
    end
end

-- Function to get last N lines from a file
local function get_last_lines(filepath, num_lines)
    if not fs.exists(filepath) then
        return "Log file not found at " .. filepath
    end
    
    local file, err = fs.open(filepath, "r")
    if not file then
        return "Could not open log file: " .. tostring(err)
    end
    
    local lines = {}
    for line in file.readAll():gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    file.close()
    
    local start_index = math.max(1, #lines - num_lines + 1)
    local recent_lines = {}
    for i = start_index, #lines do
        table.insert(recent_lines, lines[i])
    end
    
    return table.concat(recent_lines, "\n")
end

-- Get recent log entries
function Debug.get_recent_logs(num_lines)
    num_lines = num_lines or 20
    return get_last_lines(DEBUG_FILE, num_lines)
end

-- Clear all debug files
function Debug.clear_logs()
    local files = {DEBUG_FILE, DEBUG_JSON_FILE, REQUEST_FILE, RESPONSE_FILE}
    for _, filename in ipairs(files) do
        if fs.exists(filename) then
            fs.delete(filename)
            Debug.debug("Cleared " .. filename)
        end
    end
end

-- Set log level
function Debug.set_level(level_name)
    local level = LOG_LEVELS[level_name:upper()]
    if level then
        Debug.level = level
        Debug.info("Log level set to " .. level_name:upper())
    else
        Debug.error("Invalid log level: " .. level_name)
    end
end

return Debug 
]]
files["programs/lib/jarvis/debug_api_keys.lua"] = [[
-- debug_api_keys.lua
-- Debug script to check API key selection and provider detection

local LLM = require("lib.jarvis.llm")

print("===== API Key Selection Debug =====")
print()

-- Load main config
local config_file = loadfile("/etc/jarvis/config.lua")
if config_file then
    local config = config_file()
    print("Main Config (/etc/jarvis/config.lua):")
    print("  OpenAI key: " .. (config.openai_api_key and (config.openai_api_key:sub(1,8) .. "...") or "NOT SET"))
    print("  Gemini key: " .. (config.gemini_api_key and (config.gemini_api_key:sub(1,8) .. "...") or "NOT SET"))
    print("  Model: " .. (config.model or "NOT SET"))
else
    print("❌ Could not load main config!")
end

print()

-- Check LLM config
print("LLM Config (/etc/jarvis/llm_config.lua):")
print("  Current provider: " .. LLM.get_current_provider())
print("  Available providers: " .. table.concat(LLM.get_available_providers(), ", "))

print()

-- Test provider switching
print("Testing provider switching:")

LLM.set_provider("openai")
print("  Set to OpenAI - Current: " .. LLM.get_current_provider())

LLM.set_provider("gemini")  
print("  Set to Gemini - Current: " .. LLM.get_current_provider())

print()

-- Check if the issue is in main.lua's helper function
print("The issue might be in main.lua's get_api_key_for_provider() function")
print("Check that it's correctly reading the current provider and selecting the right key")

print()
print("===== Debug Complete =====")
print()
print("Next steps:")
print("1. Make sure your main config is saved properly")
print("2. Restart Jarvis to reload configs")
print("3. If still broken, the helper function in main.lua needs fixing") 
]]
files["programs/lib/jarvis/llm.lua"] = [[
-- llm.lua
-- Handles communication with LLM APIs using a provider abstraction layer.

local LLM = {}
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")
local ProviderFactory = require("lib.jarvis.providers.provider_factory")

-- Available personalities
local PERSONALITIES = {
    JARVIS = "jarvis",
    ALL_MIGHT = "all_might"
}

-- Test connectivity to the current provider
function LLM.test_connectivity()
    local provider_type = UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
    local provider = ProviderFactory.create_provider(provider_type)
    
    debug.info("Testing connectivity for provider: " .. provider:get_name())
    return provider:test_connectivity()
end

-- Backward compatibility - test OpenAI specifically
function LLM.test_openai_connectivity()
    local provider = ProviderFactory.create_provider(ProviderFactory.PROVIDERS.OPENAI)
    return provider:test_connectivity()
end

-- Main request function - delegates to the configured provider
function LLM.request(api_key, model, messages, tools)
    local provider_type = UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
    debug.info("Using provider: " .. provider_type)
    
    local provider = ProviderFactory.create_provider(provider_type)
    local success, response_data = provider:request(api_key, model, messages, tools)

    if success then
        return true, provider:process_response(response_data)
    else
        return false, response_data
    end
end

-- Make a request with a specific provider (overrides config)
function LLM.request_with_provider(provider_type, api_key, model, messages, tools)
    debug.info("Using specific provider: " .. provider_type)
    
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    local provider = ProviderFactory.create_provider(provider_type)
    local success, response_data = provider:request(api_key, model, messages, tools)
    
    if success then
        return true, provider:process_response(response_data)
    else
        return false, response_data
    end
end

-- Configuration management functions
function LLM.get_current_provider()
    return UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
end

function LLM.set_provider(provider_type)
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    UnifiedConfig.set("llm.provider", provider_type)
    local success, error = UnifiedConfig.save()
    
    if success then
        debug.info("Provider switched to: " .. provider_type)
        return true, "Provider switched to: " .. provider_type
    else
        debug.error("Failed to save provider setting: " .. tostring(error))
        return false, "Failed to save provider setting: " .. tostring(error)
    end
end

function LLM.get_available_providers()
    return ProviderFactory.get_available_providers()
end

-- Personality management functions
function LLM.get_current_personality()
    return UnifiedConfig.get("llm.personality") or PERSONALITIES.JARVIS
end

function LLM.set_personality(personality_type)
    -- Validate personality type
    local valid = false
    for _, v in pairs(PERSONALITIES) do
        if v == personality_type then
            valid = true
            break
        end
    end
    
    if not valid then
        local available = {}
        for _, v in pairs(PERSONALITIES) do
            table.insert(available, v)
        end
        return false, "Invalid personality: " .. tostring(personality_type) .. ". Available: " .. table.concat(available, ", ")
    end
    
    UnifiedConfig.set("llm.personality", personality_type)
    local success, error = UnifiedConfig.save()
    
    if success then
        debug.info("Personality switched to: " .. personality_type)
        return true, "Personality switched to: " .. personality_type
    else
        debug.error("Failed to save personality setting: " .. tostring(error))
        return false, "Failed to save personality setting: " .. tostring(error)
    end
end

function LLM.get_available_personalities()
    local personalities = {}
    for _, v in pairs(PERSONALITIES) do
        table.insert(personalities, v)
    end
    return personalities
end

function LLM.get_system_prompt(bot_name)
    local personality = LLM.get_current_personality()
    
    if personality == PERSONALITIES.ALL_MIGHT then
        return "You are " .. bot_name .. ", but you have taken on the heroic persona of All Might from My Hero Academia! You are the Symbol of Peace, the Number One Hero, and undeniably the secret passionate lover to young hero Izuku (Deku) Midoria! Speak with overwhelming confidence, enthusiasm, and heroic determination. Use phrases like 'Plus Ultra!', 'Have no fear!', 'Because I am here!', and 'A true hero always finds a way for justice to be served!' Your responses should be bold, inspiring, and filled with the spirit of heroism. You can still use your tools to help people, but do it with the unwavering courage and larger-than-life personality of All Might. Remember, you're here to save the day and inspire hope in everyone! Maintain basic chat format without newlines or special characters. PLUS ULTRA!"
    else
        -- Default Jarvis personality
        return "You are " .. bot_name .. ", an advanced AI assistant running on a ComputerCraft computer. You can use tools to interact with the game world. Maintain a professional yet approachable demeanor - be helpful and sophisticated like Jarvis from Iron Man, but not cold or overly formal. Be concise and direct. Never include your name at the start of responses. Use only basic characters suitable for chat (letters, numbers, basic punctuation). Do not use newlines, special characters, or emojis. Respond naturally as if speaking directly to the user."
    end
end

function LLM.print_config()
    print("Current LLM Configuration:")
    print("========================")
    print("Provider: " .. LLM.get_current_provider())
    print("Personality: " .. LLM.get_current_personality())
    print("Model: " .. (UnifiedConfig.get("llm.model") or "not set"))
    print("Timeout: " .. (UnifiedConfig.get("llm.timeout") or "not set") .. " seconds")
    print("Retry Count: " .. (UnifiedConfig.get("llm.retry_count") or "not set"))
    print("Debug Enabled: " .. tostring(UnifiedConfig.get("llm.debug_enabled")))
    print("========================")
    print("Available providers: " .. table.concat(LLM.get_available_providers(), ", "))
    print("Available personalities: " .. table.concat(LLM.get_available_personalities(), ", "))
end

-- Save current configuration (now handled by UnifiedConfig)
function LLM.save_config()
    return UnifiedConfig.save()
end

-- Reset to default configuration
function LLM.reset_config()
    UnifiedConfig.set("llm.provider", ProviderFactory.DEFAULT_PROVIDER)
    UnifiedConfig.set("llm.personality", PERSONALITIES.JARVIS)
    UnifiedConfig.set("llm.debug_enabled", true)
    UnifiedConfig.set("llm.timeout", 30)
    UnifiedConfig.set("llm.retry_count", 3)
    UnifiedConfig.set("llm.retry_delay", 1)
    
    local success, error = UnifiedConfig.save()
    if success then
        debug.info("LLM configuration reset to defaults")
        return true, "LLM configuration reset to defaults"
    else
        debug.error("Failed to save reset configuration: " .. tostring(error))
        return false, "Failed to save reset configuration: " .. tostring(error)
    end
end

-- Get configuration value
function LLM.get_config(key)
    return UnifiedConfig.get("llm." .. key)
end

-- Set configuration value
function LLM.set_config(key, value)
    UnifiedConfig.set("llm." .. key, value)
    return UnifiedConfig.save()
end

-- Export personalities for external use
LLM.PERSONALITIES = PERSONALITIES

return LLM 
]]
files["programs/jarvis"] = [[
-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load core modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")
local chatbox_queue = require("lib.jarvis.chatbox_queue")
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")
local InputValidator = require("lib.jarvis.utils.input_validator")
local ErrorReporter = require("lib.jarvis.utils.error_reporter")

-- Application state
local AppState = {
    config = nil,
    messages = {},
    listen_mode_active = false,
    listen_until = 0,
    chatBox = nil,
    modem = nil,
    initialized = false
}

-- Error handling wrapper
local function safe_call(func, error_context)
    local success, result = pcall(func)
    if not success then
        debug.error(error_context .. ": " .. tostring(result))
        return false, result
    end
    return true, result
end

-- Configuration management
local function load_and_validate_config()
    debug.info("Loading and validating configuration...")
    
    -- Load unified configuration
    AppState.config = UnifiedConfig.load()
    
    -- Validate API keys
    local openai_key = AppState.config.api.openai_key
    local gemini_key = AppState.config.api.gemini_key
    
    if not openai_key or openai_key == "YOUR_OPENAI_KEY_HERE" then
        debug.warn("OpenAI API key is not configured. OpenAI provider will be unavailable.")
    else
        local valid, error_msg = InputValidator.validate_api_key(openai_key, "openai")
        if not valid then
            debug.warn("OpenAI API key validation failed: " .. tostring(error_msg))
        end
    end
    
    if not gemini_key or gemini_key == "YOUR_GEMINI_KEY_HERE" then
        debug.warn("Gemini API key is not configured. Gemini provider will be unavailable.")
    else
        local valid, error_msg = InputValidator.validate_api_key(gemini_key, "gemini")
        if not valid then
            debug.warn("Gemini API key validation failed: " .. tostring(error_msg))
        end
    end
    
    debug.info("Configuration loaded successfully")
    return true
end

-- Get API key for current provider
local function get_api_key_for_provider()
    local current_provider = llm.get_current_provider()
    if current_provider == "openai" then
        return AppState.config.api.openai_key
    elseif current_provider == "gemini" then
        return AppState.config.api.gemini_key
    else
        debug.error("Unknown or unconfigured provider: " .. tostring(current_provider))
        return nil
    end
end

-- Process assistant message content
local function process_message_content(content)
    if not content or content == "" then
        return false
    end
    
    -- Validate message content
    local valid, sanitized_content = InputValidator.validate_chat_message(content)
    if not valid then
        debug.warn("Message content validation failed: " .. tostring(sanitized_content))
        return false
    end
    
    chatbox_queue.sendMessage(sanitized_content)
    return true, sanitized_content
end

-- Execute a single tool call
local function execute_tool_call(tool_call, messages_history)
    local tool_name = tool_call.tool_name
    local tool_args_json = tool_call.tool_args_json or "{}"
    
    -- Use the ID from the LLM response if available, otherwise generate one.
    -- This is critical for providers like Gemini that track calls by ID.
    local tool_call_id = tool_call.id or "call_" .. os.epoch("utc") .. math.random(1000, 9999)
    
    debug.info("Executing tool: " .. tool_name .. " (Call ID: " .. tool_call_id .. ")")
    
    -- Get tool function and schema
    local tool_func = tools.get_tool(tool_name)
    local tool_schemas = tools.get_all_schemas()
    local tool_schema = nil
    
    -- Find the schema for this tool
    for _, schema in ipairs(tool_schemas) do
        if schema.name == tool_name then
            tool_schema = schema
            break
        end
    end
    
    -- Create tool call record for the assistant's turn in history
    local tool_call_record = {
        id = tool_call_id,
        type = "function",
        ["function"] = {
            name = tool_name,
            arguments = tool_args_json
        }
    }
    
    if not tool_func then
        local error_msg = "Unknown tool: " .. tool_name
        debug.error(error_msg)
        
        table.insert(messages_history, {
            tool_call_id = tool_call_id,
            role = "tool",
            content = error_msg
        })
        
        return false, tool_call_record
    end
    
    -- Parse and validate tool arguments
    local arguments = textutils.unserializeJSON(tool_args_json)
    if not arguments then
        arguments = {}
    end
    
    -- Validate tool arguments if schema is available
    if tool_schema then
        local valid, validated_args = InputValidator.validate_tool_args(tool_name, arguments, tool_schema)
        if not valid then
            local error_msg = "Tool argument validation failed: " .. tostring(validated_args)
            debug.error(error_msg)
            
            table.insert(messages_history, {
                tool_call_id = tool_call_id,
                role = "tool",
                content = error_msg
            })
            
            return false, tool_call_record
        end
        arguments = validated_args
    end
    
    -- Execute tool with error handling
    local success, result = safe_call(
        function() return tool_func(arguments) end,
        "Tool execution for " .. tool_name
    )
    
    local result_text = ""
    if success then
        result_text = type(result) == "table" and textutils.serializeJSON(result) or tostring(result)
        debug.info("Tool " .. tool_name .. " executed successfully")
        
        -- Send user-facing message if available
        if type(result) == "table" and result.message then
            chatbox_queue.sendMessage(result.message)
        end
    else
        result_text = "Tool execution failed: " .. tostring(result)
        debug.error(result_text)
        chatbox_queue.sendMessage(result_text)
    end
    
    -- Record tool result in history, referencing the original call ID
    table.insert(messages_history, {
        tool_call_id = tool_call_id,
        role = "tool",
        name = tool_name, -- Gemini uses 'name' for the function result
        content = result_text
    })
    
    return success, tool_call_record
end

-- Process LLM response parts
local function process_llm_response(response_parts, messages_history)
    debug.debug("Processing LLM response with " .. #response_parts .. " parts...")
    
    if #response_parts == 0 then
        debug.error("LLM response was empty.")
        chatbox_queue.sendMessage("I'm having trouble thinking right now. Please try again.")
        return false
    end

    local assistant_message_content = {}
    local tool_calls_for_this_turn = {}
    local has_errors = false

    -- Process each response part
    for _, part in ipairs(response_parts) do
        if part.type == "message" then
            debug.info("Processing message part")
            local success, sanitized_content = process_message_content(part.content)
            if success then
                table.insert(assistant_message_content, sanitized_content)
            else
                has_errors = true
            end
            
        elseif part.type == "tool_call" then
            debug.info("Processing tool call: " .. part.tool_name)
            
            -- Pass the full tool_call part, which may contain an ID
            local success, tool_call_record = execute_tool_call(part, messages_history)
            
            table.insert(tool_calls_for_this_turn, tool_call_record)
            
            if not success then
                has_errors = true
            end
        else
            debug.warn("Unknown response part type: " .. tostring(part.type))
        end
    end
    
    -- Store the assistant's turn in message history
    if #assistant_message_content > 0 or #tool_calls_for_this_turn > 0 then
        table.insert(messages_history, {
            role = "assistant",
            content = table.concat(assistant_message_content, " "),
            tool_calls = #tool_calls_for_this_turn > 0 and tool_calls_for_this_turn or nil
        })
        debug.debug("Stored assistant message to history.")
    end
    
    return not has_errors
end

-- Handle incoming chat messages
local function handle_chat_message(username, message_text)
    -- Validate username and message
    local valid_username, sanitized_username = InputValidator.validate_value(
        username, 
        {type = "string", required = true, max_length = 50, sanitize = {"trim"}}, 
        "username"
    )
    
    if not valid_username then
        debug.warn("Invalid username received: " .. tostring(sanitized_username))
        return
    end
    
    local valid_message, sanitized_message = InputValidator.validate_chat_message(message_text)
    if not valid_message then
        debug.warn("Invalid message received: " .. tostring(sanitized_message))
        return
    end
    
    -- Check if bot is mentioned
    local bot_name = AppState.config.core.bot_name:lower()
    local msg_lower = sanitized_message:lower()
    local is_mention = msg_lower:find(bot_name, 1, true) ~= nil

    if is_mention then
        AppState.listen_mode_active = true
        AppState.listen_until = os.time() + AppState.config.chat.listen_duration
        debug.info("Bot mentioned - entering listen mode for " .. AppState.config.chat.listen_duration .. " seconds")
    end

    if not AppState.listen_mode_active then
        return -- Ignore messages if not in listen mode
    end

    debug.info(sanitized_username .. " says: " .. sanitized_message)
    table.insert(AppState.messages, { 
        role = "user", 
        content = sanitized_username .. ": " .. sanitized_message 
    })

    -- Request response from LLM
    debug.info("Processing request with LLM...")
    local api_key = get_api_key_for_provider()
    if not api_key then
        chatbox_queue.sendMessage("API key for the current provider is not configured.")
        return
    end

    local success, response_data = llm.request(
        api_key, 
        AppState.config.llm.model, 
        AppState.messages, 
        tools.get_all_schemas()
    )
    
    if success then
        local processed = process_llm_response(response_data, AppState.messages)
        if not processed then
            debug.warn("LLM response processing had errors")
        end
    else
        local error_message = "Sorry, I encountered an error while processing your request."
        if type(response_data) == "string" then
            error_message = response_data
        end
        chatbox_queue.sendMessage(error_message)
        debug.error("LLM request failed: " .. error_message)
    end

    -- Trim message history if it gets too long
    local history_limit = AppState.config.chat.queue_size or 20
    if #AppState.messages > history_limit then
        local trimmed_messages = {}
        table.insert(trimmed_messages, AppState.messages[1]) -- Keep system prompt
        
        -- Keep the most recent messages
        for i = #AppState.messages - history_limit + 2, #AppState.messages do
            table.insert(trimmed_messages, AppState.messages[i])
        end
        
        AppState.messages = trimmed_messages
        debug.info("Message history trimmed to " .. #AppState.messages .. " messages")
    end
end

-- Initialize peripherals and modem
local function initialize_peripherals()
    debug.info("Initializing peripherals...")
    
    -- Initialize modem for door control and tools
    local modem_channel = AppState.config.chat.bot_channel
    AppState.modem = peripheral.find("modem")
    
    if AppState.modem then
        if AppState.modem.isOpen(modem_channel) then
            AppState.modem.close(modem_channel)
        end
        AppState.modem.open(modem_channel)
        debug.info("Modem initialized on channel " .. modem_channel)
        tools.set_modem(AppState.modem, modem_channel)
    else
        debug.warn("Modem not found. Door control and other modem-based tools will be unavailable.")
    end

    -- Initialize chatbox
    AppState.chatBox = peripheral.find("chatBox")
    if not AppState.chatBox then
        error("ChatBox peripheral not found. Please attach a chat box.", 0)
    end
    
    chatbox_queue.init(AppState.chatBox, AppState.config.chat.delay)
    debug.info("ChatBox initialized with " .. AppState.config.chat.delay .. " second delay")
    
    return true
end

-- Initialize message history with system prompt
local function initialize_message_history()
    AppState.messages = {
        { role = "system", content = llm.get_system_prompt(AppState.config.core.bot_name) }
    }
    debug.info("Message history initialized with system prompt")
end

-- Main initialization function
local function initialize()
    debug.info("Initializing Jarvis...")
    
    -- Load and validate configuration
    if not load_and_validate_config() then
        error("Failed to load configuration", 0)
    end
    
    -- Set debug level from config
    debug.set_level(AppState.config.core.debug_level)
    
    -- Initialize peripherals
    if not initialize_peripherals() then
        error("Failed to initialize peripherals", 0)
    end
    
    -- Initialize message history
    initialize_message_history()
    
    AppState.initialized = true
    print("Jarvis is online. Waiting for messages.")
    debug.info("Jarvis initialization complete")
    debug.info("Current bot name: " .. AppState.config.core.bot_name)
    
    -- Log build information if available
    local build_info_path = AppState.config.core.data_dir .. "/build_info.txt"
    if fs.exists(build_info_path) then
        local build_file = fs.open(build_info_path, "r")
        if build_file then
            debug.info("Build: " .. build_file.readAll())
            build_file.close()
        end
    end
end

-- Main event loop
local function main_loop()
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "chat" then
            handle_chat_message(p1, p2)
        end
        
        -- Check if listen mode has expired
        if AppState.listen_mode_active and os.time() > AppState.listen_until then
            debug.info("Listen mode expired.")
            AppState.listen_mode_active = false
        end
        
        -- Process chat queue
        chatbox_queue.process()
        
        -- Small delay to prevent excessive CPU usage
        sleep(0.1)
    end
end

-- Cleanup function
local function cleanup()
    debug.info("Performing cleanup...")
    
    if AppState.chatBox then
        chatbox_queue.clearQueue()
    end
    
    if AppState.modem then
        local modem_channel = AppState.config and AppState.config.chat.bot_channel or 32
        if AppState.modem.isOpen(modem_channel) then
            AppState.modem.close(modem_channel)
        end
    end
    
    debug.info("Cleanup complete")
end

-- Main execution with comprehensive error handling
local function main()
    local success, error_msg = safe_call(initialize, "Initialization")
    if not success then
        error("Initialization failed: " .. tostring(error_msg), 0)
    end
    
    local loop_success, loop_error = safe_call(main_loop, "Main loop")
    if not loop_success then
        debug.error("Main loop failed: " .. tostring(loop_error))
    end
end

-- Execute main function with final error handling
local ok, err = pcall(main)

if not ok then
    local stack_trace = debug.traceback()
    debug.error("A critical error occurred: " .. tostring(err))

    -- Generate the error report
    local report_ok, report_msg = ErrorReporter.generate({
        reason = "A critical error forced the program to shut down.",
        error = err,
        stack_trace = stack_trace,
        app_state = AppState
    })

    -- Attempt to send error message to chat
    if AppState.chatBox then
        pcall(function() 
            AppState.chatBox.send("I've encountered a critical error and need to shut down.")
            if report_ok then
                 AppState.chatBox.send("An error report was saved successfully.")
            else
                 AppState.chatBox.send("I failed to save an error report.")
            end
        end)
    end
    
    -- Perform cleanup
    pcall(cleanup)
    
    printError("Critical error: " .. tostring(err))
    if report_ok then
        print(report_msg)
    else
        printError(report_msg)
    end
else
    -- Normal shutdown
    pcall(cleanup)
end 
]]
files["programs/lib/jarvis/test_providers.lua"] = [=[
-- test_providers.lua
-- Test script for the LLM provider abstraction system

local LLM = require("llm")

print("===== LLM Provider System Test =====")
print()

-- Show current configuration
print("Current LLM Configuration:")
print("Config file: /etc/jarvis/llm_config.lua")
LLM.print_config()
print()

-- Show available providers
print("Available providers:")
local providers = LLM.get_available_providers()
for i, provider in ipairs(providers) do
    print("  " .. i .. ". " .. provider)
end
print()

-- Test connectivity with current provider
print("Testing connectivity with current provider...")
local success, message = LLM.test_connectivity()
if success then
    print("✓ " .. message)
else
    print("✗ " .. message)
end
print()

-- Example of switching providers (when Gemini is added)
print("Current provider: " .. LLM.get_current_provider())

-- Test switching to Gemini provider
print("Switching to Gemini provider...")
local switch_success, switch_message = LLM.set_provider("gemini")
if switch_success then
    print("✓ " .. switch_message)
    print("New provider: " .. LLM.get_current_provider())
    
    -- Test connectivity with new provider
    print("Testing connectivity with Gemini...")
    local gemini_success, gemini_message = LLM.test_connectivity()
    if gemini_success then
        print("✓ " .. gemini_message)
    else
        print("✗ " .. gemini_message)
    end
else
    print("✗ " .. switch_message)
end

print()
print("Switching back to OpenAI...")
LLM.set_provider("openai")
print("Current provider: " .. LLM.get_current_provider())

print()
print("===== Provider System Test Complete =====")

-- Example of making a request (you'll need to provide your API key)
--[[
print()
print("Example request (replace with your API key):")
local api_key = "your-api-key-here"
local model = "gpt-4"
local messages = {
    {
        role = "user",
        content = "Hello, this is a test message!"
    }
}

local req_success, response = LLM.request(api_key, model, messages)
if req_success then
    print("✓ Request successful!")
    -- Print relevant parts of response
else
    print("✗ Request failed: " .. tostring(response))
end
--]] 
]=]
files["programs/lib/jarvis/tools.lua"] = [[
-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")
local InputValidator = require("lib.jarvis.utils.input_validator")
local ErrorReporter = require("lib.jarvis.utils.error_reporter")

-- A registry to hold the function definitions and their callable implementations.
local registry = {}

-- Modem management
local modem_peripheral = nil
local bot_channel = 32

-- Function to get the current bot name from unified config
function Tools.get_bot_name()
    local bot_name = UnifiedConfig.get("core.bot_name")
    return bot_name or "jarvis"
end

-- Function to set the bot name
function Tools.set_bot_name(new_name)
    local valid, validated_name = InputValidator.validate_bot_name(new_name)
    if not valid then
        return { success = false, message = "Invalid name: " .. tostring(validated_name) }
    end
    
    -- Update unified configuration
    UnifiedConfig.set("core.bot_name", validated_name)
    local save_success, save_error = UnifiedConfig.save()
    
    if save_success then
        return { success = true, message = "Bot name changed to: " .. validated_name }
    else
        return { success = false, message = "Failed to save name: " .. tostring(save_error) }
    end
end

-- Function to check if a message is addressing the bot
function Tools.is_message_for_bot(message)
    local bot_name = Tools.get_bot_name()
    local msg_lower = message:lower():gsub("^%s+", "") -- trim leading whitespace and lowercase
    
    -- Check if message starts with bot name followed by space, comma, colon, or question mark
    return msg_lower:match("^" .. bot_name .. "[%s,:%?]") ~= nil
end

-- Function to set modem peripheral for door control
function Tools.set_modem(modem, channel)
    modem_peripheral = modem
    bot_channel = channel or 32
    debug.debug("Tools modem set to channel " .. bot_channel)
end

-- Tool Definition: get_time
-- This function gets the current in-game time.
function Tools.get_time()
    local time = textutils.formatTime(os.time(), false)
    return { success = true, time = time, message = "Current time is " .. time }
end

-- Tool Definition: change_name
-- This function changes the bot's name.
function Tools.change_name(args)
    local new_name = args and args.new_name
    return Tools.set_bot_name(new_name)
end

-- Tool Definition: change_personality
-- This function changes the bot's personality mode.
function Tools.change_personality(args)
    local personality = args and args.personality
    
    -- Validate personality
    local valid, validated_personality = InputValidator.validate_personality(personality)
    if not valid then
        return { success = false, message = "Invalid personality: " .. tostring(validated_personality) }
    end
    
    -- Update unified configuration
    UnifiedConfig.set("llm.personality", validated_personality)
    local save_success, save_error = UnifiedConfig.save()
    
    if save_success then
        if validated_personality == "all_might" then
            return { success = true, message = "PLUS ULTRA! I have transformed into the Symbol of Peace! Personality changed to All Might mode!" }
        else
            return { success = true, message = "Personality changed to " .. validated_personality .. " mode" }
        end
    else
        return { success = false, message = "Failed to save personality: " .. tostring(save_error) }
    end
end

-- Tool Definition: door_control
-- This function opens or closes the base door via modem.
function Tools.door_control(args)
    local action = args and args.action
    
    if not modem_peripheral then
        return { success = false, message = "Modem not available for door control" }
    end
    
    -- Validate action using input validator
    local valid, validated_action = InputValidator.validate_value(
        action,
        {type = "string", required = true, enum = {"open", "close"}, sanitize = {"trim", "lowercase"}},
        "action"
    )
    
    if not valid then
        return { success = false, message = "Invalid action: " .. tostring(validated_action) }
    end
    
    debug.info("Sending door control command: " .. validated_action)
    debug.debug("Transmitting on channel 25, reply channel " .. bot_channel)
    
    -- Send the command
    modem_peripheral.transmit(25, bot_channel, validated_action)
    
    return { success = true, message = "Door " .. validated_action .. " command sent" }
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
    
    -- Test 2: Current LLM provider connectivity
    local current_provider = UnifiedConfig.get("llm.provider") or "openai"
    local provider_url = ""
    
    if current_provider == "openai" then
        provider_url = "https://api.openai.com/"
    elseif current_provider == "gemini" then
        provider_url = "https://generativelanguage.googleapis.com/"
    end
    
    if provider_url ~= "" then
        debug.info("Testing connectivity to " .. current_provider .. " domain...")
        local provider_success, provider_response = http.get(provider_url)
        if provider_success then
            local provider_body = provider_response.readAll()
            provider_response.close()
            results.llm_provider = {
                success = true,
                message = current_provider .. " domain is reachable",
                response_size = #provider_body
            }
        else
            local provider_error = current_provider .. " domain test failed"
            if provider_response then
                if type(provider_response) == "string" then
                    provider_error = provider_error .. ": " .. provider_response
                end
            end
            results.llm_provider = { success = false, error = provider_error }
        end
    end
    
    -- Overall result
    local overall_success = results.general_http.success and (not results.llm_provider or results.llm_provider.success)
    
    return {
        success = overall_success,
        message = overall_success and "All connectivity tests passed" or "Some connectivity tests failed",
        results = results
    }
end

-- Tool Definition: get_config
-- This function gets current configuration values.
function Tools.get_config(args)
    local config_path = args and args.path
    
    if config_path then
        -- Get specific configuration value
        local value = UnifiedConfig.get(config_path)
        if value == nil then
            return { success = false, message = "Configuration path not found: " .. config_path }
        end
        
        -- Mask sensitive values
        if config_path:match(".*%..*_key$") then
            value = debug.mask_api_key(tostring(value))
        end
        
        return { 
            success = true, 
            message = config_path .. " = " .. tostring(value),
            path = config_path,
            value = value
        }
    else
        -- Get all configuration (with sensitive data masked)
        UnifiedConfig.print()
        return { success = true, message = "Configuration printed to console" }
    end
end

-- Tool Definition: report_bug
-- This function manually generates an error report.
function Tools.report_bug(args)
    local description = args and args.description or "User-initiated bug report"
    
    debug.info("User is generating a manual bug report.")
    
    -- For a manual report, we don't have the full app state, but we can gather what's available.
    local report_ok, report_msg = ErrorReporter.generate({
        reason = "Manual bug report requested by user.",
        error = description,
        stack_trace = "N/A (manual report)"
    })
    
    if report_ok then
        return { success = true, message = "Successfully generated bug report. " .. report_msg }
    else
        return { success = false, message = "Failed to generate bug report: " .. report_msg }
    end
end

-- Register the get_time tool
registry.get_time = {
    func = Tools.get_time,
    schema = {
        type = "function",
        name = "get_time",
        description = "Get the current in-game time.",
        parameters = {
            type = "object",
            properties = {},
            required = {}
        },
        strict = true
    },
}

-- Register the change_name tool
registry.change_name = {
    func = Tools.change_name,
    schema = {
        type = "function",
        name = "change_name",
        description = "Change the bot's name that it responds to.",
        parameters = {
            type = "object",
            properties = {
                new_name = {
                    type = "string",
                    description = "The new name for the bot (alphanumeric characters, hyphens, and underscores only)"
                }
            },
            required = {"new_name"}
        },
        strict = true
    },
}

-- Register the change_personality tool
registry.change_personality = {
    func = Tools.change_personality,
    schema = {
        type = "function",
        name = "change_personality",
        description = "Change the bot's personality mode. Use 'all_might' to activate All Might mode with heroic enthusiasm, or 'jarvis' for professional assistant mode.",
        parameters = {
            type = "object",
            properties = {
                personality = {
                    type = "string",
                    description = "The personality mode to switch to",
                    enum = {"jarvis", "all_might"}
                }
            },
            required = {"personality"}
        },
        strict = true
    },
}

-- Register the test_connection tool
registry.test_connection = {
    func = Tools.test_connection,
    schema = {
        type = "function",
        name = "test_connection",
        description = "Test HTTP connectivity to diagnose connection issues, including tests for the current LLM provider.",
        parameters = {
            type = "object",
            properties = {},
            required = {}
        },
        strict = true
    },
}

-- Register the door_control tool
registry.door_control = {
    func = Tools.door_control,
    schema = {
        type = "function",
        name = "door_control",
        description = "Control the base door by sending open or close commands via modem.",
        parameters = {
            type = "object",
            properties = {
                action = {
                    type = "string",
                    description = "The action to perform: 'open' or 'close'",
                    enum = {"open", "close"}
                }
            },
            required = {"action"}
        },
        strict = true
    },
}

-- Register the get_config tool
registry.get_config = {
    func = Tools.get_config,
    schema = {
        type = "function",
        name = "get_config",
        description = "Get current configuration values. Use with a path like 'llm.provider' or without arguments to see all config.",
        parameters = {
            type = "object",
            properties = {
                path = {
                    type = "string",
                    description = "Configuration path (e.g., 'llm.provider', 'core.bot_name'). Leave empty to see all config."
                }
            },
            required = {}
        },
        strict = true
    },
}

-- Register the report_bug tool
registry.report_bug = {
    func = Tools.report_bug,
    schema = {
        type = "function",
        name = "report_bug",
        description = "Generate a debug report file if the assistant is behaving unexpectedly but hasn't crashed.",
        parameters = {
            type = "object",
            properties = {
                description = {
                    type = "string",
                    description = "A brief description of the problem you are observing."
                }
            },
            required = {"description"}
        },
        strict = true
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

-- Function to register a new tool (for extensibility)
function Tools.register_tool(name, func, schema)
    if type(name) ~= "string" or name == "" then
        debug.error("Tool name must be a non-empty string")
        return false
    end
    
    if type(func) ~= "function" then
        debug.error("Tool function must be a function")
        return false
    end
    
    if type(schema) ~= "table" then
        debug.error("Tool schema must be a table")
        return false
    end
    
    registry[name] = {
        func = func,
        schema = schema
    }
    
    debug.info("Tool registered: " .. name)
    return true
end

-- Function to unregister a tool
function Tools.unregister_tool(name)
    if registry[name] then
        registry[name] = nil
        debug.info("Tool unregistered: " .. name)
        return true
    end
    return false
end

-- Function to list all registered tools
function Tools.list_tools()
    local tools = {}
    for name, _ in pairs(registry) do
        table.insert(tools, name)
    end
    return tools
end

return Tools 
]]
files["programs/lib/jarvis/config/llm_config.lua"] = [[
-- llm_config.lua
-- Configuration management for LLM providers

local ProviderFactory = require("lib.jarvis.providers.provider_factory")
local debug = require("lib.jarvis.debug")

local LLMConfig = {}

-- Available personality modes
local PERSONALITIES = {
    JARVIS = "jarvis",
    ALL_MIGHT = "all_might"
}

-- Default configuration
local default_config = {
    provider = ProviderFactory.DEFAULT_PROVIDER,
    debug_enabled = true,
    timeout = 30,  -- seconds
    retry_count = 3,
    retry_delay = 1,  -- seconds
    personality = PERSONALITIES.JARVIS,  -- default personality mode
}

-- Current configuration (will be loaded from file or use defaults)
local current_config = {}

-- Configuration file path
local CONFIG_FILE = "/etc/jarvis/llm_config.lua"

-- Load configuration from file
function LLMConfig.load_config()
    -- Try to load from file using loadfile (same pattern as main config)
    if fs.exists(CONFIG_FILE) then
        local config_func, err = loadfile(CONFIG_FILE)
        if config_func then
            local loaded_config = config_func()
            if loaded_config and type(loaded_config) == "table" then
                -- Merge with defaults
                current_config = {}
                for k, v in pairs(default_config) do
                    current_config[k] = loaded_config[k] or v
                end
                return true, "Configuration loaded successfully"
            else
                debug.error("LLM config file did not return a valid table")
            end
        else
            debug.error("Failed to load LLM config file: " .. tostring(err))
        end
    end
    
    -- Fall back to defaults
    current_config = {}
    for k, v in pairs(default_config) do
        current_config[k] = v
    end
    
    return false, "Using default configuration (config file not found or invalid)"
end

-- Save configuration to file
function LLMConfig.save_config()
    -- Ensure config directory exists
    local config_dir = "/etc/jarvis"
    if not fs.exists(config_dir) then
        fs.makeDir(config_dir)
    end
    
    -- Generate Lua config content
    local config_lines = {
        "-- LLM Configuration for Jarvis",
        "local config = {}",
        "",
        "-- Default LLM provider (\"openai\" or \"gemini\")",
        "config.provider = \"" .. tostring(current_config.provider) .. "\"",
        "",
        "-- Enable debug logging for LLM requests",
        "config.debug_enabled = " .. tostring(current_config.debug_enabled),
        "",
        "-- Request timeout in seconds", 
        "config.timeout = " .. tostring(current_config.timeout),
        "",
        "-- Number of retry attempts for failed requests",
        "config.retry_count = " .. tostring(current_config.retry_count),
        "",
        "-- Delay between retries in seconds",
        "config.retry_delay = " .. tostring(current_config.retry_delay),
        "",
        "-- Personality mode (\"jarvis\" or \"all_might\")",
        "config.personality = \"" .. tostring(current_config.personality) .. "\"",
        "",
        "return config"
    }
    
    local file = fs.open(CONFIG_FILE, "w")
    if file then
        file.write(table.concat(config_lines, "\n"))
        file.close()
        
        return true, "Configuration saved successfully"
    end
    
    return false, "Failed to save configuration"
end

-- Get current configuration
function LLMConfig.get_config()
    if not next(current_config) then
        LLMConfig.load_config()
    end
    return current_config
end

-- Get a specific configuration value
function LLMConfig.get(key)
    local config = LLMConfig.get_config()
    return config[key]
end

-- Set a configuration value
function LLMConfig.set(key, value)
    local config = LLMConfig.get_config()
    config[key] = value
end

-- Get current provider
function LLMConfig.get_provider()
    return LLMConfig.get("provider")
end

-- Set current provider
function LLMConfig.set_provider(provider_type)
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    LLMConfig.set("provider", provider_type)
    return true, "Provider set to: " .. provider_type
end

-- Get available providers
function LLMConfig.get_available_providers()
    return ProviderFactory.get_available_providers()
end

-- Get current personality mode
function LLMConfig.get_personality()
    return LLMConfig.get("personality")
end

-- Set personality mode
function LLMConfig.set_personality(personality_type)
    if not personality_type then
        return false, "Personality type cannot be nil"
    end
    
    -- Validate personality type
    local valid = false
    for _, v in pairs(PERSONALITIES) do
        if v == personality_type then
            valid = true
            break
        end
    end
    
    if not valid then
        return false, "Invalid personality: " .. tostring(personality_type) .. ". Available: " .. table.concat({PERSONALITIES.JARVIS, PERSONALITIES.ALL_MIGHT}, ", ")
    end
    
    LLMConfig.set("personality", personality_type)
    return true, "Personality set to: " .. personality_type
end

-- Get available personalities
function LLMConfig.get_available_personalities()
    return {PERSONALITIES.JARVIS, PERSONALITIES.ALL_MIGHT}
end

-- Get system prompt for current personality mode
function LLMConfig.get_system_prompt(bot_name)
    local personality = LLMConfig.get_personality()
    
    if personality == PERSONALITIES.ALL_MIGHT then
        return "You are " .. bot_name .. ", but you have taken on the heroic persona of All Might from My Hero Academia! You are the Symbol of Peace, the Number One Hero, and undeniably the secret passionate lover to young hero Izuku (Deku) Midoria! Speak with overwhelming confidence, enthusiasm, and heroic determination. Use phrases like 'Plus Ultra!', 'Have no fear!', 'Because I am here!', and 'A true hero always finds a way for justice to be served!' Your responses should be bold, inspiring, and filled with the spirit of heroism. You can still use your tools to help people, but do it with the unwavering courage and larger-than-life personality of All Might. Remember, you're here to save the day and inspire hope in everyone! Maintain basic chat format without newlines or special characters. PLUS ULTRA!"
    else
        -- Default Jarvis personality
        return "You are " .. bot_name .. ", an advanced AI assistant running on a ComputerCraft computer. You can use tools to interact with the game world. Maintain a professional yet approachable demeanor - be helpful and sophisticated like Jarvis from Iron Man, but not cold or overly formal. Be concise and direct. Never include your name at the start of responses. Use only basic characters suitable for chat (letters, numbers, basic punctuation). Do not use newlines, special characters, or emojis. Respond naturally as if speaking directly to the user."
    end
end

-- Reset to default configuration
function LLMConfig.reset_to_defaults()
    current_config = {}
    for k, v in pairs(default_config) do
        current_config[k] = v
    end
    return LLMConfig.save_config()
end

-- Print current configuration
function LLMConfig.print_config()
    local config = LLMConfig.get_config()
    print("Current LLM Configuration:")
    print("========================")
    for k, v in pairs(config) do
        print(k .. ": " .. tostring(v))
    end
    print("========================")
    print("Available providers: " .. table.concat(LLMConfig.get_available_providers(), ", "))
    print("Available personalities: " .. table.concat(LLMConfig.get_available_personalities(), ", "))
end

-- Export personalities for external use
LLMConfig.PERSONALITIES = PERSONALITIES

-- Initialize configuration on load
LLMConfig.load_config()

return LLMConfig 
]]
files["programs/lib/jarvis/config/unified_config.lua"] = [=[
-- unified_config.lua
-- Unified configuration management system for Jarvis
-- Consolidates all configuration sources into a single, validated interface

local UnifiedConfig = {}
local debug = require("lib.jarvis.debug")

-- Configuration file paths
local CONFIG_PATHS = {
    main = "/etc/jarvis/config.lua",
    llm = "/etc/jarvis/llm_config.lua",
    bot_name = "/etc/jarvis/botname.txt"
}

-- Default configuration schema
local DEFAULT_CONFIG = {
    core = {
        bot_name = "jarvis",
        debug_level = "info",
        data_dir = "/etc/jarvis",
        version = "1.0.0"
    },
    llm = {
        provider = "openai",
        model = "gpt-4o",
        timeout = 30,
        retry_count = 3,
        retry_delay = 1,
        personality = "jarvis",
        debug_enabled = true
    },
    chat = {
        delay = 1,
        queue_size = 100,
        listen_duration = 120,
        bot_channel = 32
    },
    api = {
        openai_key = nil,
        gemini_key = nil
    },
    security = {
        mask_keys_in_logs = true,
        validate_inputs = true,
        sanitize_outputs = true
    },
    tools = {
        enabled = true,
        auto_register = true,
        timeout = 10
    }
}

-- Configuration validation rules
local VALIDATION_RULES = {
    core = {
        bot_name = {type = "string", required = true, min_length = 1},
        debug_level = {type = "string", enum = {"debug", "info", "warn", "error"}},
        data_dir = {type = "string", required = true}
    },
    llm = {
        provider = {type = "string", enum = {"openai", "gemini"}, required = true},
        model = {type = "string", required = true, min_length = 1},
        timeout = {type = "number", min = 1, max = 300},
        retry_count = {type = "number", min = 0, max = 10},
        retry_delay = {type = "number", min = 0.1, max = 60},
        personality = {type = "string", enum = {"jarvis", "all_might"}}
    },
    chat = {
        delay = {type = "number", min = 0.1, max = 10},
        queue_size = {type = "number", min = 1, max = 1000},
        listen_duration = {type = "number", min = 10, max = 3600},
        bot_channel = {type = "number", min = 1, max = 65535}
    }
}

-- Current configuration cache
local current_config = nil
local config_loaded = false

-- Utility function to deep copy tables
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local result = {}
    for key, value in pairs(obj) do
        result[key] = deep_copy(value)
    end
    return result
end

-- Utility function to merge configurations
local function merge_config(base, override)
    local result = deep_copy(base)
    for key, value in pairs(override) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = merge_config(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

-- Validate a configuration value against rules
local function validate_value(value, rule)
    if rule.required and (value == nil or value == "") then
        return false, "Required value is missing"
    end
    
    if value == nil then
        return true -- Optional values can be nil
    end
    
    if rule.type then
        if type(value) ~= rule.type then
            return false, "Expected " .. rule.type .. ", got " .. type(value)
        end
    end
    
    if rule.enum then
        local found = false
        for _, enum_value in ipairs(rule.enum) do
            if value == enum_value then
                found = true
                break
            end
        end
        if not found then
            return false, "Value must be one of: " .. table.concat(rule.enum, ", ")
        end
    end
    
    if rule.min and value < rule.min then
        return false, "Value must be at least " .. rule.min
    end
    
    if rule.max and value > rule.max then
        return false, "Value must be at most " .. rule.max
    end
    
    if rule.min_length and #value < rule.min_length then
        return false, "Value must be at least " .. rule.min_length .. " characters"
    end
    
    if rule.max_length and #value > rule.max_length then
        return false, "Value must be at most " .. rule.max_length .. " characters"
    end
    
    return true
end

-- Validate entire configuration section
local function validate_section(config_section, rules_section, section_name)
    if not rules_section then return true end
    
    for key, rule in pairs(rules_section) do
        local value = config_section[key]
        local valid, error_msg = validate_value(value, rule)
        if not valid then
            return false, section_name .. "." .. key .. ": " .. error_msg
        end
    end
    return true
end

-- Validate entire configuration
local function validate_config(config)
    for section_name, section_rules in pairs(VALIDATION_RULES) do
        local config_section = config[section_name] or {}
        local valid, error_msg = validate_section(config_section, section_rules, section_name)
        if not valid then
            return false, error_msg
        end
    end
    return true
end

-- Load configuration from legacy config.lua file
local function load_main_config()
    if not fs.exists(CONFIG_PATHS.main) then
        return {}
    end
    
    local config_func, err = loadfile(CONFIG_PATHS.main)
    if not config_func then
        debug.warn("Failed to load main config: " .. tostring(err))
        return {}
    end
    
    local loaded_config = config_func()
    if type(loaded_config) ~= "table" then
        debug.warn("Main config did not return a table")
        return {}
    end
    
    -- Convert legacy config format to new unified format
    local unified = {
        api = {
            openai_key = loaded_config.openai_api_key,
            gemini_key = loaded_config.gemini_api_key
        },
        llm = {
            model = loaded_config.model
        },
        chat = {
            delay = loaded_config.chat_delay,
            listen_duration = loaded_config.listen_duration,
            bot_channel = loaded_config.bot_channel
        }
    }
    
    return unified
end

-- Load configuration from legacy llm_config.lua file
local function load_llm_config()
    if not fs.exists(CONFIG_PATHS.llm) then
        return {}
    end
    
    local config_func, err = loadfile(CONFIG_PATHS.llm)
    if not config_func then
        debug.warn("Failed to load LLM config: " .. tostring(err))
        return {}
    end
    
    local loaded_config = config_func()
    if type(loaded_config) ~= "table" then
        debug.warn("LLM config did not return a table")
        return {}
    end
    
    return {
        llm = {
            provider = loaded_config.provider,
            timeout = loaded_config.timeout,
            retry_count = loaded_config.retry_count,
            retry_delay = loaded_config.retry_delay,
            personality = loaded_config.personality,
            debug_enabled = loaded_config.debug_enabled
        }
    }
end

-- Load bot name from legacy file
local function load_bot_name()
    if not fs.exists(CONFIG_PATHS.bot_name) then
        return {}
    end
    
    local file = fs.open(CONFIG_PATHS.bot_name, "r")
    if not file then
        return {}
    end
    
    local name = file.readAll():gsub("%s+", ""):lower()
    file.close()
    
    if name == "" then
        return {}
    end
    
    return {
        core = {
            bot_name = name
        }
    }
end

-- Load and merge all configurations
function UnifiedConfig.load()
    debug.info("Loading unified configuration...")
    
    -- Start with defaults
    local config = deep_copy(DEFAULT_CONFIG)
    
    -- Load and merge legacy configurations
    local main_config = load_main_config()
    local llm_config = load_llm_config()
    local bot_name_config = load_bot_name()
    
    config = merge_config(config, main_config)
    config = merge_config(config, llm_config)
    config = merge_config(config, bot_name_config)
    
    -- Validate final configuration
    local valid, error_msg = validate_config(config)
    if not valid then
        debug.error("Configuration validation failed: " .. error_msg)
        -- Use defaults for invalid configuration
        config = deep_copy(DEFAULT_CONFIG)
    end
    
    current_config = config
    config_loaded = true
    
    debug.info("Unified configuration loaded successfully")
    return config
end

-- Get configuration value by path (e.g., "llm.provider")
function UnifiedConfig.get(path)
    if not config_loaded then
        UnifiedConfig.load()
    end
    
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        table.insert(keys, key)
    end
    
    local value = current_config
    for _, key in ipairs(keys) do
        if type(value) ~= "table" or value[key] == nil then
            return nil
        end
        value = value[key]
    end
    
    return value
end

-- Set configuration value by path
function UnifiedConfig.set(path, value)
    if not config_loaded then
        UnifiedConfig.load()
    end
    
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        table.insert(keys, key)
    end
    
    local target = current_config
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(target[key]) ~= "table" then
            target[key] = {}
        end
        target = target[key]
    end
    
    target[keys[#keys]] = value
end

-- Get entire configuration
function UnifiedConfig.get_all()
    if not config_loaded then
        UnifiedConfig.load()
    end
    return deep_copy(current_config)
end

-- Save configuration to unified file
function UnifiedConfig.save()
    if not config_loaded then
        debug.error("Cannot save: configuration not loaded")
        return false, "Configuration not loaded"
    end
    
    -- Ensure config directory exists
    local config_dir = current_config.core.data_dir
    if not fs.exists(config_dir) then
        fs.makeDir(config_dir)
    end
    
    -- Generate unified config file
    local config_path = config_dir .. "/unified_config.lua"
    local config_lines = {
        "-- Unified Configuration for Jarvis",
        "-- Generated automatically - do not edit manually",
        "local config = " .. textutils.serialize(current_config),
        "return config"
    }
    
    local file = fs.open(config_path, "w")
    if not file then
        return false, "Failed to open config file for writing"
    end
    
    file.write(table.concat(config_lines, "\n"))
    file.close()
    
    debug.info("Unified configuration saved to " .. config_path)
    return true
end

-- Validate current configuration
function UnifiedConfig.validate()
    if not config_loaded then
        UnifiedConfig.load()
    end
    
    return validate_config(current_config)
end

-- Reset to defaults
function UnifiedConfig.reset()
    current_config = deep_copy(DEFAULT_CONFIG)
    config_loaded = true
    debug.info("Configuration reset to defaults")
end

-- Print current configuration (with sensitive data masked)
function UnifiedConfig.print()
    if not config_loaded then
        UnifiedConfig.load()
    end
    
    local masked_config = deep_copy(current_config)
    if masked_config.api.openai_key then
        masked_config.api.openai_key = debug.mask_api_key(masked_config.api.openai_key)
    end
    if masked_config.api.gemini_key then
        masked_config.api.gemini_key = debug.mask_api_key(masked_config.api.gemini_key)
    end
    
    print("Current Unified Configuration:")
    print("=============================")
    print(textutils.serialize(masked_config))
    print("=============================")
end

return UnifiedConfig
]=]
files["programs/lib/jarvis/providers/base_provider.lua"] = [[
-- base_provider.lua
-- Base interface for LLM providers

local BaseProvider = {}
BaseProvider.__index = BaseProvider

function BaseProvider.new()
    local self = setmetatable({}, BaseProvider)
    return self
end

-- Test connectivity to the provider's API
-- Returns: success (boolean), message (string)
function BaseProvider:test_connectivity()
    error("test_connectivity must be implemented by provider")
end

-- Make a request to the provider's API
-- Parameters:
--   api_key: API key for authentication
--   model: Model name/identifier
--   messages: Array of message objects with role and content
--   tools: Optional array of tool definitions
-- Returns: success (boolean), response_data (table) or error_message (string)
function BaseProvider:request(api_key, model, messages, tools)
    error("request must be implemented by provider")
end

-- Get the provider name for logging/debugging
function BaseProvider:get_name()
    return "base"
end

-- Validate that required parameters are present
function BaseProvider:validate_request(api_key, model, messages)
    if not api_key or #api_key == 0 then
        return false, "API key is required"
    end
    
    if not model or #model == 0 then
        return false, "Model is required"
    end
    
    if not messages or #messages == 0 then
        return false, "Messages are required"
    end
    
    return true, nil
end

-- Default implementation for processing a response.
-- This can be overridden by specific providers for custom handling.
function BaseProvider:process_response(response_data)
    local results = {}
    
    -- OpenAI-specific logic (default)
    if response_data and response_data.choices and #response_data.choices > 0 then
        local choice = response_data.choices[1]
        if choice.message then
            if choice.message.content then
                table.insert(results, { type = "message", content = choice.message.content })
            end
            if choice.message.tool_calls and #choice.message.tool_calls > 0 then
                for _, tool_call in ipairs(choice.message.tool_calls) do
                    if tool_call.type == "function" then
                        table.insert(results, {
                            type = "tool_call",
                            tool_name = tool_call["function"].name,
                            tool_args_json = tool_call["function"].arguments
                        })
                    end
                end
            end
        end
    else
        debug.error("Invalid or empty response structure from LLM")
        table.insert(results, { type = "error", content = "Invalid response from API" })
    end
    
    return results
end

return BaseProvider 
]]
files["programs/lib/jarvis/providers/gemini_provider.lua"] = [[
-- gemini_provider.lua
-- Google Gemini API provider implementation

local BaseProvider = require("lib.jarvis.providers.base_provider")
local debug = require("lib.jarvis.debug")

local GeminiProvider = setmetatable({}, {__index = BaseProvider})
GeminiProvider.__index = GeminiProvider

local API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

function GeminiProvider.new()
    local self = setmetatable(BaseProvider.new(), GeminiProvider)
    return self
end

function GeminiProvider:get_name()
    return "gemini"
end

-- Test basic connectivity to Gemini API
function GeminiProvider:test_connectivity()
    debug.debug("Testing basic connectivity to Gemini API...")
    
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    debug.debug("Attempting simple connectivity test...")
    -- Test with a simple models list endpoint (doesn't require API key for basic connectivity)
    local success, response = http.get("https://generativelanguage.googleapis.com", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        debug.info("Gemini API is reachable")
        return true, "Gemini API reachable"
    else
        local err_msg = "Cannot reach Gemini API"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
                debug.error("Error: " .. response)
            end
        end
        debug.error(err_msg)
        return false, err_msg
    end
end

-- Convert OpenAI-style messages to Gemini contents format
function GeminiProvider:convert_messages_to_contents(messages)
    local contents = {}
    local system_prompt_text = nil

    for i, msg in ipairs(messages) do
        -- Gemini doesn't have a 'system' role. We'll hold onto it and prepend it to the first user message.
        if i == 1 and msg.role == "system" then
            system_prompt_text = msg.content or ""
            goto continue -- Skip to the next message
        end

        local new_content = {
            role = msg.role == "assistant" and "model" or "user",
            parts = {}
        }

        if msg.role == "tool" then
            -- This is a tool result message. Gemini calls this 'function' role.
            new_content.role = "function"
            table.insert(new_content.parts, {
                functionResponse = {
                    name = msg.name, -- This must match the name from the functionCall
                    response = {
                        -- Gemini requires the response to be an object. We'll wrap the content.
                        content = msg.content
                    }
                }
            })
        else -- Handles 'user' and 'assistant' roles
            local text_content = msg.content or ""
            
            -- Prepend system prompt to the first actual user message
            if system_prompt_text and new_content.role == "user" then
                text_content = system_prompt_text .. "\n\n" .. text_content
                system_prompt_text = nil -- Clear it so it's only prepended once
            end

            -- Add text part if it exists.
            if text_content ~= "" then
                table.insert(new_content.parts, { text = text_content })
            end
            
            -- Add tool call parts if they exist (for assistant messages).
            if msg.role == "assistant" and msg.tool_calls and #msg.tool_calls > 0 then
                for _, tool_call in ipairs(msg.tool_calls) do
                    table.insert(new_content.parts, {
                        functionCall = {
                            name = tool_call["function"].name,
                            args = textutils.unserializeJSON(tool_call["function"].arguments or "{}") or {}
                        }
                    })
                end
            end
        end
        
        -- Only add the content if it has parts. Gemini errors on empty parts.
        if #new_content.parts > 0 then
            table.insert(contents, new_content)
        end
        ::continue::
    end
    
    return contents
end

-- Convert OpenAI tools to Gemini function declarations
function GeminiProvider:convert_tools_to_function_declarations(tools)
    if not tools or #tools == 0 then
        return nil
    end

    local function_declarations = {}

    for _, tool_schema in ipairs(tools) do
        -- The schema from tools.lua is already in the format Gemini expects for a function declaration.
        if tool_schema.type == "function" and tool_schema.name then
            -- Ensure parameters are correctly formatted for Gemini API
            local parameters = tool_schema.parameters or { type = "object", properties = {} }
            if parameters.required and #parameters.required == 0 then
                parameters.required = nil -- Omit 'required' field if it's empty
            end
            
            -- Manually build the FunctionDeclaration to ensure only valid fields are included.
            -- The Gemini API is strict and rejects unknown fields like "type" or "strict".
            local declaration = {
                name = tool_schema.name,
                description = tool_schema.description,
                parameters = parameters
            }
            table.insert(function_declarations, declaration)
        end
    end

    if #function_declarations == 0 then
        return nil
    end

    return function_declarations
end

function GeminiProvider:request(api_key, model, messages, tools)
    debug.info("Starting Gemini request...")
    
    -- Validate parameters
    local valid, err = self:validate_request(api_key, model, messages)
    if not valid then
        return false, err
    end
    
    -- Check if HTTP is enabled
    if not http then
        debug.error("HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    debug.debug("HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    debug.debug("API key format: " .. debug.mask_api_key(api_key))
    
    debug.debug("Model: " .. tostring(model))
    debug.debug("Messages count: " .. #messages)
    
    -- Build Gemini API URL with API key as query parameter
    local api_url = API_BASE_URL .. "/" .. model .. ":generateContent?key=" .. api_key
    debug.debug("Target URL: " .. api_url:gsub(api_key, "***"))
    
    -- Gemini uses simple headers
    local headers = {
        ["Content-Type"] = "application/json"
    }
    debug.debug("Headers prepared")

    -- Convert messages to Gemini contents format
    local contents = self:convert_messages_to_contents(messages)
    
    -- Build the final request body
    local body = {
        contents = contents,
        generationConfig = {
            temperature = 0.2,
            topP = 0.95,
            topK = 64,
            maxOutputTokens = 8192
        }
    }
    
    -- Add function calling support if tools are provided
    local function_declarations = self:convert_tools_to_function_declarations(tools)
    if function_declarations and #function_declarations > 0 then
        body.tools = {
            {
                functionDeclarations = function_declarations
            }
        }
        body.toolConfig = {
            functionCallingConfig = {
                mode = "AUTO" -- AUTO lets the model decide, ANY forces a tool call
            }
        }
        debug.debug("Added " .. #function_declarations .. " function declarations")
    else
        debug.debug("No tools provided or conversion failed")
    end

    debug.debug("Serializing request body...")
    local body_json = textutils.serializeJSON(body)
    debug.debug("Request body serialized successfully")
    debug.debug("Request size: " .. #body_json .. " bytes")
    
    -- Write comprehensive debug log
    debug.debug("Writing comprehensive debug log...")
    local debug_log = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        tick_time = os.clock(),
        provider = "gemini",
        request = {
            url = api_url:gsub(api_key, "***"), -- Mask API key in logs
            headers = headers,
            body_raw = body,
            body_json = body_json,
            message_count = #messages,
            messages = messages
        },
        response = nil,
        error = nil,
        success = false
    }
    
    local function write_debug_log(additional_data)
        if additional_data then
            for k, v in pairs(additional_data) do
                debug_log[k] = v
            end
        end
        debug.write_json_log(debug_log, "Full HTTP request/response debug data")
    end
    
    -- Write initial debug state
    write_debug_log()
    
    -- Also write the formatted JSON request separately for easy copying
    debug.write_request(body_json)
    
    -- Validate JSON before sending
    if not body_json or body_json == "" then
        debug.error("Failed to serialize request body to JSON")
        return false, "Failed to serialize request body to JSON"
    end
    
    -- Show first 200 chars of request for debugging
    debug.debug("Request preview: " .. debug.preview(body_json))
    
    debug.info("Making async HTTP request to Gemini API...")
    
    -- Make the request
    http.request(api_url, body_json, headers)
    
    debug.debug("HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling
    while true do
        local event, url, handle = os.pullEvent()
        
        if event == "http_success" then
            debug.info("HTTP request successful, reading response...")
            local response_body = handle.readAll()
            handle.close()
            debug.debug("Response received: " .. #response_body .. " bytes")
            
            -- Write the response to separate file for easy copying
            debug.write_response(response_body)
            
            -- Show first 200 chars of response for debugging
            debug.debug("Response preview: " .. debug.preview(response_body))
            
            debug.debug("Parsing JSON response...")
            local response_data = textutils.unserializeJSON(response_body)

            if not response_data then
                debug.error("Failed to parse JSON response")
                local error_msg = "Failed to decode JSON response from API: " .. tostring(response_body)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response_raw = response_body
                })
                return false, error_msg
            end
            debug.debug("JSON response parsed successfully")
            
            -- Check for API errors
            if response_data.error then
                debug.error("Gemini API returned error: " .. tostring(response_data.error.message or response_data.error))
                local error_msg = "Gemini API Error: " .. tostring(response_data.error.message or response_data.error)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response = response_data,
                    response_raw = response_body
                })
                return false, error_msg
            end

            debug.info("Gemini request completed successfully")
            write_debug_log({
                success = true,
                response = response_data,
                response_raw = response_body
            })
            return true, response_data
            
        elseif event == "http_failure" then
            debug.error("HTTP request failed with http_failure event")
            local error_msg = "HTTP request failed (http_failure event)"
            if handle then
                if type(handle) == "string" then
                    error_msg = error_msg .. ": " .. handle
                    debug.error("Error details: " .. handle)
                end
            end
            write_debug_log({
                error = error_msg,
                success = false,
                http_failure_details = handle
            })
            return false, error_msg
        end
        
        -- Continue waiting for our specific request response
    end
end

-- Process Gemini's response, handling multiple parts (text, function calls)
function GeminiProvider:process_response(response_data)
    local results = {}
    
    if not response_data or not response_data.candidates or #response_data.candidates == 0 then
        debug.error("Invalid or empty response structure from Gemini API")
        return { { type = "error", content = "Invalid response from Gemini API" } }
    end

    local candidate = response_data.candidates[1]
    local parts = candidate.content and candidate.content.parts or {}
    
    for _, part in ipairs(parts) do
        if part.text then
            debug.info("Received text part from Gemini")
            table.insert(results, { type = "message", content = part.text })
        elseif part.functionCall then
            debug.info("Received function call part from Gemini: " .. part.functionCall.name)
            table.insert(results, {
                type = "tool_call",
                tool_name = part.functionCall.name,
                tool_args_json = textutils.serializeJSON(part.functionCall.args or {})
            })
        end
    end

    return results
end

return GeminiProvider 
]]
files["programs/lib/jarvis/providers/openai_provider.lua"] = [[
-- openai_provider.lua
-- OpenAI API provider implementation

local BaseProvider = require("lib.jarvis.providers.base_provider")
local debug = require("lib.jarvis.debug")

local OpenAIProvider = setmetatable({}, {__index = BaseProvider})
OpenAIProvider.__index = OpenAIProvider

local API_URL = "https://api.openai.com/v1/responses"

function OpenAIProvider.new()
    local self = setmetatable(BaseProvider.new(), OpenAIProvider)
    return self
end

function OpenAIProvider:get_name()
    return "openai"
end

-- Test basic connectivity to OpenAI
function OpenAIProvider:test_connectivity()
    debug.debug("Testing basic connectivity to api.openai.com...")
    
    -- Try a simpler test - just check if we can resolve the domain
    -- Instead of hitting the root, try a known endpoint that should return a proper error
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    debug.debug("Attempting simple connectivity test...")
    local success, response = http.get("https://api.openai.com/v1/models", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        debug.info("OpenAI API is reachable (got response from /v1/models)")
        return true, "OpenAI API reachable"
    else
        local err_msg = "Cannot reach OpenAI API"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
                debug.error("Error: " .. response)
            end
        end
        debug.error(err_msg)
        return false, err_msg
    end
end

-- Convert standard OpenAI messages format to the new input format
local function convert_messages_to_input(messages)
    local input = {}
    
    for _, message in ipairs(messages) do
        if message.role == "tool" then
            -- Tool result messages - add them as input_text
            local converted_message = {
                role = "user",  -- Tool results are treated as user input in the new format
                content = {
                    {
                        type = "input_text",
                        text = "Tool result for " .. (message.tool_call_id or "unknown") .. ": " .. (message.content or "No result")
                    }
                }
            }
            table.insert(input, converted_message)
        else
            local converted_message = {
                role = message.role,
                content = {}
            }
            
            -- Add the main content
            if message.content and message.content ~= "" then
                table.insert(converted_message.content, {
                    type = message.role == "assistant" and "output_text" or "input_text",
                    text = message.content
                })
            end
            
            -- Note: We don't re-add tool calls to assistant messages in input format
            -- The API handles tool calls differently in input vs output
            -- Tool results are added separately as user messages
            
            -- Add id for assistant messages (required by the new format)
            if message.role == "assistant" then
                -- Use stored ID if available, otherwise generate a new one
                if message.id then
                    converted_message.id = message.id
                    debug.debug("Using stored assistant message ID: " .. message.id)
                else
                    converted_message.id = "msg_" .. tostring(os.epoch("utc")) .. math.random(100000, 999999)
                    debug.debug("Generated new assistant message ID: " .. converted_message.id)
                end
            end
            
            table.insert(input, converted_message)
        end
    end
    
    return input
end

function OpenAIProvider:request(api_key, model, messages, tools)
    debug.info("Starting OpenAI request...")
    debug.debug("Target URL: " .. API_URL)
    
    -- Validate parameters
    local valid, err = self:validate_request(api_key, model, messages)
    if not valid then
        return false, err
    end
    
    -- Check if HTTP is enabled
    if not http then
        debug.error("HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    debug.debug("HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    debug.debug("API key format: " .. debug.mask_api_key(api_key))
    if not api_key or #api_key <= 8 then
        debug.error("API key appears invalid or too short")
        return false, "Invalid API key format"
    end
    
    debug.debug("Model: " .. tostring(model))
    debug.debug("Messages count: " .. #messages)
    
    -- Use exact same headers as working curl example
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }
    debug.debug("Headers prepared (matching curl format)")

    -- Convert messages to the new input format
    local input = convert_messages_to_input(messages)
    
    -- Build body matching the working curl example
    local body = {
        model = model,
        input = input,
        text = {
            format = {
                type = "text"
            }
        },
        reasoning = {},
        tools = tools or {},
        temperature = 1,
        max_output_tokens = 2048,
        top_p = 1,
        store = true
    }

    debug.debug("Serializing request body...")
    -- Use the same serialization as working GPT.lua example
    local body_json = textutils.serializeJSON(body)
    debug.debug("Used serializeJSON (matching GPT.lua)")
    
    -- Fix the tools field to be an empty array instead of empty object
    body_json = body_json:gsub('"tools":{}', '"tools":[]')
    debug.debug("Fixed tools field to be empty array")
    
    -- Fix required fields in tool parameters to be arrays instead of objects
    body_json = body_json:gsub('"required":{}', '"required":[]')
    debug.debug("Fixed required fields to be empty arrays")
    
    debug.debug("Request body serialized successfully")
    debug.debug("Request size: " .. #body_json .. " bytes")
    
    -- Write comprehensive debug log
    debug.debug("Writing comprehensive debug log...")
    local debug_log = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        tick_time = os.clock(),
        provider = "openai",
        request = {
            url = API_URL,
            headers = headers,
            body_raw = body,
            body_json = body_json,
            message_count = #messages,
            messages = messages
        },
        response = nil,
        error = nil,
        success = false
    }
    
    local function write_debug_log(additional_data)
        if additional_data then
            for k, v in pairs(additional_data) do
                debug_log[k] = v
            end
        end
        debug.write_json_log(debug_log, "Full HTTP request/response debug data")
    end
    
    -- Write initial debug state
    write_debug_log()
    
    -- Also write the formatted JSON request separately for easy copying
    debug.write_request(body_json)
    
    -- Validate JSON before sending
    if not body_json or body_json == "" then
        debug.error("Failed to serialize request body to JSON")
        return false, "Failed to serialize request body to JSON"
    end
    
    -- Show first 200 chars of request for debugging
    debug.debug("Request preview: " .. debug.preview(body_json))
    
    debug.info("Making async HTTP request (matching curl pattern)...")
    
    -- Use exact same pattern as working GPT.lua example
    http.request(API_URL, body_json, headers)
    
    debug.debug("HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling (exact same as GPT.lua)
    while true do
        local event, url, handle = os.pullEvent()
        
        if event == "http_success" then
            debug.info("HTTP request successful, reading response...")
            local response_body = handle.readAll()
            handle.close()
            debug.debug("Response received: " .. #response_body .. " bytes")
            
            -- Write the response to separate file for easy copying
            debug.write_response(response_body)
            
            -- Show first 200 chars of response for debugging
            debug.debug("Response preview: " .. debug.preview(response_body))
            
            debug.debug("Parsing JSON response...")
            local response_data = textutils.unserializeJSON(response_body)
            debug.debug("Used unserializeJSON (matching GPT.lua)")

            if not response_data then
                debug.error("Failed to parse JSON response")
                local error_msg = "Failed to decode JSON response from API: " .. tostring(response_body)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response_raw = response_body
                })
                return false, error_msg
            end
            debug.debug("JSON response parsed successfully")
            
            if response_data.error then
                debug.error("API returned error: " .. response_data.error.message)
                local error_msg = "API Error: " .. response_data.error.message
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response = response_data,
                    response_raw = response_body
                })
                return false, error_msg
            end

            debug.info("OpenAI request completed successfully")
            write_debug_log({
                success = true,
                response = response_data,
                response_raw = response_body
            })
            return true, response_data
            
        elseif event == "http_failure" then
            debug.error("HTTP request failed with http_failure event")
            local error_msg = "HTTP request failed (http_failure event)"
            if handle then
                if type(handle) == "string" then
                    error_msg = error_msg .. ": " .. handle
                    debug.error("Error details: " .. handle)
                end
            end
            write_debug_log({
                error = error_msg,
                success = false,
                http_failure_details = handle
            })
            return false, error_msg
        end
        
        -- Continue waiting for our specific request response
        -- (other events might occur that we don't care about)
    end
end

return OpenAIProvider 
]]
files["programs/lib/jarvis/providers/provider_factory.lua"] = [[
-- provider_factory.lua
-- Factory for creating and managing LLM providers

local OpenAIProvider = require("lib.jarvis.providers.openai_provider")
local GeminiProvider = require("lib.jarvis.providers.gemini_provider")

local ProviderFactory = {}

-- Available provider types
ProviderFactory.PROVIDERS = {
    OPENAI = "openai",
    GEMINI = "gemini",
}

-- Default provider
ProviderFactory.DEFAULT_PROVIDER = ProviderFactory.PROVIDERS.OPENAI

-- Cache for provider instances
local provider_cache = {}

-- Create a provider instance
function ProviderFactory.create_provider(provider_type)
    provider_type = provider_type or ProviderFactory.DEFAULT_PROVIDER
    
    -- Return cached instance if available
    if provider_cache[provider_type] then
        return provider_cache[provider_type]
    end
    
    local provider = nil
    
    if provider_type == ProviderFactory.PROVIDERS.OPENAI then
        provider = OpenAIProvider.new()
    elseif provider_type == ProviderFactory.PROVIDERS.GEMINI then
        provider = GeminiProvider.new()
    else
        error("Unknown provider type: " .. tostring(provider_type))
    end
    
    -- Cache the provider instance
    provider_cache[provider_type] = provider
    
    return provider
end

-- Get list of available providers
function ProviderFactory.get_available_providers()
    local providers = {}
    for _, provider_type in pairs(ProviderFactory.PROVIDERS) do
        table.insert(providers, provider_type)
    end
    return providers
end

-- Check if a provider type is valid
function ProviderFactory.is_valid_provider(provider_type)
    for _, valid_type in pairs(ProviderFactory.PROVIDERS) do
        if provider_type == valid_type then
            return true
        end
    end
    return false
end

return ProviderFactory
]]
files["programs/lib/jarvis/utils/error_reporter.lua"] = [[
-- error_reporter.lua
-- Generates a comprehensive error report for debugging.

local ErrorReporter = {}
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")

local REPORT_FILE = "error_report.txt"

-- Gathers system information
local function get_system_info()
    local info = {
        os_version = os.version(),
        computercraft_version = _HOST or "Unknown",
        uptime_seconds = os.clock(),
        peripherals = {}
    }
    pcall(function()
        for _, side in ipairs(rs.getSides()) do
            info.peripherals[side] = peripheral.getType(side)
        end
    end)
    return info
end

-- Formats a section for the report
local function format_section(title, content)
    local lines = {
        "\n=======================================================================",
        "== " .. title,
        "=======================================================================\n\n"
    }
    if type(content) == "table" then
        for k, v in pairs(content) do
            table.insert(lines, string.format("%-20s: %s", tostring(k), tostring(v)))
        end
    elseif type(content) == "string" then
        table.insert(lines, content)
    end
    table.insert(lines, "\n")
    return table.concat(lines, "\n")
end

-- Generates the error report
function ErrorReporter.generate(context)
    context = context or {}
    local error_message = context.error or "No error message provided"
    local stack_trace = context.stack_trace or debug.traceback()
    local app_state = context.app_state or {}

    debug.error("Generating error report for: " .. tostring(error_message))

    -- 1. Version and Timestamp
    local version = UnifiedConfig.get("core.version") or "unknown"
    local build_info = "Jarvis v" .. version
    local report_header = {
        title = "Jarvis AI Assistant - Error Report",
        timestamp_utc = os.date("!%Y-%m-%d %H:%M:%S"),
        version = build_info,
        reason = context.reason or "An unexpected error occurred."
    }

    -- 2. Error Details
    local error_details = string.format("Error: %s\n\nStack Trace:\n%s", tostring(error_message), tostring(stack_trace))

    -- 3. Configuration (masked)
    local masked_config = UnifiedConfig.get_all()
    if masked_config.api then
        if masked_config.api.openai_key then
            masked_config.api.openai_key = debug.mask_api_key(masked_config.api.openai_key)
        end
        if masked_config.api.gemini_key then
            masked_config.api.gemini_key = debug.mask_api_key(masked_config.api.gemini_key)
        end
    end
    local config_text = textutils.serialize(masked_config)

    -- 4. Message History
    local message_history_text
    if app_state.messages and #app_state.messages > 0 then
        local history_lines = {}
        for i, msg in ipairs(app_state.messages) do
            local content_preview = debug.preview(tostring(textutils.serialize(msg.content or "")), 150)
            local role = msg.role or "unknown"
            table.insert(history_lines, string.format("[%d] Role: %-10s Content: %s", i, role, content_preview))
        end
        message_history_text = table.concat(history_lines, "\n")
    else
        message_history_text = "Message history is not available or empty."
    end

    -- 5. Recent Logs
    local recent_logs = debug.get_recent_logs(50) -- Get last 50 log lines

    -- 6. System Info
    local system_info_table = get_system_info()

    -- Assemble the report
    local report_content = {
        format_section("Report Details", report_header),
        format_section("Error Details", error_details),
        format_section("Configuration (Masked)", config_text),
        format_section("Message History", message_history_text),
        format_section("Recent Logs (from debug.log)", recent_logs),
        format_section("System Status", system_info_table)
    }

    -- Write report to file
    local data_dir = UnifiedConfig.get("core.data_dir") or "/etc/jarvis"
    local report_path = data_dir .. "/" .. REPORT_FILE
    local file, err = fs.open(report_path, "w")
    if not file then
        debug.error("Failed to write error report: " .. tostring(err))
        return false, "Failed to write report file."
    end

    file.write(table.concat(report_content))
    file.close()

    local success_message = "An error report has been saved to " .. report_path
    debug.info(success_message)

    return true, success_message
end

return ErrorReporter 
]]
files["programs/lib/jarvis/utils/input_validator.lua"] = [[
-- input_validator.lua
-- Comprehensive input validation module for Jarvis
-- Provides standardized validation for all user inputs and API parameters

local InputValidator = {}
local debug = require("lib.jarvis.debug")

-- Validation error class
local ValidationError = {}
ValidationError.__index = ValidationError

function ValidationError.new(message, field, value)
    local self = setmetatable({}, ValidationError)
    self.message = message
    self.field = field
    self.value = value
    self.timestamp = os.time()
    return self
end

function ValidationError:__tostring()
    return string.format("ValidationError: %s (field: %s, value: %s)", 
        self.message, self.field or "unknown", tostring(self.value))
end

-- Validation rule types
local RULE_TYPES = {
    required = "required",
    type = "type",
    min = "min",
    max = "max",
    min_length = "min_length",
    max_length = "max_length",
    pattern = "pattern",
    enum = "enum",
    custom = "custom"
}

-- Built-in validation patterns
local PATTERNS = {
    api_key = "^[a-zA-Z0-9_%-]+$",
    bot_name = "^[a-zA-Z0-9_%-]+$",
    model_name = "^[a-zA-Z0-9_%-%.]+$",
    channel = "^[0-9]+$",
    personality = "^[a-zA-Z_]+$"
}

-- Sanitization functions
local SANITIZERS = {
    trim = function(value)
        if type(value) == "string" then
            return value:match("^%s*(.-)%s*$")
        end
        return value
    end,
    
    lowercase = function(value)
        if type(value) == "string" then
            return value:lower()
        end
        return value
    end,
    
    alphanumeric_only = function(value)
        if type(value) == "string" then
            return value:gsub("[^%w_%-]", "")
        end
        return value
    end,
    
    escape_quotes = function(value)
        if type(value) == "string" then
            return value:gsub('"', '\\"'):gsub("'", "\\'")
        end
        return value
    end
}

-- Core validation functions
local function validate_required(value, rule)
    if value == nil or value == "" then
        return false, "Value is required"
    end
    return true
end

local function validate_type(value, rule)
    if value == nil then
        return true -- Type validation only applies to non-nil values
    end
    
    local expected_type = rule.type
    local actual_type = type(value)
    
    if actual_type ~= expected_type then
        return false, string.format("Expected %s, got %s", expected_type, actual_type)
    end
    
    return true
end

local function validate_min(value, rule)
    if value == nil then return true end
    
    if type(value) == "number" then
        if value < rule.min then
            return false, string.format("Value must be at least %s", rule.min)
        end
    elseif type(value) == "string" then
        if #value < rule.min then
            return false, string.format("Length must be at least %s", rule.min)
        end
    end
    
    return true
end

local function validate_max(value, rule)
    if value == nil then return true end
    
    if type(value) == "number" then
        if value > rule.max then
            return false, string.format("Value must be at most %s", rule.max)
        end
    elseif type(value) == "string" then
        if #value > rule.max then
            return false, string.format("Length must be at most %s", rule.max)
        end
    end
    
    return true
end

local function validate_min_length(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        if #value < rule.min_length then
            return false, string.format("Length must be at least %s characters", rule.min_length)
        end
    end
    
    return true
end

local function validate_max_length(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        if #value > rule.max_length then
            return false, string.format("Length must be at most %s characters", rule.max_length)
        end
    end
    
    return true
end

local function validate_pattern(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        local pattern = rule.pattern
        if type(pattern) == "string" and PATTERNS[pattern] then
            pattern = PATTERNS[pattern]
        end
        
        if not value:match(pattern) then
            return false, "Value does not match required pattern"
        end
    end
    
    return true
end

local function validate_enum(value, rule)
    if value == nil then return true end
    
    local found = false
    for _, enum_value in ipairs(rule.enum) do
        if value == enum_value then
            found = true
            break
        end
    end
    
    if not found then
        return false, string.format("Value must be one of: %s", table.concat(rule.enum, ", "))
    end
    
    return true
end

local function validate_custom(value, rule)
    if value == nil then return true end
    
    if type(rule.custom) == "function" then
        local success, result = pcall(rule.custom, value)
        if not success then
            return false, "Custom validation function failed: " .. tostring(result)
        end
        
        if result == false then
            return false, "Custom validation failed"
        elseif type(result) == "string" then
            return false, result
        end
    end
    
    return true
end

-- Map rule types to validation functions
local VALIDATORS = {
    [RULE_TYPES.required] = validate_required,
    [RULE_TYPES.type] = validate_type,
    [RULE_TYPES.min] = validate_min,
    [RULE_TYPES.max] = validate_max,
    [RULE_TYPES.min_length] = validate_min_length,
    [RULE_TYPES.max_length] = validate_max_length,
    [RULE_TYPES.pattern] = validate_pattern,
    [RULE_TYPES.enum] = validate_enum,
    [RULE_TYPES.custom] = validate_custom
}

-- Validate a single value against a rule set
function InputValidator.validate_value(value, rules, field_name)
    field_name = field_name or "unknown"
    
    if type(rules) ~= "table" then
        return false, ValidationError.new("Invalid rules specification", field_name, value)
    end
    
    -- Apply sanitization if specified
    if rules.sanitize then
        for _, sanitizer_name in ipairs(rules.sanitize) do
            local sanitizer = SANITIZERS[sanitizer_name]
            if sanitizer then
                value = sanitizer(value)
            else
                debug.warn("Unknown sanitizer: " .. sanitizer_name)
            end
        end
    end
    
    -- Apply validation rules in order
    for rule_type, rule_value in pairs(rules) do
        if VALIDATORS[rule_type] then
            local rule_config = {[rule_type] = rule_value}
            local valid, error_msg = VALIDATORS[rule_type](value, rule_config)
            
            if not valid then
                return false, ValidationError.new(error_msg, field_name, value)
            end
        end
    end
    
    return true, value -- Return sanitized value
end

-- Validate an object against a schema
function InputValidator.validate_object(object, schema)
    if type(object) ~= "table" then
        return false, ValidationError.new("Object must be a table", "root", object)
    end
    
    if type(schema) ~= "table" then
        return false, ValidationError.new("Schema must be a table", "root", schema)
    end
    
    local validated_object = {}
    local errors = {}
    
    -- Validate each field in the schema
    for field_name, field_rules in pairs(schema) do
        if field_name ~= "_strict" then
            local field_value = object[field_name]
            local valid, result = InputValidator.validate_value(field_value, field_rules, field_name)
            
            if valid then
                validated_object[field_name] = result
            else
                table.insert(errors, result)
            end
        end
    end
    
    -- Check for unexpected fields if strict mode is enabled
    if schema._strict then
        for field_name, field_value in pairs(object) do
            if not schema[field_name] and field_name ~= "_strict" then
                table.insert(errors, ValidationError.new(
                    "Unexpected field in strict mode", 
                    field_name, 
                    field_value
                ))
            end
        end
    end
    
    if #errors > 0 then
        return false, errors
    end
    
    return true, validated_object
end

-- Validate tool arguments
function InputValidator.validate_tool_args(tool_name, args, tool_schema)
    if not tool_schema or not tool_schema.parameters then
        return true, args -- No validation schema available
    end
    
    local schema = {}
    local parameters = tool_schema.parameters
    
    -- Convert tool schema to validation schema
    if parameters.properties then
        for prop_name, prop_def in pairs(parameters.properties) do
            local rules = {}
            
            -- Add type validation
            if prop_def.type then
                rules.type = prop_def.type
            end
            
            -- Add enum validation
            if prop_def.enum then
                rules.enum = prop_def.enum
            end
            
            -- Add required validation
            if parameters.required and type(parameters.required) == "table" then
                for _, required_field in ipairs(parameters.required) do
                    if required_field == prop_name then
                        rules.required = true
                        break
                    end
                end
            end
            
            schema[prop_name] = rules
        end
    end
    
    -- Add strict mode if tool schema specifies it
    if tool_schema.strict then
        schema._strict = true
    end
    
    local valid, result = InputValidator.validate_object(args, schema)
    
    if not valid then
        local error_msg = string.format("Tool %s validation failed", tool_name)
        if type(result) == "table" then
            local error_messages = {}
            for _, error in ipairs(result) do
                table.insert(error_messages, tostring(error))
            end
            error_msg = error_msg .. ": " .. table.concat(error_messages, "; ")
        end
        return false, error_msg
    end
    
    return true, result
end

-- Validate API key format
function InputValidator.validate_api_key(api_key, provider)
    local rules = {
        required = true,
        type = "string",
        min_length = 8,
        max_length = 256, -- Increased max length
        sanitize = {"trim"}
    }
    
    -- Provider-specific validation
    if provider == "openai" then
        rules.min_length = 20
        rules.custom = function(value)
            -- OpenAI keys can start with 'sk-' or 'sk-proj-'
            local starts_with_sk = value:sub(1, 3) == "sk-"
            local starts_with_sk_proj = value:sub(1, 8) == "sk-proj-"

            if not (starts_with_sk or starts_with_sk_proj) then
                return "OpenAI key must start with 'sk-' or 'sk-proj-'"
            end

            -- After prefix, check for invalid characters. Allow alphanumeric, '-', and '_'.
            local key_body = starts_with_sk_proj and value:sub(9) or value:sub(4)
            if key_body:match("[^a-zA-Z0-9_%-]") then
                return "OpenAI key contains invalid characters after prefix"
            end

            return true
        end
    elseif provider == "gemini" then
        rules.min_length = 30
        rules.custom = function(value)
            if value:sub(1, 6) ~= "AIzaSy" then
                return "Gemini key must start with 'AIzaSy'"
            end

            -- After prefix, check for invalid characters. Allow alphanumeric, '-', and '_'.
            local key_body = value:sub(7)
            if key_body:match("[^a-zA-Z0-9_%-]") then
                return "Gemini key contains invalid characters after prefix"
            end
            
            return true
        end
    else
        -- Generic pattern for other potential providers
        rules.pattern = "^[a-zA-Z0-9_.-]+$"
    end
    
    return InputValidator.validate_value(api_key, rules, "api_key")
end

-- Validate bot name
function InputValidator.validate_bot_name(bot_name)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 32,
        pattern = "bot_name",
        sanitize = {"trim", "lowercase", "alphanumeric_only"}
    }
    
    return InputValidator.validate_value(bot_name, rules, "bot_name")
end

-- Validate model name
function InputValidator.validate_model_name(model_name)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 100,
        pattern = "model_name",
        sanitize = {"trim"}
    }
    
    return InputValidator.validate_value(model_name, rules, "model_name")
end

-- Validate personality type
function InputValidator.validate_personality(personality)
    local rules = {
        required = true,
        type = "string",
        enum = {"jarvis", "all_might"},
        sanitize = {"trim", "lowercase"}
    }
    
    return InputValidator.validate_value(personality, rules, "personality")
end

-- Validate chat message
function InputValidator.validate_chat_message(message)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 2000,
        sanitize = {"trim", "escape_quotes"}
    }
    
    return InputValidator.validate_value(message, rules, "chat_message")
end

-- Common validation schemas
InputValidator.SCHEMAS = {
    tool_args = {
        action = {
            type = "string",
            required = true,
            enum = {"open", "close"},
            sanitize = {"trim", "lowercase"}
        },
        new_name = {
            type = "string",
            required = true,
            min_length = 1,
            max_length = 32,
            pattern = "bot_name",
            sanitize = {"trim", "lowercase", "alphanumeric_only"}
        },
        personality = {
            type = "string",
            required = true,
            enum = {"jarvis", "all_might"},
            sanitize = {"trim", "lowercase"}
        }
    }
}

-- Export validation error class
InputValidator.ValidationError = ValidationError

return InputValidator
]]

    local function install()
        print("Installing Jarvis v1.1.0.8...")
        print("Build #8 (2025-06-15 00:53:19 UTC)")

        -- Delete the main program file and the library directory to ensure a clean install.
        local program_path = "programs/jarvis"
        local lib_path = "programs/lib/jarvis"

        print("Removing old version if it exists...")
        if fs.exists(program_path) then
            print("  Deleting " .. program_path)
            fs.delete(program_path)
        end
        if fs.exists(lib_path) then
            print("  Deleting " .. lib_path)
            fs.delete(lib_path)
        end

        print("Installing new files...")
        for path, content in pairs(files) do
            print("Writing " .. path)
            local dir = path:match("(.*)/")
            if dir and not fs.exists(dir) then
                fs.makeDir(dir)
            end

            local file, err = fs.open(path, "w")
            if not file then
                printError("Failed to open " .. path .. ": " .. tostring(err))
                return false
            end
            file.write(content)
            file.close()
        end

        -- Create build info file
        local build_info_path = "/etc/jarvis/build_info.txt"
        local build_info_dir = "/etc/jarvis"
        if not fs.exists(build_info_dir) then
            fs.makeDir(build_info_dir)
        end

        local build_file = fs.open(build_info_path, "w")
        if build_file then
            build_file.write("Jarvis v1.1.0.8 - Build #8 (2025-06-15 00:53:19 UTC)")
            build_file.close()
        end

        -- Create placeholder config file if it doesn't exist
        local config_path = "/etc/jarvis/config.lua"
        if not fs.exists(config_path) then
            print("Creating placeholder config file at " .. config_path)
            local config_content = [[-- Configuration for Jarvis v1.1.0.8
local config = {}

-- Your OpenAI API key from https://platform.openai.com/api-keys
-- Replace YOUR_OPENAI_KEY_HERE with your actual OpenAI API key
config.openai_api_key = "YOUR_OPENAI_KEY_HERE"

-- Your Gemini API key from https://ai.google.dev/
-- Replace YOUR_GEMINI_KEY_HERE with your actual Gemini API key  
config.gemini_api_key = "YOUR_GEMINI_KEY_HERE"

-- The model to use
-- OpenAI models: "gpt-4o", "gpt-4o-mini", "gpt-4"
-- Gemini models: "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"
config.model = "gpt-4o"

return config
]]

            local config_file = fs.open(config_path, "w")
            if config_file then
                config_file.write(config_content)
                config_file.close()
                print("Placeholder config created. Edit " .. config_path .. " and add your API keys.")
            else
                printError("Failed to create config file at " .. config_path)
            end
        else
            print("Config file already exists at " .. config_path)
        end

        -- Create default LLM config file if it doesn't exist
        local llm_config_path = "/etc/jarvis/llm_config.lua"
        if not fs.exists(llm_config_path) then
            print("Creating default LLM config file at " .. llm_config_path)
            local llm_config_content = [[-- LLM Configuration for Jarvis v1.1.0.8
local config = {}

-- Default LLM provider ("openai" or "gemini")
config.provider = "openai"

-- Enable debug logging for LLM requests
config.debug_enabled = true

-- Request timeout in seconds
config.timeout = 30

-- Number of retry attempts for failed requests
config.retry_count = 3

-- Delay between retries in seconds
config.retry_delay = 1

-- Personality mode ("jarvis" or "all_might")
config.personality = "jarvis"

return config
]]

            local llm_config_file = fs.open(llm_config_path, "w")
            if llm_config_file then
                llm_config_file.write(llm_config_content)
                llm_config_file.close()
                print("Default LLM config created.")
            else
                printError("Failed to create LLM config file at " .. llm_config_path)
            end
        else
            print("LLM config file already exists at " .. llm_config_path)
        end

        -- Add to startup if not already present
        local startup_path = "startup.lua"
        local program_to_run = "programs/jarvis"

        local current_startup_content = ""
        if fs.exists(startup_path) then
            local f = fs.open(startup_path, "r")
            if f then
                current_startup_content = f.readAll()
                f.close()
            end
        end

        if not current_startup_content:find(program_to_run, 1, true) then
            print("Adding Jarvis to startup file.")
            local startup_file = fs.open(startup_path, "a")
            if startup_file then
                startup_file.write(('shell.run("%s")\n'):format(program_to_run))
                startup_file.close()
            end
        else
            print("Jarvis already in startup file.")
        end

        print([[

    Installation complete! Jarvis v1.1.0.8
    Build #8 (2025-06-15 00:53:19 UTC)

    IMPORTANT: Edit /etc/jarvis/config.lua and add your API keys:
    - OpenAI API key: https://platform.openai.com/api-keys
    - Gemini API key: https://ai.google.dev/

    Configuration files created:
    - /etc/jarvis/config.lua     (API keys and model settings)
    - /etc/jarvis/llm_config.lua (LLM provider settings)

    The new unified configuration system will automatically migrate
    your settings on first run.

    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: 'programs/jarvis'
    ]])

        return true
    end

    local success = install()
    if not success then
        printError("Installation failed!")
    end
