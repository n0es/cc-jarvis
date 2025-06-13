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

return BaseProvider 