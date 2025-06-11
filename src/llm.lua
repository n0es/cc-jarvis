-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/chat/completions"

function LLM.request(api_key, model, messages, tools)
    print("[DEBUG] Starting LLM request...")
    
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
    local body_json = textutils.serialiseJSON(body)
    print("[DEBUG] Request body serialized successfully")
    print("[DEBUG] Request size: " .. #body_json .. " bytes")
    
    -- Show first 200 chars of request for debugging
    print("[DEBUG] Request preview: " .. body_json:sub(1, 200) .. (#body_json > 200 and "..." or ""))
    
    print("[DEBUG] Making HTTP POST request to: " .. API_URL)
    local success, response = http.post(API_URL, body_json, headers)
    print("[DEBUG] HTTP request completed. Success: " .. tostring(success))

    if not success then
        print("[DEBUG] HTTP request failed")
        local err_msg = "HTTP request failed."
        if response then
            print("[DEBUG] Response type: " .. type(response))
            if type(response) == "string" then
                print("[DEBUG] Error response: " .. response)
                err_msg = err_msg .. " Error: " .. response
            elseif response.readAll then
                local error_body = response.readAll()
                print("[DEBUG] Error response body: " .. error_body)
                err_msg = err_msg .. " Response: " .. error_body
                response.close()
            else
                print("[DEBUG] Response object has no readAll method")
            end
        else
            print("[DEBUG] No response object returned")
            err_msg = err_msg .. " No response received. Check internet connection and HTTP settings."
        end
        return false, err_msg
    end

    print("[DEBUG] HTTP request successful, reading response...")
    local response_body = response.readAll()
    response.close()
    print("[DEBUG] Response received: " .. #response_body .. " bytes")
    
    -- Show first 200 chars of response for debugging
    print("[DEBUG] Response preview: " .. response_body:sub(1, 200) .. (#response_body > 200 and "..." or ""))
    
    print("[DEBUG] Parsing JSON response...")
    local response_data = textutils.unserialiseJSON(response_body)

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
end

return LLM 