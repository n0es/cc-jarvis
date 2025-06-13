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