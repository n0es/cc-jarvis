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
    
    -- Handle Gemini format with candidates
    if response_data.candidates and #response_data.candidates > 0 then
        local candidate = response_data.candidates[1]
        if candidate.content and candidate.content.parts then
            local content = ""
            local tool_calls = {}
            
            -- Extract text content from parts
            for _, part in ipairs(candidate.content.parts) do
                if part.text then
                    content = content .. part.text
                elseif part.functionCall then
                    -- Handle Gemini function calls
                    table.insert(tool_calls, {
                        id = "call_" .. os.epoch("utc") .. math.random(1000, 9999),
                        type = "function",
                        ["function"] = {
                            name = part.functionCall.name,
                            arguments = textutils.serializeJSON(part.functionCall.args or {})
                        }
                    })
                end
            end
            
            -- Trim trailing whitespace from the final content
            content = content:gsub("%s+$", "")
            
            return {
                content = content,
                tool_calls = tool_calls,
                id = response_data.responseId
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
                    
                    -- Check if personality was changed and update system prompt
                    if function_name == "change_personality" then
                        debug.info("Personality changed, updating system prompt in history...")
                        if #messages > 0 and messages[1].role == "system" then
                            messages[1].content = llm.get_system_prompt(tools.get_bot_name())
                            debug.info("System prompt updated to: " .. llm.get_current_personality())
                        end
                    end

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