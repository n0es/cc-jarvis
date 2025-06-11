-- llm.lua
-- Handles communication with the OpenAI API.

local LLM = {}

local API_URL = "https://api.openai.com/v1/chat/completions"

function LLM.request(api_key, model, messages, tools)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
    }

    local body = {
        model = model,
        messages = messages,
    }

    if tools and #tools > 0 then
        body.tools = tools
        body.tool_choice = "auto"
    end

    local body_json = textutils.serialiseJSON(body)

    local success, response = http.post(API_URL, body_json, headers)

    if not success then
        local err_msg = "HTTP request failed."
        if response and response.readAll then
            err_msg = err_msg .. " Response: " .. response.readAll()
            response.close()
        end
        return false, err_msg
    end

    local response_body = response.readAll()
    response.close()
    local response_data = textutils.unserialiseJSON(response_body)

    if not response_data then
        return false, "Failed to decode JSON response from API: " .. tostring(response_body)
    end
    
    if response_data.error then
        return false, "API Error: " .. response_data.error.message
    end

    return true, response_data
end

return LLM 