-- test_gemini_format.lua
-- Test script to show exact Gemini request format

local LLM = require("lib.jarvis.llm")

print("===== Gemini Request Format Test =====")
print()

-- Switch to Gemini
LLM.set_provider("gemini")

-- Sample messages like Jarvis would send
local test_messages = {
    {
        role = "system",
        content = "You are jarvis, a helpful assistant."
    },
    {
        role = "user", 
        content = "b0op3r: hiii jarvisss"
    }
}

print("Input messages (OpenAI format):")
for i, msg in ipairs(test_messages) do
    print("  " .. i .. ". " .. msg.role .. ": " .. msg.content)
end

print()
print("Expected Gemini format (after conversion):")
print([[
{
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "System instructions: You are jarvis, a helpful assistant."}]
    },
    {
      "role": "user", 
      "parts": [{"text": "b0op3r: hiii jarvisss"}]
    }
  ],
  "generationConfig": {
    "responseMimeType": "text/plain"
  },
  "tools": [...]
}
]])

print()
print("Suggested config changes:")
print("1. Try model: 'gemini-1.5-flash' (more stable)")
print("2. Or try: 'gemini-1.5-pro'") 
print("3. Make sure your API key is valid")

print()
print("Your current config should use:")
print('config.model = "gemini-1.5-flash"')
print('config.provider = "gemini"')

print()
print("===== Test Complete =====")
print("The provider should now send properly formatted requests!") 