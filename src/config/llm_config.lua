-- llm_config.lua
-- Configuration management for LLM providers

local ProviderFactory = require("lib.jarvis.providers.provider_factory")
local debug = require("lib.jarvis.debug")

local LLMConfig = {}

-- Default configuration
local default_config = {
    provider = ProviderFactory.DEFAULT_PROVIDER,
    debug_enabled = true,
    timeout = 30,  -- seconds
    retry_count = 3,
    retry_delay = 1,  -- seconds
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
end

-- Initialize configuration on load
LLMConfig.load_config()

return LLMConfig 