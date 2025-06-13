-- base_provider.lua
-- Base interface for LLM providers

local BaseProvider = {}
BaseProvider.__index = BaseProvider

function BaseProvider.new()
    local self = setmetatable({}, BaseProvider)
    return self
end

-- Test connectivity to the provider's API
-- Returns: success (boolean), message (string)
function BaseProvider:test_connectivity()
    error("test_connectivity must be implemented by provider")
end

-- Make a request to the provider's API
-- Parameters:
--   api_key: API key for authentication
--   model: Model name/identifier
--   messages: Array of message objects with role and content
--   tools: Optional array of tool definitions
-- Returns: success (boolean), response_data (table) or error_message (string)
function BaseProvider:request(api_key, model, messages, tools)
    error("request must be implemented by provider")
end

-- Get the provider name for logging/debugging
function BaseProvider:get_name()
    return "base"
end

-- Validate that required parameters are present
function BaseProvider:validate_request(api_key, model, messages)
    if not api_key or #api_key == 0 then
        return false, "API key is required"
    end
    
    if not model or #model == 0 then
        return false, "Model is required"
    end
    
    if not messages or #messages == 0 then
        return false, "Messages are required"
    end
    
    return true, nil
end

-- Default implementation for processing a response.
-- This can be overridden by specific providers for custom handling.
function BaseProvider:process_response(response_data)
    local results = {}
    
    -- OpenAI-specific logic (default)
    if response_data and response_data.choices and #response_data.choices > 0 then
        local choice = response_data.choices[1]
        if choice.message then
            if choice.message.content then
                table.insert(results, { type = "message", content = choice.message.content })
            end
            if choice.message.tool_calls and #choice.message.tool_calls > 0 then
                for _, tool_call in ipairs(choice.message.tool_calls) do
                    if tool_call.type == "function" then
                        table.insert(results, {
                            type = "tool_call",
                            tool_name = tool_call["function"].name,
                            tool_args_json = tool_call["function"].arguments
                        })
                    end
                end
            end
        end
    else
        debug.error("Invalid or empty response structure from LLM")
        table.insert(results, { type = "error", content = "Invalid response from API" })
    end
    
    return results
end

return BaseProvider 