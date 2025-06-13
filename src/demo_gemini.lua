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
print("(Uncomment API key sections to test)")

-- You would need to set up API keys:
-- local openai_key = "your-openai-api-key"
-- local gemini_key = "your-gemini-api-key"

-- OpenAI request:
-- LLM.set_provider("openai")
-- local success, response = LLM.request(openai_key, "gpt-4o", example_messages)

-- Gemini request:
-- LLM.set_provider("gemini")
-- local success, response = LLM.request(gemini_key, "gemini-2.0-flash", example_messages)
--]]

print("===== Demo Complete =====")
print()
print("To switch providers in your code:")
print('LLM.set_provider("openai")   -- Use OpenAI')
print('LLM.set_provider("gemini")   -- Use Gemini')
print()
print("Or edit /etc/jarvis/llm_config.lua to change the default") 