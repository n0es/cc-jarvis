-- debug_api_keys.lua
-- Debug script to check API key selection and provider detection

local LLM = require("lib.jarvis.llm")

print("===== API Key Selection Debug =====")
print()

-- Load main config
local config_file = loadfile("/etc/jarvis/config.lua")
if config_file then
    local config = config_file()
    print("Main Config (/etc/jarvis/config.lua):")
    print("  OpenAI key: " .. (config.openai_api_key and (config.openai_api_key:sub(1,8) .. "...") or "NOT SET"))
    print("  Gemini key: " .. (config.gemini_api_key and (config.gemini_api_key:sub(1,8) .. "...") or "NOT SET"))
    print("  Model: " .. (config.model or "NOT SET"))
else
    print("❌ Could not load main config!")
end

print()

-- Check LLM config
print("LLM Config (/etc/jarvis/llm_config.lua):")
print("  Current provider: " .. LLM.get_current_provider())
print("  Available providers: " .. table.concat(LLM.get_available_providers(), ", "))

print()

-- Test provider switching
print("Testing provider switching:")

LLM.set_provider("openai")
print("  Set to OpenAI - Current: " .. LLM.get_current_provider())

LLM.set_provider("gemini")  
print("  Set to Gemini - Current: " .. LLM.get_current_provider())

print()

-- Check if the issue is in main.lua's helper function
print("The issue might be in main.lua's get_api_key_for_provider() function")
print("Check that it's correctly reading the current provider and selecting the right key")

print()
print("===== Debug Complete =====")
print()
print("Next steps:")
print("1. Make sure your main config is saved properly")
print("2. Restart Jarvis to reload configs")
print("3. If still broken, the helper function in main.lua needs fixing") 