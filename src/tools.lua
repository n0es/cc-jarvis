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