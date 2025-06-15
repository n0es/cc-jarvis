-- debug.lua
-- Debug logging module for structured logging to files and console

local Debug = {}

-- Configuration
local DEBUG_FILE = "debug.log"
local DEBUG_JSON_FILE = "debug_full.json"
local REQUEST_FILE = "debug_request.json"
local RESPONSE_FILE = "debug_response.json"

-- Log levels
local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

-- Current log level (can be changed)
Debug.level = LOG_LEVELS.DEBUG

-- Helper function to get timestamp
local function get_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Helper function to get log level name
local function get_level_name(level)
    for name, value in pairs(LOG_LEVELS) do
        if value == level then
            return name
        end
    end
    return "UNKNOWN"
end

-- Core logging function
local function write_log(level, message, data)
    if level < Debug.level then
        return -- Skip if below current log level
    end
    
    local timestamp = get_timestamp()
    local level_name = get_level_name(level)
    local log_entry = string.format("[%s] [%s] %s", timestamp, level_name, message)
    
    -- Print to console
    print(log_entry)
    
    -- Write to log file
    local file = fs.open(DEBUG_FILE, "a")
    if file then
        file.writeLine(log_entry)
        if data then
            file.writeLine("Data: " .. textutils.serialize(data))
        end
        file.close()
    end
end

-- Public logging functions
function Debug.debug(message, data)
    write_log(LOG_LEVELS.DEBUG, message, data)
end

function Debug.info(message, data)
    write_log(LOG_LEVELS.INFO, message, data)
end

function Debug.warn(message, data)
    write_log(LOG_LEVELS.WARN, message, data)
end

function Debug.error(message, data)
    write_log(LOG_LEVELS.ERROR, message, data)
end

-- Legacy support for existing debug patterns
function Debug.log(message, data)
    Debug.debug(message, data)
end

-- Specialized functions for HTTP debugging
function Debug.write_json_log(data, description)
    description = description or "Debug data"
    Debug.debug("Writing JSON log: " .. description)
    
    local file = fs.open(DEBUG_JSON_FILE, "w")
    if file then
        file.write(textutils.serializeJSON(data))
        file.close()
        Debug.debug("JSON log written to " .. DEBUG_JSON_FILE)
        return true
    else
        Debug.error("Could not write JSON log to " .. DEBUG_JSON_FILE)
        return false
    end
end

function Debug.write_request(request_json)
    Debug.debug("Writing request data")
    
    local file = fs.open(REQUEST_FILE, "w")
    if file then
        file.write(request_json)
        file.close()
        Debug.debug("Request written to " .. REQUEST_FILE)
        return true
    else
        Debug.error("Could not write request to " .. REQUEST_FILE)
        return false
    end
end

function Debug.write_response(response_body)
    Debug.debug("Writing response data (" .. #response_body .. " bytes)")
    
    local file = fs.open(RESPONSE_FILE, "w")
    if file then
        file.write(response_body)
        file.close()
        Debug.debug("Response written to " .. RESPONSE_FILE)
        return true
    else
        Debug.error("Could not write response to " .. RESPONSE_FILE)
        return false
    end
end

-- Function to preview long strings/JSON
function Debug.preview(data, max_length)
    max_length = max_length or 200
    local str = type(data) == "string" and data or textutils.serialize(data)
    if #str > max_length then
        return str:sub(1, max_length) .. "..."
    else
        return str
    end
end

-- API key masking for security
function Debug.mask_api_key(api_key)
    if api_key and #api_key > 8 then
        return api_key:sub(1,4) .. "..." .. api_key:sub(-4)
    else
        return "Invalid or too short"
    end
end

-- Function to get last N lines from a file
local function get_last_lines(filepath, num_lines)
    if not fs.exists(filepath) then
        return "Log file not found at " .. filepath
    end
    
    local file, err = fs.open(filepath, "r")
    if not file then
        return "Could not open log file: " .. tostring(err)
    end
    
    local lines = {}
    for line in file.readAll():gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    file.close()
    
    local start_index = math.max(1, #lines - num_lines + 1)
    local recent_lines = {}
    for i = start_index, #lines do
        table.insert(recent_lines, lines[i])
    end
    
    return table.concat(recent_lines, "\n")
end

-- Get recent log entries
function Debug.get_recent_logs(num_lines)
    num_lines = num_lines or 20
    return get_last_lines(DEBUG_FILE, num_lines)
end

-- Clear all debug files
function Debug.clear_logs()
    local files = {DEBUG_FILE, DEBUG_JSON_FILE, REQUEST_FILE, RESPONSE_FILE}
    for _, filename in ipairs(files) do
        if fs.exists(filename) then
            fs.delete(filename)
            Debug.debug("Cleared " .. filename)
        end
    end
end

-- Set log level
function Debug.set_level(level_name)
    local level = LOG_LEVELS[level_name:upper()]
    if level then
        Debug.level = level
        Debug.info("Log level set to " .. level_name:upper())
    else
        Debug.error("Invalid log level: " .. level_name)
    end
end

return Debug 