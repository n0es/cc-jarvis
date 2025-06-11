-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/responses"

-- Test basic connectivity to OpenAI
function LLM.test_openai_connectivity()
    print("[DEBUG] Testing basic connectivity to api.openai.com...")
    
    -- Try a simpler test - just check if we can resolve the domain
    -- Instead of hitting the root, try a known endpoint that should return a proper error
    local test_headers = {
        ["User-Agent"] = "ComputerCraft",
    }
    
    print("[DEBUG] Attempting simple connectivity test...")
    local success, response = http.get("https://api.openai.com/v1/models", test_headers)
    
    if success then
        local body = response.readAll()
        response.close()
        print("[DEBUG] OpenAI API is reachable (got response from /v1/models)")
        return true, "OpenAI API reachable"
    else
        local err_msg = "Cannot reach OpenAI API"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
                print("[DEBUG] Error: " .. response)
            end
        end
        print("[DEBUG] " .. err_msg)
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
            converted_message.id = "msg_" .. tostring(os.epoch("utc")) .. math.random(100000, 999999)
        end
        
        table.insert(input, converted_message)
    end
    
    return input
end

function LLM.request(api_key, model, messages, tools)
    print("[DEBUG] Starting LLM request...")
    print("[DEBUG] Target URL: " .. API_URL)
    
    -- Check if HTTP is enabled
    if not http then
        print("[DEBUG] HTTP API not available")
        return false, "HTTP API is not available. Ensure 'http_enable' is set to true in computercraft-common.toml"
    end
    print("[DEBUG] HTTP API is available")
    
    -- Debug API key (show first/last 4 chars only for security)
    if api_key and #api_key > 8 then
        print("[DEBUG] API key format: " .. api_key:sub(1,4) .. "..." .. api_key:sub(-4))
    else
        print("[DEBUG] API key appears invalid or too short")
        return false, "Invalid API key format"
    end
    
    print("[DEBUG] Model: " .. tostring(model))
    print("[DEBUG] Messages count: " .. #messages)
    
    -- Use exact same headers as working curl example
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }
    print("[DEBUG] Headers prepared (matching curl format)")

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
    
    -- Ensure tools is an empty array, not an empty object (fixes bad request)
    if not tools or #tools == 0 then
        -- Create a proper empty array structure
        body.tools = {}
        -- Add a dummy element and remove it to force array serialization
        table.insert(body.tools, "dummy")
        table.remove(body.tools, 1)
    end

    print("[DEBUG] Serializing request body...")
    -- Use the same serialization as working GPT.lua example
    local body_json = textutils.serializeJSON(body)
    print("[DEBUG] Used serializeJSON (matching GPT.lua)")
    
    print("[DEBUG] Request body serialized successfully")
    print("[DEBUG] Request size: " .. #body_json .. " bytes")
    
    -- Write the full request to a file for debugging
    print("[DEBUG] Writing request to debug_request.json for inspection...")
    local debug_file = fs.open("debug_request.json", "w")
    if debug_file then
        debug_file.write(body_json)
        debug_file.close()
        print("[DEBUG] Request written to debug_request.json - you can copy this to compare with working curl")
    else
        print("[DEBUG] Warning: Could not write debug file")
    end
    
    -- Validate JSON before sending
    if not body_json or body_json == "" then
        return false, "Failed to serialize request body to JSON"
    end
    
    -- Show first 200 chars of request for debugging
    print("[DEBUG] Request preview: " .. body_json:sub(1, 200) .. (#body_json > 200 and "..." or ""))
    
    print("[DEBUG] Making async HTTP request (matching curl pattern)...")
    
    -- Use exact same pattern as working GPT.lua example
    http.request(API_URL, body_json, headers)
    
    print("[DEBUG] HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling (exact same as GPT.lua)
    while true do
        local event, url, handle = os.pullEvent()
        
        if event == "http_success" then
            print("[DEBUG] HTTP request successful, reading response...")
            local response_body = handle.readAll()
            handle.close()
            print("[DEBUG] Response received: " .. #response_body .. " bytes")
            
            -- Show first 200 chars of response for debugging
            print("[DEBUG] Response preview: " .. response_body:sub(1, 200) .. (#response_body > 200 and "..." or ""))
            
            print("[DEBUG] Parsing JSON response...")
            local response_data = textutils.unserializeJSON(response_body)
            print("[DEBUG] Used unserializeJSON (matching GPT.lua)")

            if not response_data then
                print("[DEBUG] Failed to parse JSON response")
                return false, "Failed to decode JSON response from API: " .. tostring(response_body)
            end
            print("[DEBUG] JSON response parsed successfully")
            
            if response_data.error then
                print("[DEBUG] API returned error: " .. response_data.error.message)
                return false, "API Error: " .. response_data.error.message
            end

            print("[DEBUG] LLM request completed successfully")
            return true, response_data
            
        elseif event == "http_failure" then
            print("[DEBUG] HTTP request failed with http_failure event")
            local error_msg = "HTTP request failed (http_failure event)"
            if handle then
                if type(handle) == "string" then
                    error_msg = error_msg .. ": " .. handle
                    print("[DEBUG] Error details: " .. handle)
                end
            end
            return false, error_msg
        end
        
        -- Continue waiting for our specific request response
        -- (other events might occur that we don't care about)
    end
end

return LLM 