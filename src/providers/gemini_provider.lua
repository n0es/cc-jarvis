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
function GeminiProvider:convert_messages_to_contents(messages)
    local contents = {}
    local system_instruction = nil

    -- First pass to map tool call IDs to function names for Gemini's required format
    local tool_call_id_to_name = {}
    for _, message in ipairs(messages) do
        if message.role == "assistant" and message.tool_calls then
            for _, tool_call in ipairs(message.tool_calls) do
                if tool_call.id and tool_call["function"] and tool_call["function"].name then
                    tool_call_id_to_name[tool_call.id] = tool_call["function"].name
                end
            end
        end
    end

    for _, message in ipairs(messages) do
        if message.role == "system" then
            system_instruction = { parts = { { text = message.content or "" } } }

        elseif message.role == "user" then
            table.insert(contents, {
                role = "user",
                parts = { { text = message.content or "" } }
            })
            
        elseif message.role == "assistant" then
            if message.tool_calls and #message.tool_calls > 0 then
                -- This is a tool-calling turn from the assistant
                local parts = {}
                for _, tool_call in ipairs(message.tool_calls) do
                    if tool_call["function"] then
                        local func = tool_call["function"]
                        local args = textutils.unserializeJSON(func.arguments or "{}") or {}
                        table.insert(parts, {
                            functionCall = {
                                name = func.name,
                                args = args
                            }
                        })
                    end
                end
                if #parts > 0 then
                    table.insert(contents, { role = "model", parts = parts })
                end
            elseif message.content and message.content ~= "" then
                -- This is a standard text response from the assistant
                table.insert(contents, { role = "model", parts = { { text = message.content } } })
            end

        elseif message.role == "tool" then
            local func_name = tool_call_id_to_name[message.tool_call_id]
            if func_name then
                local response_data = textutils.unserializeJSON(message.content or "")
                -- Gemini expects the 'response' to be a JSON object.
                -- If the tool returned a raw string, wrap it in a table.
                if not response_data then
                    response_data = { result = message.content or "empty result" }
                end
                
                table.insert(contents, {
                    role = "tool",
                    parts = {
                        {
                            functionResponse = {
                                name = func_name,
                                response = response_data
                            }
                        }
                    }
                })
            else
                debug.warn("Orphaned tool call response found for ID: " .. tostring(message.tool_call_id))
            end
        end
    end
    
    return contents, system_instruction
end

-- Convert OpenAI tools to Gemini function declarations
function GeminiProvider:convert_tools_to_function_declarations(tools)
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
    local contents, system_instruction = self:convert_messages_to_contents(messages)
    
    -- Build Gemini request body - match Google's format exactly
    local body = {
        contents = contents,
        generationConfig = {
            temperature = 0.2,
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
    local function_declarations = self:convert_tools_to_function_declarations(tools)
    if function_declarations and #function_declarations > 0 then
        body.tools = {
            {
                functionDeclarations = function_declarations
            }
        }
        body.toolConfig = {
            functionCallingConfig = {
                mode = "AUTO" -- AUTO lets the model decide, ANY forces a tool call
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

-- Process Gemini's response, handling multiple parts (text, function calls)
function GeminiProvider:process_response(response_data)
    local results = {}
    
    if not response_data or not response_data.candidates or #response_data.candidates == 0 then
        debug.error("No candidates found in Gemini response")
        table.insert(results, { type = "error", content = "Invalid response from API" })
        return results
    end
    
    local candidate = response_data.candidates[1]
    
    if not candidate.content or not candidate.content.parts or #candidate.content.parts == 0 then
        debug.warn("Candidate content is empty or has no parts")
        if candidate.finishReason == "SAFETY" then
            table.insert(results, { type = "message", content = "I cannot respond to that due to safety settings." })
        else
            table.insert(results, { type = "message", content = "I received an empty response." })
        end
        return results
    end
    
    -- Iterate through all parts of the response
    for _, part in ipairs(candidate.content.parts) do
        if part.text then
            debug.info("Received text part from Gemini")
            table.insert(results, { type = "message", content = part.text })
        end
        
        if part.functionCall then
            debug.info("Received function call part from Gemini: " .. part.functionCall.name)
            local args_json = textutils.serializeJSON(part.functionCall.args or {})
            
            table.insert(results, {
                type = "tool_call",
                tool_name = part.functionCall.name,
                tool_args_json = args_json
            })
        end
    end
    
    return results
end

return GeminiProvider 