-- llm.lua
-- Handles communication with LLM APIs using a provider abstraction layer.

local LLM = {}
local debug = require("lib.jarvis.debug")
local LLMConfig = require("config.llm_config")
local ProviderFactory = require("providers.provider_factory")

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
    return provider:request(api_key, model, messages, tools)
end

-- Make a request with a specific provider (overrides config)
function LLM.request_with_provider(provider_type, api_key, model, messages, tools)
    debug.info("Using specific provider: " .. provider_type)
    
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    local provider = ProviderFactory.create_provider(provider_type)
    return provider:request(api_key, model, messages, tools)
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