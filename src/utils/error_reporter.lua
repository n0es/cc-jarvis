-- error_reporter.lua
-- Generates a comprehensive error report for debugging.

local ErrorReporter = {}
local debug = require("lib.jarvis.debug")
local UnifiedConfig = require("lib.jarvis.config.unified_config")

local REPORT_FILE = "error_report.txt"

-- Gathers system information
local function get_system_info()
    local info = {
        os_version = os.version(),
        computercraft_version = _HOST or "Unknown",
        uptime_seconds = os.clock(),
        peripherals = {}
    }
    pcall(function()
        for _, side in ipairs(rs.getSides()) do
            info.peripherals[side] = peripheral.getType(side)
        end
    end)
    return info
end

-- Formats a section for the report
local function format_section(title, content)
    local lines = {
        "\n=======================================================================",
        "== " .. title,
        "=======================================================================\n\n"
    }
    if type(content) == "table" then
        for k, v in pairs(content) do
            table.insert(lines, string.format("%-20s: %s", tostring(k), tostring(v)))
        end
    elseif type(content) == "string" then
        table.insert(lines, content)
    end
    table.insert(lines, "\n")
    return table.concat(lines, "\n")
end

-- Generates the error report
function ErrorReporter.generate(context)
    context = context or {}
    local error_message = context.error or "No error message provided"
    local stack_trace = context.stack_trace or debug.traceback()
    local app_state = context.app_state or {}

    debug.error("Generating error report for: " .. tostring(error_message))

    -- 1. Version and Timestamp
    local version = UnifiedConfig.get("core.version") or "unknown"
    local build_info = "Jarvis v" .. version
    local report_header = {
        title = "Jarvis AI Assistant - Error Report",
        timestamp_utc = os.date("!%Y-%m-%d %H:%M:%S"),
        version = build_info,
        reason = context.reason or "An unexpected error occurred."
    }

    -- 2. Error Details
    local error_details = string.format("Error: %s\n\nStack Trace:\n%s", tostring(error_message), tostring(stack_trace))

    -- 3. Configuration (masked)
    local masked_config = UnifiedConfig.get_all()
    if masked_config.api then
        if masked_config.api.openai_key then
            masked_config.api.openai_key = debug.mask_api_key(masked_config.api.openai_key)
        end
        if masked_config.api.gemini_key then
            masked_config.api.gemini_key = debug.mask_api_key(masked_config.api.gemini_key)
        end
    end
    local config_text = textutils.serialize(masked_config)

    -- 4. Message History
    local message_history_text
    if app_state.messages and #app_state.messages > 0 then
        local history_lines = {}
        for i, msg in ipairs(app_state.messages) do
            local content_preview = debug.preview(tostring(textutils.serialize(msg.content or "")), 150)
            local role = msg.role or "unknown"
            table.insert(history_lines, string.format("[%d] Role: %-10s Content: %s", i, role, content_preview))
        end
        message_history_text = table.concat(history_lines, "\n")
    else
        message_history_text = "Message history is not available or empty."
    end

    -- 5. Recent Logs
    local recent_logs = debug.get_recent_logs(50) -- Get last 50 log lines

    -- 6. System Info
    local system_info_table = get_system_info()

    -- Assemble the report
    local report_content = {
        format_section("Report Details", report_header),
        format_section("Error Details", error_details),
        format_section("Configuration (Masked)", config_text),
        format_section("Message History", message_history_text),
        format_section("Recent Logs (from debug.log)", recent_logs),
        format_section("System Status", system_info_table)
    }

    -- Write report to file
    local data_dir = UnifiedConfig.get("core.data_dir") or "/etc/jarvis"
    local report_path = data_dir .. "/" .. REPORT_FILE
    local file, err = fs.open(report_path, "w")
    if not file then
        debug.error("Failed to write error report: " .. tostring(err))
        return false, "Failed to write report file."
    end

    file.write(table.concat(report_content))
    file.close()

    local success_message = "An error report has been saved to " .. report_path
    debug.info(success_message)

    return true, success_message
end

return ErrorReporter 