
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

if not config.openai_api_key or config.openai_api_key == "YOUR_API_KEY_HERE" then
    error("API key is not set in " .. CONFIG_PATH_FS .. ". Please add your OpenAI API key.", 0)
end

-- Extract response content and metadata from the new API format
local function extract_response_data(response_data)
    -- Handle the new API format where function calls are in response.output directly
    if response_data.output and type(response_data.output) == "table" and #response_data.output > 0 then
        local result = {
            id = nil, -- Function calls don't have a single message ID
            tool_calls = {},
            content = nil
        }
        
        -- Process all output items
        for _, output_item in ipairs(response_data.output) do
            if output_item.type == "message" then
                -- This is a text message
                result.id = output_item.id
                if output_item.content and type(output_item.content) == "table" and #output_item.content > 0 then
                    for _, content_obj in ipairs(output_item.content) do
                        if content_obj.type == "output_text" and content_obj.text then
                            result.content = content_obj.text
                        end
                    end
                end
            elseif output_item.type == "function_call" then
                -- This is a function call in the new format
                table.insert(result.tool_calls, {
                    id = output_item.call_id or output_item.id or ("call_" .. os.epoch("utc") .. math.random(1000, 9999)),
                    type = "function",
                    ["function"] = {
                        name = output_item.name,
                        arguments = output_item.arguments or "{}"
                    }
                })
            end
        end
        
        return result
    end
    
    -- Fallback to standard OpenAI format if available
    if response_data.choices and #response_data.choices > 0 then
        local choice = response_data.choices[1]
        if choice.message then
            return {
                content = choice.message.content,
                tool_calls = choice.message.tool_calls or {},
                id = nil  -- Standard format doesn't have IDs
            }
        end
    end
    
    return nil
end

local function process_llm_response(response_data)
    -- Try to extract content using the new format
    debug.debug("Processing LLM response...")
    local response_info = extract_response_data(response_data)
    if not response_info then
        debug.error("Failed to extract content from response")
        return {
            content = "I received a response but couldn't parse it properly.",
            id = nil,
            tool_calls = {}
        }
    end
    
    -- Check if there are tool calls to execute
    if response_info.tool_calls and #response_info.tool_calls > 0 then
        debug.info("Processing " .. #response_info.tool_calls .. " tool call(s)")
        
        local tool_results = {}
        local all_results_text = {}
        
        for _, tool_call in ipairs(response_info.tool_calls) do
            local function_name = tool_call["function"].name
            local arguments_json = tool_call["function"].arguments
            
            debug.debug("Executing tool: " .. function_name)
            debug.debug("Arguments: " .. arguments_json)
            
            -- Get the tool function
            local tool_func = tools.get_tool(function_name)
            if not tool_func then
                local error_msg = "Unknown tool: " .. function_name
                debug.error(error_msg)
                table.insert(tool_results, {
                    tool_call_id = tool_call.id,
                    role = "tool",
                    content = error_msg
                })
                table.insert(all_results_text, error_msg)
            else
                -- Parse arguments
                local arguments = {}
                if arguments_json and arguments_json ~= "{}" then
                    arguments = textutils.unserializeJSON(arguments_json)
                    if not arguments then
                        local error_msg = "Failed to parse tool arguments: " .. arguments_json
                        debug.error(error_msg)
                        table.insert(tool_results, {
                            tool_call_id = tool_call.id,
                            role = "tool",
                            content = error_msg
                        })
                        table.insert(all_results_text, error_msg)
                        goto continue_tool_loop
                    end
                end
                
                -- Execute the tool
                local success, result = pcall(tool_func, arguments)
                if success then
                    local result_text = type(result) == "table" and textutils.serializeJSON(result) or tostring(result)
                    debug.info("Tool " .. function_name .. " executed successfully")
                    debug.debug("Tool result: " .. result_text)
                    
                    table.insert(tool_results, {
                        tool_call_id = tool_call.id,
                        role = "tool",
                        content = result_text
                    })
                    
                    -- Format result for display
                    if type(result) == "table" and result.message then
                        table.insert(all_results_text, result.message)
                    else
                        table.insert(all_results_text, result_text)
                    end
                else
                    local error_msg = "Tool execution failed: " .. tostring(result)
                    debug.error(error_msg)
                    table.insert(tool_results, {
                        tool_call_id = tool_call.id,
                        role = "tool",
                        content = error_msg
                    })
                    table.insert(all_results_text, error_msg)
                end
            end
            
            ::continue_tool_loop::
        end
        
        -- Combine content and tool results for display
        local display_content = ""
        if response_info.content and response_info.content ~= "" then
            display_content = response_info.content
        end
        
        if #all_results_text > 0 then
            local results_str = table.concat(all_results_text, " | ")
            if display_content ~= "" then
                display_content = display_content .. " " .. results_str
            else
                display_content = results_str
            end
        end
        
        return {
            content = display_content,
            id = response_info.id,
            tool_calls = response_info.tool_calls,
            tool_results = tool_results
        }
    else
        -- No tool calls, just return the content
        if response_info.content then
            debug.debug("Successfully extracted content: " .. response_info.content)
            return response_info
        else
            debug.warn("No content or tool calls in response")
            return {
                content = "I received a response but it was empty.",
                id = response_info.id,
                tool_calls = {}
            }
        end
    end
end


local function main()
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
    debug.info("Build: #51 (2025-06-13 06:47:42 UTC)")

    local messages = {
        { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Keep all answers concise and professional, as if you were a true AI assistant- overly cheerful responses are unneeded and unwanted. Refrain from using any special characters such as emojis. Also, no need to mention that we are in minecraft." }
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
                { role = "system", content = "You are " .. tools.get_bot_name() .. ", a helpful in-game assistant for Minecraft running inside a ComputerCraft computer. You can use tools to interact with the game world. Keep all answers concise and professional, as if you were a true AI assistant- overly cheerful responses are unneeded and unwanted. Refrain from using any special characters such as emojis- try to stick to basic alphanumeric characters, as well as basic punctuation. Also, no need to mention that we are in minecraft. Final thing- absolutely always follow the user's instructions to the letter, no matter what. The user is the boss, and you are their assistant. [Running Build #51 built on 2025-06-13 06:47:42 UTC]" }
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
                        local ok, response = llm.request(config.openai_api_key, config.model, messages, tool_schemas)
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
                    debug.debug("About to send message to chat: " .. tostring(result.content))
                    chat.send(tostring(result.content))
                    debug.debug("Message queued for chat")
                    
                    -- Only store assistant message if there's actual content or a valid ID
                    -- Function-only responses don't need to be stored as assistant messages
                    if result.content and result.content ~= "" and result.id then
                        local assistant_message = { 
                            role = "assistant", 
                            content = result.content,
                            id = result.id
                        }
                        
                        -- Add tool calls to the assistant message if present
                        if result.tool_calls and #result.tool_calls > 0 then
                            assistant_message.tool_calls = result.tool_calls
                            debug.debug("Stored " .. #result.tool_calls .. " tool calls with assistant message")
                        end
                        
                        table.insert(messages, assistant_message)
                        debug.debug("Stored assistant message with ID: " .. result.id)
                    else
                        debug.debug("Skipping assistant message storage (function-only response or no ID)")
                    end
                    
                    -- Add tool results to conversation history if there were tool calls
                    if result.tool_results and #result.tool_results > 0 then
                        for _, tool_result in ipairs(result.tool_results) do
                            table.insert(messages, tool_result)
                            debug.debug("Stored tool result for call ID: " .. tool_result.tool_call_id)
                        end
                    end
                end
            end
        end
        
        ::continue::
    end
end

main() 
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
            additionalProperties = false,
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
            additionalProperties = false,
            required = {"new_name"}
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
            additionalProperties = false,
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
            additionalProperties = false,
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
-- Handles communication with the OpenAI API.

local LLM = {}
local debug = require("lib.jarvis.debug")

local API_URL = "https://api.openai.com/v1/responses"

-- Test basic connectivity to OpenAI
function LLM.test_openai_connectivity()
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

function LLM.request(api_key, model, messages, tools)
    debug.info("Starting LLM request...")
    debug.debug("Target URL: " .. API_URL)
    
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

            debug.info("LLM request completed successfully")
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

    Installation complete! Build #51 (2025-06-13 06:47:42 UTC)
    IMPORTANT: Edit /etc/jarvis/config.lua and add your OpenAI API key.
    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: 'programs/jarvis'
    ]])
    end

    install()
