-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/chat/completions"

-- Test basic connectivity to OpenAI
function LLM.test_openai_connectivity()
    print("[DEBUG] Testing basic connectivity to api.openai.com...")
    
    -- Try a simple GET request to OpenAI (this will return 404, but that's expected)
    local success, response = http.get("https://api.openai.com/")
    
    if success then
        local body = response.readAll()
        response.close()
        print("[DEBUG] OpenAI domain is reachable (got response)")
        return true, "OpenAI domain reachable"
    else
        local err_msg = "Cannot reach OpenAI domain"
        if response then
            if type(response) == "string" then
                err_msg = err_msg .. ": " .. response
            end
        end
        print("[DEBUG] " .. err_msg)
        return false, err_msg
    end
end

function LLM.request(api_key, model, messages, tools)
    print("[DEBUG] Starting LLM request...")
    print("[DEBUG] Target URL: " .. API_URL)
    
    -- Test connectivity first
    local conn_ok, conn_msg = LLM.test_openai_connectivity()
    if not conn_ok then
        return false, "Connectivity test failed: " .. conn_msg
    end
    
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
    end
    
    print("[DEBUG] Model: " .. tostring(model))
    print("[DEBUG] Messages count: " .. #messages)
    print("[DEBUG] Tools count: " .. (tools and #tools or 0))
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
    }
    print("[DEBUG] Headers prepared")

    local body = {
        model = model,
        messages = messages,
    }

    if tools and #tools > 0 then
        body.tools = tools
        body.tool_choice = "auto"
        print("[DEBUG] Tools added to request")
    end

    print("[DEBUG] Serializing request body...")
    -- Try both spellings of serialize in case one works better
    local body_json
    if textutils.serializeJSON then
        body_json = textutils.serializeJSON(body)
        print("[DEBUG] Used serializeJSON (American spelling)")
    else
        body_json = textutils.serialiseJSON(body)
        print("[DEBUG] Used serialiseJSON (British spelling)")
    end
    
    print("[DEBUG] Request body serialized successfully")
    print("[DEBUG] Request size: " .. #body_json .. " bytes")
    
    -- Show first 200 chars of request for debugging
    print("[DEBUG] Request preview: " .. body_json:sub(1, 200) .. (#body_json > 200 and "..." or ""))
    
    print("[DEBUG] Making async HTTP request to: " .. API_URL)
    
    -- Use async http.request like the working GPT.lua example
    http.request(API_URL, body_json, headers)
    
    print("[DEBUG] HTTP request sent, waiting for response...")
    
    -- Wait for the response using event handling
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
            local response_data
            if textutils.unserializeJSON then
                response_data = textutils.unserializeJSON(response_body)
                print("[DEBUG] Used unserializeJSON (American spelling)")
            else
                response_data = textutils.unserialiseJSON(response_body)
                print("[DEBUG] Used unserialiseJSON (British spelling)")
            end

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