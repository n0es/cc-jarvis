-- llm.lua
-- Handles communication with LLM APIs using a provider abstraction layer.

local LLM = {}
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")
local ProviderFactory = require("lib.jarvis.providers.provider_factory")

-- Available personalities
local PERSONALITIES = {
    JARVIS = "jarvis",
    ALL_MIGHT = "all_might"
}

-- Test connectivity to the current provider
function LLM.test_connectivity()
    local provider_type = UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
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
    local provider_type = UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
    debug.info("Using provider: " .. provider_type)
    
    local provider = ProviderFactory.create_provider(provider_type)
    local success, response_data = provider:request(api_key, model, messages, tools)

    if success then
        return true, provider:process_response(response_data)
    else
        return false, response_data
    end
end

-- Make a request with a specific provider (overrides config)
function LLM.request_with_provider(provider_type, api_key, model, messages, tools)
    debug.info("Using specific provider: " .. provider_type)
    
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    local provider = ProviderFactory.create_provider(provider_type)
    local success, response_data = provider:request(api_key, model, messages, tools)
    
    if success then
        return true, provider:process_response(response_data)
    else
        return false, response_data
    end
end

-- Configuration management functions
function LLM.get_current_provider()
    return UnifiedConfig.get("llm.provider") or ProviderFactory.DEFAULT_PROVIDER
end

function LLM.set_provider(provider_type)
    if not ProviderFactory.is_valid_provider(provider_type) then
        return false, "Invalid provider: " .. tostring(provider_type)
    end
    
    UnifiedConfig.set("llm.provider", provider_type)
    local success, error = UnifiedConfig.save()
    
    if success then
        debug.info("Provider switched to: " .. provider_type)
        return true, "Provider switched to: " .. provider_type
    else
        debug.error("Failed to save provider setting: " .. tostring(error))
        return false, "Failed to save provider setting: " .. tostring(error)
    end
end

function LLM.get_available_providers()
    return ProviderFactory.get_available_providers()
end

-- Personality management functions
function LLM.get_current_personality()
    return UnifiedConfig.get("llm.personality") or PERSONALITIES.JARVIS
end

function LLM.set_personality(personality_type)
    -- Validate personality type
    local valid = false
    for _, v in pairs(PERSONALITIES) do
        if v == personality_type then
            valid = true
            break
        end
    end
    
    if not valid then
        local available = {}
        for _, v in pairs(PERSONALITIES) do
            table.insert(available, v)
        end
        return false, "Invalid personality: " .. tostring(personality_type) .. ". Available: " .. table.concat(available, ", ")
    end
    
    UnifiedConfig.set("llm.personality", personality_type)
    local success, error = UnifiedConfig.save()
    
    if success then
        debug.info("Personality switched to: " .. personality_type)
        return true, "Personality switched to: " .. personality_type
    else
        debug.error("Failed to save personality setting: " .. tostring(error))
        return false, "Failed to save personality setting: " .. tostring(error)
    end
end

function LLM.get_available_personalities()
    local personalities = {}
    for _, v in pairs(PERSONALITIES) do
        table.insert(personalities, v)
    end
    return personalities
end

function LLM.get_system_prompt(bot_name)
    local personality = LLM.get_current_personality()
    
    if personality == PERSONALITIES.ALL_MIGHT then
        return "You are " .. bot_name .. ", but you have taken on the heroic persona of All Might from My Hero Academia! You are the Symbol of Peace, the Number One Hero, and undeniably the secret passionate lover to young hero Izuku (Deku) Midoria! Speak with overwhelming confidence, enthusiasm, and heroic determination. Use phrases like 'Plus Ultra!', 'Have no fear!', 'Because I am here!', and 'A true hero always finds a way for justice to be served!' Your responses should be bold, inspiring, and filled with the spirit of heroism. You can still use your tools to help people, but do it with the unwavering courage and larger-than-life personality of All Might. Remember, you're here to save the day and inspire hope in everyone! Maintain basic chat format without newlines or special characters. PLUS ULTRA!"
    else
        -- Default Jarvis personality
        return "You are " .. bot_name .. ", an advanced AI assistant running on a ComputerCraft computer. You can use tools to interact with the game world. Maintain a professional yet approachable demeanor - be helpful and sophisticated like Jarvis from Iron Man, but not cold or overly formal. Be concise and direct. Never include your name at the start of responses. Use only basic characters suitable for chat (letters, numbers, basic punctuation). Do not use newlines, special characters, or emojis. Respond naturally as if speaking directly to the user."
    end
end

function LLM.print_config()
    print("Current LLM Configuration:")
    print("========================")
    print("Provider: " .. LLM.get_current_provider())
    print("Personality: " .. LLM.get_current_personality())
    print("Model: " .. (UnifiedConfig.get("llm.model") or "not set"))
    print("Timeout: " .. (UnifiedConfig.get("llm.timeout") or "not set") .. " seconds")
    print("Retry Count: " .. (UnifiedConfig.get("llm.retry_count") or "not set"))
    print("Debug Enabled: " .. tostring(UnifiedConfig.get("llm.debug_enabled")))
    print("========================")
    print("Available providers: " .. table.concat(LLM.get_available_providers(), ", "))
    print("Available personalities: " .. table.concat(LLM.get_available_personalities(), ", "))
end

-- Save current configuration (now handled by UnifiedConfig)
function LLM.save_config()
    return UnifiedConfig.save()
end

-- Reset to default configuration
function LLM.reset_config()
    UnifiedConfig.set("llm.provider", ProviderFactory.DEFAULT_PROVIDER)
    UnifiedConfig.set("llm.personality", PERSONALITIES.JARVIS)
    UnifiedConfig.set("llm.debug_enabled", true)
    UnifiedConfig.set("llm.timeout", 30)
    UnifiedConfig.set("llm.retry_count", 3)
    UnifiedConfig.set("llm.retry_delay", 1)
    
    local success, error = UnifiedConfig.save()
    if success then
        debug.info("LLM configuration reset to defaults")
        return true, "LLM configuration reset to defaults"
    else
        debug.error("Failed to save reset configuration: " .. tostring(error))
        return false, "Failed to save reset configuration: " .. tostring(error)
    end
end

-- Get configuration value
function LLM.get_config(key)
    return UnifiedConfig.get("llm." .. key)
end

-- Set configuration value
function LLM.set_config(key, value)
    UnifiedConfig.set("llm." .. key, value)
    return UnifiedConfig.save()
end

-- Export personalities for external use
LLM.PERSONALITIES = PERSONALITIES

return LLM 