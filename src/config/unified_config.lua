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