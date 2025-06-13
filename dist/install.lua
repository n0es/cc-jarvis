
    -- Jarvis Installer

    local files = {}

    -- Packed files will be inserted here by the build script.
    files["programs/jarvis"] = [[
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

    local success, response_data = llm.request(api_key, config.model, messages, tools.get_tools())
    
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
files["programs/lib/jarvis/tools.lua"] = [[
-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}
local debug = require("lib.jarvis.debug")
local llm = require("lib.jarvis.llm")

-- A registry to hold the function definitions and their callable implementations.
local registry = {}

-- Bot name management
local BOT_NAME_FILE = "/etc/jarvis/botname.txt"
local DEFAULT_BOT_NAME = "jarvis"

-- Modem management
local modem_peripheral = nil
local bot_channel = 32

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

-- Function to set modem peripheral for door control
function Tools.set_modem(modem, channel)
    modem_peripheral = modem
    bot_channel = channel or 32
    debug.debug("Tools modem set to channel " .. bot_channel)
end

-- Tool Definition: change_name
-- This function changes the bot's name.
function Tools.change_name(new_name)
    return Tools.set_bot_name(new_name)
end

-- Tool Definition: change_personality
-- This function changes the bot's personality mode.
function Tools.change_personality(personality)
    local success, message = llm.set_personality(personality)
    if success then
        if personality == "all_might" then
            return { success = true, message = "PLUS ULTRA! I have transformed into the Symbol of Peace! " .. message }
        else
            return { success = true, message = message }
        end
    else
        return { success = false, message = message }
    end
end

-- Tool Definition: door_control
-- This function opens or closes the base door via modem.
function Tools.door_control(action)
    if not modem_peripheral then
        return { success = false, message = "Modem not available for door control" }
    end
    
    if not action or (action ~= "open" and action ~= "close") then
        return { success = false, message = "Invalid action. Use 'open' or 'close'" }
    end
    
    debug.info("Sending door control command: " .. action)
    debug.debug("Transmitting on channel 25, reply channel " .. bot_channel)
    
    -- Send the command
    modem_peripheral.transmit(25, bot_channel, action)
    
    return { success = true, message = "Door " .. action .. " command sent" }
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
    func = function(args)
        local new_name = args and args.new_name
        return Tools.change_name(new_name)
    end,
    schema = {
        type = "function",
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
            required = {"new_name"}
        },
        strict = true
    },
}

-- Register the change_personality tool
registry.change_personality = {
    func = function(args)
        local personality = args and args.personality
        return Tools.change_personality(personality)
    end,
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
        description = "Test HTTP connectivity to diagnose connection issues.",
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
    func = function(args)
        local action = args and args.action
        return Tools.door_control(action)
    end,
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
-- Handles communication with LLM APIs using a provider abstraction layer.

local LLM = {}
local debug = require("lib.jarvis.debug")
local LLMConfig = require("lib.jarvis.config.llm_config")
local ProviderFactory = require("lib.jarvis.providers.provider_factory")

-- Test connectivity to the current provider
function LLM.test_connectivity()
    local provider_type = LLMConfig.get_provider()
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
    local provider_type = LLMConfig.get_provider()
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
    return LLMConfig.get_provider()
end

function LLM.set_provider(provider_type)
    local success, message = LLMConfig.set_provider(provider_type)
    if success then
        LLMConfig.save_config()
        debug.info("Provider switched to: " .. provider_type)
    else
        debug.error("Failed to set provider: " .. message)
    end
    return success, message
end

function LLM.get_available_providers()
    return LLMConfig.get_available_providers()
end

-- Personality management functions
function LLM.get_current_personality()
    return LLMConfig.get_personality()
end

function LLM.set_personality(personality_type)
    local success, message = LLMConfig.set_personality(personality_type)
    if success then
        LLMConfig.save_config()
        debug.info("Personality switched to: " .. personality_type)
    else
        debug.error("Failed to set personality: " .. message)
    end
    return success, message
end

function LLM.get_available_personalities()
    return LLMConfig.get_available_personalities()
end

function LLM.get_system_prompt(bot_name)
    return LLMConfig.get_system_prompt(bot_name)
end

function LLM.print_config()
    LLMConfig.print_config()
end

-- Save current configuration
function LLM.save_config()
    return LLMConfig.save_config()
end

-- Reset to default configuration
function LLM.reset_config()
    return LLMConfig.reset_to_defaults()
end

return LLM 
]]
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
    local system_instruction = nil

    -- First pass to map tool call IDs to function names for Gemini's required format
    local tool_call_id_to_name = {}
    for _, message in ipairs(messages) do
        if message.role == "assistant" and message.tool_calls then
            for _, tool_call in ipairs(message.tool_calls) do
                if tool_call.id and tool_call["function"] and tool_call["function"].name then
                    tool_call_id_to_name[tool_call.id] = tool_call["function"].name
                end
            end
        end
    end

    for _, message in ipairs(messages) do
        if message.role == "system" then
            system_instruction = { parts = { { text = message.content or "" } } }

        elseif message.role == "user" then
            table.insert(contents, {
                role = "user",
                parts = { { text = message.content or "" } }
            })
            
        elseif message.role == "assistant" then
            if message.tool_calls and #message.tool_calls > 0 then
                -- This is a tool-calling turn from the assistant
                local parts = {}
                for _, tool_call in ipairs(message.tool_calls) do
                    if tool_call["function"] then
                        local func = tool_call["function"]
                        local args = textutils.unserializeJSON(func.arguments or "{}") or {}
                        table.insert(parts, {
                            functionCall = {
                                name = func.name,
                                args = args
                            }
                        })
                    end
                end
                if #parts > 0 then
                    table.insert(contents, { role = "model", parts = parts })
                end
            elseif message.content and message.content ~= "" then
                -- This is a standard text response from the assistant
                table.insert(contents, { role = "model", parts = { { text = message.content } } })
            end

        elseif message.role == "tool" then
            local func_name = tool_call_id_to_name[message.tool_call_id]
            if func_name then
                local response_data = textutils.unserializeJSON(message.content or "")
                -- Gemini expects the 'response' to be a JSON object.
                -- If the tool returned a raw string, wrap it in a table.
                if not response_data then
                    response_data = { result = message.content or "empty result" }
                end
                
                table.insert(contents, {
                    role = "tool",
                    parts = {
                        {
                            functionResponse = {
                                name = func_name,
                                response = response_data
                            }
                        }
                    }
                })
            else
                debug.warn("Orphaned tool call response found for ID: " .. tostring(message.tool_call_id))
            end
        end
    end
    
    return contents, system_instruction
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
    local contents, system_instruction = self:convert_messages_to_contents(messages)
    
    -- Build Gemini request body - match Google's format exactly
    local body = {
        contents = contents,
        generationConfig = {
            temperature = 0.2,
            topP = 0.95,
            topK = 64,
            maxOutputTokens = 8192
        }
    }
    
    -- Add system instruction if present
    if system_instruction then
        body.systemInstruction = system_instruction
    end
    
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
        debug.error("No candidates found in Gemini response")
        table.insert(results, { type = "error", content = "Invalid response from API" })
        return results
    end
    
    local candidate = response_data.candidates[1]
    
    if not candidate.content or not candidate.content.parts or #candidate.content.parts == 0 then
        debug.warn("Candidate content is empty or has no parts")
        if candidate.finishReason == "SAFETY" then
            table.insert(results, { type = "message", content = "I cannot respond to that due to safety settings." })
        else
            table.insert(results, { type = "message", content = "I received an empty response." })
        end
        return results
    end
    
    -- Iterate through all parts of the response
    for _, part in ipairs(candidate.content.parts) do
        if part.text then
            debug.info("Received text part from Gemini")
            table.insert(results, { type = "message", content = part.text })
        end
        
        if part.functionCall then
            debug.info("Received function call part from Gemini: " .. part.functionCall.name)
            local args_json = textutils.serializeJSON(part.functionCall.args or {})
            
            table.insert(results, {
                type = "tool_call",
                tool_name = part.functionCall.name,
                tool_args_json = args_json
            })
        end
    end
    
    return results
end

return GeminiProvider 
]]
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
                print("Placeholder config created. Edit " .. config_path .. " and add your API key.")
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
            local config_dir = "/etc/jarvis"
            if not fs.exists(config_dir) then
                fs.makeDir(config_dir)
            end

            local llm_config_content = [[-- LLM Configuration for Jarvis
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

    Installation complete! Build #80 (2025-06-13 21:33:43 UTC)

    IMPORTANT: Edit /etc/jarvis/config.lua and add your API keys:
    - OpenAI API key: https://platform.openai.com/api-keys
    - Gemini API key: https://ai.google.dev/

    Configuration files created:
    - /etc/jarvis/config.lua     (API keys and model settings)
    - /etc/jarvis/llm_config.lua (LLM provider settings)

    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: 'programs/jarvis'
    ]])
    end

    install()
