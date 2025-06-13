-- gemini_provider.lua
-- Google Gemini API provider implementation

local BaseProvider = require("lib.jarvis.providers.base_provider")
local debug = require("lib.jarvis.debug")

local GeminiProvider = setmetatable({}, {__index = BaseProvider})
GeminiProvider.__index = GeminiProvider

local API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

function GeminiProvider.new()
    local self = setmetatable(BaseProvider.new(), GeminiProvider)
    return self
end

function GeminiProvider:get_name()
    return "gemini"
end

-- Test basic connectivity to Gemini API
function GeminiProvider:test_connectivity()
    debug.debug("Testing basic connectivity to Gemini API...")
    
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    debug.debug("Attempting simple connectivity test...")
    -- Test with a simple models list endpoint (doesn't require API key for basic connectivity)
    local success, response = http.get("https://generativelanguage.googleapis.com", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        debug.info("Gemini API is reachable")
        return true, "Gemini API reachable"
    else
        local err_msg = "Cannot reach Gemini API"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
                debug.error("Error: " .. response)
            end
        end
        debug.error(err_msg)
        return false, err_msg
    end
end

-- Convert OpenAI-style messages to Gemini contents format
local function convert_messages_to_contents(messages)
    local contents = {}
    local system_instruction = nil
    
    for _, message in ipairs(messages) do
        if message.role == "system" then
            -- Extract system instruction separately
            system_instruction = {
                parts = {
                    {
                        text = message.content or ""
                    }
                }
            }
        elseif message.role == "user" then
            table.insert(contents, {
                role = "user",
                parts = {
                    {
                        text = message.content or ""
                    }
                }
            })
        elseif message.role == "assistant" then
            table.insert(contents, {
                role = "model",  -- Gemini uses "model" instead of "assistant"
                parts = {
                    {
                        text = message.content or ""
                    }
                }
            })
        elseif message.role == "tool" then
            -- Tool results - add as user message
            table.insert(contents, {
                role = "user",
                parts = {
                    {
                        text = "Tool result: " .. (message.content or "No result")
                    }
                }
            })
        end
    end
    
    return contents, system_instruction
end

-- Convert OpenAI tools to Gemini function declarations
local function convert_tools_to_function_declarations(tools)
    if not tools or #tools == 0 then
        return nil
    end

    local function_declarations = {}

    for _, tool_schema in ipairs(tools) do
        -- The schema from tools.lua is already in the format Gemini expects for a function declaration.
        if tool_schema.type == "function" and tool_schema.name then
            -- Ensure parameters are correctly formatted for Gemini API
            local parameters = tool_schema.parameters or { type = "object", properties = {} }
            if parameters.required and #parameters.required == 0 then
                parameters.required = nil -- Omit 'required' field if it's empty
            end
            
            -- Manually build the FunctionDeclaration to ensure only valid fields are included.
            -- The Gemini API is strict and rejects unknown fields like "type" or "strict".
            local declaration = {
                name = tool_schema.name,
                description = tool_schema.description,
                parameters = parameters
            }
            table.insert(function_declarations, declaration)
        end
    end

    if #function_declarations == 0 then
        return nil
    end

    return function_declarations
end

function GeminiProvider:request(api_key, model, messages, tools)
    debug.info("Starting Gemini request...")
    
    -- Validate parameters
    local valid, err = self:validate_request(api_key, model, messages)
    if not valid then
        return false, err
    end
    
    -- Check if HTTP is enabled
    if not http then
        debug.error("HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    debug.debug("HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    debug.debug("API key format: " .. debug.mask_api_key(api_key))
    
    debug.debug("Model: " .. tostring(model))
    debug.debug("Messages count: " .. #messages)
    
    -- Build Gemini API URL with API key as query parameter
    local api_url = API_BASE_URL .. "/" .. model .. ":generateContent?key=" .. api_key
    debug.debug("Target URL: " .. api_url:gsub(api_key, "***"))
    
    -- Gemini uses simple headers
    local headers = {
        ["Content-Type"] = "application/json"
    }
    debug.debug("Headers prepared")

    -- Convert messages to Gemini contents format
    local contents, system_instruction = convert_messages_to_contents(messages)
    
    -- Build Gemini request body - match Google's format exactly
    local body = {
        contents = contents,
        generationConfig = {
            temperature = 1,
            topP = 0.95,
            topK = 64,
            maxOutputTokens = 8192
        }
    }
    
    -- Add system instruction if present
    if system_instruction then
        body.systemInstruction = system_instruction
    end
    
    -- Add function calling support if tools are provided
    local function_declarations = convert_tools_to_function_declarations(tools)
    if function_declarations and #function_declarations > 0 then
        body.tools = {
            {
                functionDeclarations = function_declarations
            }
        }
        body.toolConfig = {
            functionCallingConfig = {
                mode = "ANY"
            }
        }
        debug.debug("Added " .. #function_declarations .. " function declarations")
    else
        debug.debug("No tools provided or conversion failed")
    end

    debug.debug("Serializing request body...")
    local body_json = textutils.serializeJSON(body)
    debug.debug("Request body serialized successfully")
    debug.debug("Request size: " .. #body_json .. " bytes")
    
    -- Write comprehensive debug log
    debug.debug("Writing comprehensive debug log...")
    local debug_log = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        tick_time = os.clock(),
        provider = "gemini",
        request = {
            url = api_url:gsub(api_key, "***"), -- Mask API key in logs
            headers = headers,
            body_raw = body,
            body_json = body_json,
            message_count = #messages,
            messages = messages
        },
        response = nil,
        error = nil,
        success = false
    }
    
    local function write_debug_log(additional_data)
        if additional_data then
            for k, v in pairs(additional_data) do
                debug_log[k] = v
            end
        end
        debug.write_json_log(debug_log, "Full HTTP request/response debug data")
    end
    
    -- Write initial debug state
    write_debug_log()
    
    -- Also write the formatted JSON request separately for easy copying
    debug.write_request(body_json)
    
    -- Validate JSON before sending
    if not body_json or body_json == "" then
        debug.error("Failed to serialize request body to JSON")
        return false, "Failed to serialize request body to JSON"
    end
    
    -- Show first 200 chars of request for debugging
    debug.debug("Request preview: " .. debug.preview(body_json))
    
    debug.info("Making async HTTP request to Gemini API...")
    
    -- Make the request
    http.request(api_url, body_json, headers)
    
    debug.debug("HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling
    while true do
        local event, url, handle = os.pullEvent()
        
        if event == "http_success" then
            debug.info("HTTP request successful, reading response...")
            local response_body = handle.readAll()
            handle.close()
            debug.debug("Response received: " .. #response_body .. " bytes")
            
            -- Write the response to separate file for easy copying
            debug.write_response(response_body)
            
            -- Show first 200 chars of response for debugging
            debug.debug("Response preview: " .. debug.preview(response_body))
            
            debug.debug("Parsing JSON response...")
            local response_data = textutils.unserializeJSON(response_body)

            if not response_data then
                debug.error("Failed to parse JSON response")
                local error_msg = "Failed to decode JSON response from API: " .. tostring(response_body)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response_raw = response_body
                })
                return false, error_msg
            end
            debug.debug("JSON response parsed successfully")
            
            -- Check for API errors
            if response_data.error then
                debug.error("Gemini API returned error: " .. tostring(response_data.error.message or response_data.error))
                local error_msg = "Gemini API Error: " .. tostring(response_data.error.message or response_data.error)
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response = response_data,
                    response_raw = response_body
                })
                return false, error_msg
            end

            debug.info("Gemini request completed successfully")
            write_debug_log({
                success = true,
                response = response_data,
                response_raw = response_body
            })
            return true, response_data
            
        elseif event == "http_failure" then
            debug.error("HTTP request failed with http_failure event")
            local error_msg = "HTTP request failed (http_failure event)"
            if handle then
                if type(handle) == "string" then
                    error_msg = error_msg .. ": " .. handle
                    debug.error("Error details: " .. handle)
                end
            end
            write_debug_log({
                error = error_msg,
                success = false,
                http_failure_details = handle
            })
            return false, error_msg
        end
        
        -- Continue waiting for our specific request response
    end
end

return GeminiProvider 