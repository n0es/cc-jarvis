-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}
local debug = require("lib.jarvis.debug")

local API_URL = "https://api.openai.com/v1/responses"

-- Test basic connectivity to OpenAI
function LLM.test_openai_connectivity()
    debug.debug("Testing basic connectivity to api.openai.com...")
    
    -- Try a simpler test - just check if we can resolve the domain
    -- Instead of hitting the root, try a known endpoint that should return a proper error
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    debug.debug("Attempting simple connectivity test...")
    local success, response = http.get("https://api.openai.com/v1/models", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        debug.info("OpenAI API is reachable (got response from /v1/models)")
        return true, "OpenAI API reachable"
    else
        local err_msg = "Cannot reach OpenAI API"
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

-- Convert standard OpenAI messages format to the new input format
local function convert_messages_to_input(messages)
    local input = {}
    
    for _, message in ipairs(messages) do
        local converted_message = {
            role = message.role,
            content = {
                {
                    type = message.role == "assistant" and "output_text" or "input_text",
                    text = message.content
                }
            }
        }
        
        -- Add id for assistant messages (required by the new format)
        if message.role == "assistant" then
            -- Use stored ID if available, otherwise generate a new one
            if message.id then
                converted_message.id = message.id
                debug.debug("Using stored assistant message ID: " .. message.id)
            else
                converted_message.id = "msg_" .. tostring(os.epoch("utc")) .. math.random(100000, 999999)
                debug.debug("Generated new assistant message ID: " .. converted_message.id)
            end
        end
        
        table.insert(input, converted_message)
    end
    
    return input
end

function LLM.request(api_key, model, messages, tools)
    debug.info("Starting LLM request...")
    debug.debug("Target URL: " .. API_URL)
    
    -- Check if HTTP is enabled
    if not http then
        debug.error("HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    debug.debug("HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    debug.debug("API key format: " .. debug.mask_api_key(api_key))
    if not api_key or #api_key <= 8 then
        debug.error("API key appears invalid or too short")
        return false, "Invalid API key format"
    end
    
    debug.debug("Model: " .. tostring(model))
    debug.debug("Messages count: " .. #messages)
    
    -- Use exact same headers as working curl example
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }
    debug.debug("Headers prepared (matching curl format)")

    -- Convert messages to the new input format
    local input = convert_messages_to_input(messages)
    
    -- Build body matching the working curl example
    local body = {
        model = model,
        input = input,
        text = {
            format = {
                type = "text"
            }
        },
        reasoning = {},
        tools = tools or {},
        temperature = 1,
        max_output_tokens = 2048,
        top_p = 1,
        store = true
    }

    debug.debug("Serializing request body...")
    -- Use the same serialization as working GPT.lua example
    local body_json = textutils.serializeJSON(body)
    debug.debug("Used serializeJSON (matching GPT.lua)")
    
    -- Fix the tools field to be an empty array instead of empty object
    body_json = body_json:gsub('"tools":{}', '"tools":[]')
    debug.debug("Fixed tools field to be empty array")
    
    debug.debug("Request body serialized successfully")
    debug.debug("Request size: " .. #body_json .. " bytes")
    
    -- Write comprehensive debug log
    debug.debug("Writing comprehensive debug log...")
    local debug_log = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        tick_time = os.clock(),
        request = {
            url = API_URL,
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
    
    debug.info("Making async HTTP request (matching curl pattern)...")
    
    -- Use exact same pattern as working GPT.lua example
    http.request(API_URL, body_json, headers)
    
    debug.debug("HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling (exact same as GPT.lua)
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
            debug.debug("Used unserializeJSON (matching GPT.lua)")

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
            
            if response_data.error then
                debug.error("API returned error: " .. response_data.error.message)
                local error_msg = "API Error: " .. response_data.error.message
                write_debug_log({
                    error = error_msg,
                    success = false,
                    response = response_data,
                    response_raw = response_body
                })
                return false, error_msg
            end

            debug.info("LLM request completed successfully")
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
        -- (other events might occur that we don't care about)
    end
end

return LLM 