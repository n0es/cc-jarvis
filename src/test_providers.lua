-- test_providers.lua
-- Test script for the LLM provider abstraction system

local LLM = require("llm")

print("===== LLM Provider System Test =====")
print()

-- Show current configuration
print("Current LLM Configuration:")
print("Config file: /etc/jarvis/llm_config.lua")
LLM.print_config()
print()

-- Show available providers
print("Available providers:")
local providers = LLM.get_available_providers()
for i, provider in ipairs(providers) do
    print("  " .. i .. ". " .. provider)
end
print()

-- Test connectivity with current provider
print("Testing connectivity with current provider...")
local success, message = LLM.test_connectivity()
if success then
    print("✓ " .. message)
else
    print("✗ " .. message)
end
print()

-- Example of switching providers (when Gemini is added)
print("Current provider: " .. LLM.get_current_provider())

-- Uncomment when Gemini provider is added:
--[[ 
print("Switching to Gemini provider...")
local switch_success, switch_message = LLM.set_provider("gemini")
if switch_success then
    print("✓ " .. switch_message)
    print("New provider: " .. LLM.get_current_provider())
    
    -- Test connectivity with new provider
    print("Testing connectivity with Gemini...")
    local gemini_success, gemini_message = LLM.test_connectivity()
    if gemini_success then
        print("✓ " .. gemini_message)
    else
        print("✗ " .. gemini_message)
    end
else
    print("✗ " .. switch_message)
end

print()
print("Switching back to OpenAI...")
LLM.set_provider("openai")
print("Current provider: " .. LLM.get_current_provider())
--]]

print()
print("===== Provider System Test Complete =====")

-- Example of making a request (you'll need to provide your API key)
--[[
print()
print("Example request (replace with your API key):")
local api_key = "your-api-key-here"
local model = "gpt-4"
local messages = {
    {
        role = "user",
        content = "Hello, this is a test message!"
    }
}

local req_success, response = LLM.request(api_key, model, messages)
if req_success then
    print("✓ Request successful!")
    -- Print relevant parts of response
else
    print("✗ Request failed: " .. tostring(response))
end
--]] 