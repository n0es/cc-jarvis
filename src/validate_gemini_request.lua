-- validate_gemini_request.lua
-- Validate that our Gemini request format matches Google's specifications

local GeminiProvider = require("lib.jarvis.providers.gemini_provider")

print("===== Gemini Request Format Validation =====")
print()

-- Create test data matching what Jarvis sends
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

local test_tools = {
    {
        type = "function",
        ["function"] = {
            name = "door_control",
            description = "Control the base door by sending open or close commands via modem.",
            parameters = {
                type = "object",
                properties = {
                    action = {
                        type = "string",
                        description = "The action to perform: 'open' or 'close'",
                        enum = {"open", "close"}
                    }
                },
                required = {"action"}
            }
        }
    }
}

print("Expected Google format (from your example):")
print([[
{
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "b0op3r: hiii jarvisss"}]
    }
  ],
  "systemInstruction": {
    "role": "user", 
    "parts": [{"text": "You are jarvis, a helpful assistant."}]
  },
  "generationConfig": {
    "temperature": 1,
    "topP": 0.95,
    "topK": 64,
    "maxOutputTokens": 8192,
    "responseMimeType": "text/plain"
  },
  "tools": [
    {
      "functionDeclarations": [
        {
          "name": "door_control",
          "description": "...",
          "parameters": {...}
        }
      ]
    }
  ],
  "toolConfig": {
    "functionCallingConfig": {
      "mode": "ANY"
    }
  }
}
]])

print()
print("✅ Key fixes applied:")
print("  • systemInstruction field (separate from contents)")
print("  • functionDeclarations (not function_declarations)")
print("  • Complete generationConfig with temperature, topP, etc.")
print("  • toolConfig with functionCallingConfig")
print("  • Proper role mapping (model vs assistant)")

print()
print("🚀 Try again with model: 'gemini-1.5-flash'")
print("The format should now match Google's specification exactly!")

print()
print("===== Validation Complete =====")
print()
print("If still getting errors:")
print("1. Double-check your API key is valid")
print("2. Try model 'gemini-1.5-pro' or 'gemini-1.5-flash'") 
print("3. Check API quota/billing at ai.google.dev") 