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
    local tool_call_id = "call_" .. os.epoch("utc") .. math.random(1000, 9999)
    
    debug.info("Executing tool: " .. tool_name)
    
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
    
    -- Create tool call record
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
    
    -- Record tool result
    table.insert(messages_history, {
        tool_call_id = tool_call_id,
        role = "tool",
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