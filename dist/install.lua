
    -- Jarvis Installer

    local files = {}

    -- Packed files will be inserted here by the build script.
    files["programs/jarvis"] = [=[
-- Jarvis: Main Program
-- An LLM-powered assistant for ComputerCraft.

-- Load modules
local llm = require("lib.jarvis.llm")
local tools = require("lib.jarvis.tools")
local chatbox_queue = require("lib.jarvis.chatbox_queue")

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
    print("[DEBUG] Processing LLM response...")
    local content = extract_response_content(response_data)
    if content then
        print("[DEBUG] Successfully extracted content: " .. content)
        return content
    end
    
    -- If we can't extract content, return an error message
    print("[DEBUG] Failed to extract content from response")
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

    print("Jarvis is online. Waiting for messages.")
    print("Current bot name: " .. tools.get_bot_name())

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
            print("[INFO] Context cleared due to timeout (" .. CONTEXT_TIMEOUT / 20 / 60 .. " minutes)")
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
            print("[INFO] Listen mode ended")
        end
        
        -- If bot is mentioned, enter listen mode
        if is_bot_mentioned(message) then
            in_listen_mode = true
            listen_mode_end_time = current_time + LISTEN_MODE_TIMEOUT
            print("[INFO] Bot mentioned - entering listen mode for " .. LISTEN_MODE_TIMEOUT / 20 / 60 .. " minutes")
            return true
        end
        
        -- If in listen mode, listen to all messages
        if in_listen_mode then
            print("[INFO] Listening due to active listen mode")
            return true
        end
        
        return false
    end

    while true do
        -- Process the chatbox queue
        chatbox_queue.process()
        
        -- Show queue status if there are messages waiting
        local queue_size = chatbox_queue.getQueueSize()
        if queue_size > 0 then
            print("[DEBUG] Messages in queue: " .. queue_size)
        end
        
        -- Use pullEventRaw with timeout to allow queue processing
        local event_data = {os.pullEventRaw(0.1)}  -- 0.1 second timeout
        
        if event_data[1] == "chat" then
            local _, player, message_text = table.unpack(event_data)
            local bot_name = tools.get_bot_name()
            local current_time = os.clock() * 20

            -- Check for context timeout before processing message
            check_context_timeout()

            -- Check if we should respond to this message
            if should_listen_to_message(message_text) then
            print(player .. " says: " .. message_text)
            
            -- Update last message time
            last_message_time = current_time
            
            table.insert(messages, { role = "user", content = message_text })

            -- Call the LLM (without tools for now)
            print("Thinking...")
            local ok, response = llm.request(config.openai_api_key, config.model, messages) -- removed tool_schemas parameter

            if not ok then
                printError("LLM Request Failed: " .. tostring(response))
                chat.send("Sorry, I encountered an error.")
                table.remove(messages) -- Remove the failed user message
                goto continue
            end

            -- Process response using the new format
            local result = process_llm_response(response)
            print("[DEBUG] About to send message to chat: " .. tostring(result))
            chat.send(tostring(result))
            print("[DEBUG] Message queued for chat")
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
end

main() 
]=]
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
    
    local results = {}
    
    -- Test 1: General HTTP connectivity
    local test_url = "https://httpbin.org/get"
    print("Testing HTTP connectivity to " .. test_url)
    
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
    print("Testing connectivity to OpenAI domain...")
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

local API_URL = "https://api.openai.com/v1/responses"

-- Test basic connectivity to OpenAI
function LLM.test_openai_connectivity()
    print("[DEBUG] Testing basic connectivity to api.openai.com...")
    
    -- Try a simpler test - just check if we can resolve the domain
    -- Instead of hitting the root, try a known endpoint that should return a proper error
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    print("[DEBUG] Attempting simple connectivity test...")
    local success, response = http.get("https://api.openai.com/v1/models", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        print("[DEBUG] OpenAI API is reachable (got response from /v1/models)")
        return true, "OpenAI API reachable"
    else
        local err_msg = "Cannot reach OpenAI API"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
                print("[DEBUG] Error: " .. response)
            end
        end
        print("[DEBUG] " .. err_msg)
        return false, err_msg
    end
end

-- Convert standard OpenAI messages format to the new input format
local function convert_messages_to_input(messages)
    local input = {}
    
    for _, message in ipairs(messages) do
        local converted_message = {
            role = message.role,
            content = {
                {
                    type = message.role == "assistant" and "output_text" or "input_text",
                    text = message.content
                }
            }
        }
        
        -- Add id for assistant messages (required by the new format)
        if message.role == "assistant" then
            converted_message.id = "msg_" .. tostring(os.epoch("utc")) .. math.random(100000, 999999)
        end
        
        table.insert(input, converted_message)
    end
    
    return input
end

function LLM.request(api_key, model, messages, tools)
    print("[DEBUG] Starting LLM request...")
    print("[DEBUG] Target URL: " .. API_URL)
    
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
        return false, "Invalid API key format"
    end
    
    print("[DEBUG] Model: " .. tostring(model))
    print("[DEBUG] Messages count: " .. #messages)
    
    -- Use exact same headers as working curl example
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }
    print("[DEBUG] Headers prepared (matching curl format)")

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
    


    print("[DEBUG] Serializing request body...")
    -- Use the same serialization as working GPT.lua example
    local body_json = textutils.serializeJSON(body)
    print("[DEBUG] Used serializeJSON (matching GPT.lua)")
    
    -- Fix the tools field to be an empty array instead of empty object
    body_json = body_json:gsub('"tools":{}', '"tools":[]')
    print("[DEBUG] Fixed tools field to be empty array")
    
    print("[DEBUG] Request body serialized successfully")
    print("[DEBUG] Request size: " .. #body_json .. " bytes")
    
    -- Write comprehensive debug log
    print("[DEBUG] Writing comprehensive debug log...")
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
        
        local debug_file = fs.open("debug_full.json", "w")
        if debug_file then
            debug_file.write(textutils.serializeJSON(debug_log))
            debug_file.close()
            print("[DEBUG] Full debug log written to debug_full.json")
        else
            print("[DEBUG] Warning: Could not write full debug log")
        end
    end
    
    -- Write initial debug state
    write_debug_log()
    
    -- Also write the formatted JSON request and response separately for easy copying
    local debug_request_file = fs.open("debug_request.json", "w")
    if debug_request_file then
        debug_request_file.write(body_json)
        debug_request_file.close()
        print("[DEBUG] Request written to debug_request.json")
    end
    
    -- Validate JSON before sending
    if not body_json or body_json == "" then
        return false, "Failed to serialize request body to JSON"
    end
    
    -- Show first 200 chars of request for debugging
    print("[DEBUG] Request preview: " .. body_json:sub(1, 200) .. (#body_json > 200 and "..." or ""))
    
    print("[DEBUG] Making async HTTP request (matching curl pattern)...")
    
    -- Use exact same pattern as working GPT.lua example
    http.request(API_URL, body_json, headers)
    
    print("[DEBUG] HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling (exact same as GPT.lua)
    while true do
        local event, url, handle = os.pullEvent()
        
        if event == "http_success" then
            print("[DEBUG] HTTP request successful, reading response...")
            local response_body = handle.readAll()
            handle.close()
            print("[DEBUG] Response received: " .. #response_body .. " bytes")
            
            -- Write the response to separate file for easy copying
            local debug_response_file = fs.open("debug_response.json", "w")
            if debug_response_file then
                debug_response_file.write(response_body)
                debug_response_file.close()
                print("[DEBUG] Response written to debug_response.json")
            end
            
            -- Show first 200 chars of response for debugging
            print("[DEBUG] Response preview: " .. response_body:sub(1, 200) .. (#response_body > 200 and "..." or ""))
            
            print("[DEBUG] Parsing JSON response...")
            local response_data = textutils.unserializeJSON(response_body)
            print("[DEBUG] Used unserializeJSON (matching GPT.lua)")

            if not response_data then
                print("[DEBUG] Failed to parse JSON response")
                local error_msg = "Failed to decode JSON response from API: " .. tostring(response_body)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response_raw = response_body
                })
                return false, error_msg
            end
            print("[DEBUG] JSON response parsed successfully")
            
            if response_data.error then
                print("[DEBUG] API returned error: " .. response_data.error.message)
                local error_msg = "API Error: " .. response_data.error.message
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response = response_data,
                    response_raw = response_body
                })
                return false, error_msg
            end

            print("[DEBUG] LLM request completed successfully")
            write_debug_log({
                success = true,
                response = response_data,
                response_raw = response_body
            })
            return true, response_data
            
        elseif event == "http_failure" then
            print("[DEBUG] HTTP request failed with http_failure event")
            local error_msg = "HTTP request failed (http_failure event)"
            if handle then
                if type(handle) == "string" then
                    error_msg = error_msg .. ": " .. handle
                    print("[DEBUG] Error details: " .. handle)
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
files["programs/lib/jarvis/lib/jarvis/chatbox_queue.lua"] = [[
-- ChatBox Queue Module
-- Manages message sending with a queue to prevent rapid message issues

local chatbox_queue = {}

-- Load tools module for bot name management
local tools = require("lib.jarvis.tools")

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
    print("[ChatBox Queue] Initialized with " .. (delay_seconds or 1) .. " second delay")
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
    
    print("[ChatBox Queue] Message queued: " .. tostring(message))
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
            print("[ChatBox Queue] Message sent: " .. msg_data.message)
            last_send_time = current_time
        else
            print("[ChatBox Queue] Failed to send message: " .. tostring(err))
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
    print("[ChatBox Queue] Cleared " .. cleared_count .. " messages from queue")
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

    Installation complete!
    IMPORTANT: Edit /etc/jarvis/config.lua and add your OpenAI API key.
    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: 'programs/jarvis'
    ]])
    end

    install()
