-- demo_gemini.lua
-- Demo script showing OpenAI vs Gemini provider usage

local LLM = require("lib.jarvis.llm")

print("===== Gemini Provider Demo =====")
print()

-- Show current state
print("Initial provider: " .. LLM.get_current_provider())
print("Available providers: " .. table.concat(LLM.get_available_providers(), ", "))
print()

-- Test both providers connectivity
print("Testing connectivity:")

-- Test OpenAI
LLM.set_provider("openai")
local success, message = LLM.test_connectivity()
print("OpenAI: " .. (success and "✓" or "✗") .. " " .. message)

-- Test Gemini
LLM.set_provider("gemini")
success, message = LLM.test_connectivity()
print("Gemini: " .. (success and "✓" or "✗") .. " " .. message)

print()

-- Example request formats
print("===== Request Format Comparison =====")
print()
print("OpenAI uses complex input format with role conversion")
print("Gemini uses simple contents format with parts")
print()

-- Example messages
local example_messages = {
    {
        role = "user",
        content = "Hello! Can you explain the difference between these two AI providers?"
    }
}

print("Example request with OpenAI:")
LLM.set_provider("openai")
print("Provider: " .. LLM.get_current_provider())
print("- Uses Bearer token authentication")
print("- Complex message conversion to input format")
print("- Advanced reasoning capabilities")
print()

print("Example request with Gemini:")
LLM.set_provider("gemini")
print("Provider: " .. LLM.get_current_provider())
print("- Uses API key in query parameter")
print("- Simple contents array format")
print("- Fast and efficient responses")
print()

-- Uncomment to make actual requests (requires API keys):
--[[
-- Make requests to both providers
print("===== Live API Comparison =====")

-- Load config to get API keys
local config_file = loadfile("/etc/jarvis/config.lua")
if config_file then
    local config = config_file()
    
    local example_messages = {
        {
            role = "user", 
            content = "Say hello and tell me which AI you are!"
        }
    }

    -- OpenAI request:
    print("Making request to OpenAI...")
    LLM.set_provider("openai")
    local success, response = LLM.request(config.openai_api_key, "gpt-4o", example_messages)
    if success then
        print("✓ OpenAI responded!")
    else
        print("✗ OpenAI failed: " .. tostring(response))
    end

    -- Gemini request:
    print("Making request to Gemini...")
    LLM.set_provider("gemini")
    local success, response = LLM.request(config.gemini_api_key, "gemini-1.5-flash", example_messages)
    if success then
        print("✓ Gemini responded!")
    else
        print("✗ Gemini failed: " .. tostring(response))
    end
else
    print("Could not load config file")
end
--]]

print("===== Demo Complete =====")
print()
print("To switch providers in your code:")
print('LLM.set_provider("openai")   -- Use OpenAI')
print('LLM.set_provider("gemini")   -- Use Gemini')
print()
print("Or edit /etc/jarvis/llm_config.lua to change the default") 