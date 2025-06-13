-- llm_config.lua
-- Configuration management for LLM providers

local ProviderFactory = require("providers.provider_factory")

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
local CONFIG_FILE = "config/llm_settings.json"

-- Load configuration from file
function LLMConfig.load_config()
    -- Try to load from file
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local loaded_config = textutils.unserializeJSON(content)
            if loaded_config then
                -- Merge with defaults
                current_config = {}
                for k, v in pairs(default_config) do
                    current_config[k] = loaded_config[k] or v
                end
                return true, "Configuration loaded successfully"
            end
        end
    end
    
    -- Fall back to defaults
    current_config = {}
    for k, v in pairs(default_config) do
        current_config[k] = v
    end
    
    return false, "Using default configuration"
end

-- Save configuration to file
function LLMConfig.save_config()
    -- Ensure config directory exists
    if not fs.exists("config") then
        fs.makeDir("config")
    end
    
    local file = fs.open(CONFIG_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(current_config))
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