-- input_validator.lua
-- Comprehensive input validation module for Jarvis
-- Provides standardized validation for all user inputs and API parameters

local InputValidator = {}
local debug = require("lib.jarvis.debug")

-- Validation error class
local ValidationError = {}
ValidationError.__index = ValidationError

function ValidationError.new(message, field, value)
    local self = setmetatable({}, ValidationError)
    self.message = message
    self.field = field
    self.value = value
    self.timestamp = os.time()
    return self
end

function ValidationError:__tostring()
    return string.format("ValidationError: %s (field: %s, value: %s)", 
        self.message, self.field or "unknown", tostring(self.value))
end

-- Validation rule types
local RULE_TYPES = {
    required = "required",
    type = "type",
    min = "min",
    max = "max",
    min_length = "min_length",
    max_length = "max_length",
    pattern = "pattern",
    enum = "enum",
    custom = "custom"
}

-- Built-in validation patterns
local PATTERNS = {
    api_key = "^[a-zA-Z0-9_%-]+$",
    bot_name = "^[a-zA-Z0-9_%-]+$",
    model_name = "^[a-zA-Z0-9_%-%.]+$",
    channel = "^[0-9]+$",
    personality = "^[a-zA-Z_]+$"
}

-- Sanitization functions
local SANITIZERS = {
    trim = function(value)
        if type(value) == "string" then
            return value:match("^%s*(.-)%s*$")
        end
        return value
    end,
    
    lowercase = function(value)
        if type(value) == "string" then
            return value:lower()
        end
        return value
    end,
    
    alphanumeric_only = function(value)
        if type(value) == "string" then
            return value:gsub("[^%w_%-]", "")
        end
        return value
    end,
    
    escape_quotes = function(value)
        if type(value) == "string" then
            return value:gsub('"', '\\"'):gsub("'", "\\'")
        end
        return value
    end
}

-- Core validation functions
local function validate_required(value, rule)
    if value == nil or value == "" then
        return false, "Value is required"
    end
    return true
end

local function validate_type(value, rule)
    if value == nil then
        return true -- Type validation only applies to non-nil values
    end
    
    local expected_type = rule.type
    local actual_type = type(value)
    
    if actual_type ~= expected_type then
        return false, string.format("Expected %s, got %s", expected_type, actual_type)
    end
    
    return true
end

local function validate_min(value, rule)
    if value == nil then return true end
    
    if type(value) == "number" then
        if value < rule.min then
            return false, string.format("Value must be at least %s", rule.min)
        end
    elseif type(value) == "string" then
        if #value < rule.min then
            return false, string.format("Length must be at least %s", rule.min)
        end
    end
    
    return true
end

local function validate_max(value, rule)
    if value == nil then return true end
    
    if type(value) == "number" then
        if value > rule.max then
            return false, string.format("Value must be at most %s", rule.max)
        end
    elseif type(value) == "string" then
        if #value > rule.max then
            return false, string.format("Length must be at most %s", rule.max)
        end
    end
    
    return true
end

local function validate_min_length(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        if #value < rule.min_length then
            return false, string.format("Length must be at least %s characters", rule.min_length)
        end
    end
    
    return true
end

local function validate_max_length(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        if #value > rule.max_length then
            return false, string.format("Length must be at most %s characters", rule.max_length)
        end
    end
    
    return true
end

local function validate_pattern(value, rule)
    if value == nil then return true end
    
    if type(value) == "string" then
        local pattern = rule.pattern
        if type(pattern) == "string" and PATTERNS[pattern] then
            pattern = PATTERNS[pattern]
        end
        
        if not value:match(pattern) then
            return false, "Value does not match required pattern"
        end
    end
    
    return true
end

local function validate_enum(value, rule)
    if value == nil then return true end
    
    local found = false
    for _, enum_value in ipairs(rule.enum) do
        if value == enum_value then
            found = true
            break
        end
    end
    
    if not found then
        return false, string.format("Value must be one of: %s", table.concat(rule.enum, ", "))
    end
    
    return true
end

local function validate_custom(value, rule)
    if value == nil then return true end
    
    if type(rule.custom) == "function" then
        local success, result = pcall(rule.custom, value)
        if not success then
            return false, "Custom validation function failed: " .. tostring(result)
        end
        
        if result == false then
            return false, "Custom validation failed"
        elseif type(result) == "string" then
            return false, result
        end
    end
    
    return true
end

-- Map rule types to validation functions
local VALIDATORS = {
    [RULE_TYPES.required] = validate_required,
    [RULE_TYPES.type] = validate_type,
    [RULE_TYPES.min] = validate_min,
    [RULE_TYPES.max] = validate_max,
    [RULE_TYPES.min_length] = validate_min_length,
    [RULE_TYPES.max_length] = validate_max_length,
    [RULE_TYPES.pattern] = validate_pattern,
    [RULE_TYPES.enum] = validate_enum,
    [RULE_TYPES.custom] = validate_custom
}

-- Validate a single value against a rule set
function InputValidator.validate_value(value, rules, field_name)
    field_name = field_name or "unknown"
    
    if type(rules) ~= "table" then
        return false, ValidationError.new("Invalid rules specification", field_name, value)
    end
    
    -- Apply sanitization if specified
    if rules.sanitize then
        for _, sanitizer_name in ipairs(rules.sanitize) do
            local sanitizer = SANITIZERS[sanitizer_name]
            if sanitizer then
                value = sanitizer(value)
            else
                debug.warn("Unknown sanitizer: " .. sanitizer_name)
            end
        end
    end
    
    -- Apply validation rules in order
    for rule_type, rule_value in pairs(rules) do
        if VALIDATORS[rule_type] then
            local rule_config = {[rule_type] = rule_value}
            local valid, error_msg = VALIDATORS[rule_type](value, rule_config)
            
            if not valid then
                return false, ValidationError.new(error_msg, field_name, value)
            end
        end
    end
    
    return true, value -- Return sanitized value
end

-- Validate an object against a schema
function InputValidator.validate_object(object, schema)
    if type(object) ~= "table" then
        return false, ValidationError.new("Object must be a table", "root", object)
    end
    
    if type(schema) ~= "table" then
        return false, ValidationError.new("Schema must be a table", "root", schema)
    end
    
    local validated_object = {}
    local errors = {}
    
    -- Validate each field in the schema
    for field_name, field_rules in pairs(schema) do
        if field_name ~= "_strict" then
            local field_value = object[field_name]
            local valid, result = InputValidator.validate_value(field_value, field_rules, field_name)
            
            if valid then
                validated_object[field_name] = result
            else
                table.insert(errors, result)
            end
        end
    end
    
    -- Check for unexpected fields if strict mode is enabled
    if schema._strict then
        for field_name, field_value in pairs(object) do
            if not schema[field_name] and field_name ~= "_strict" then
                table.insert(errors, ValidationError.new(
                    "Unexpected field in strict mode", 
                    field_name, 
                    field_value
                ))
            end
        end
    end
    
    if #errors > 0 then
        return false, errors
    end
    
    return true, validated_object
end

-- Validate tool arguments
function InputValidator.validate_tool_args(tool_name, args, tool_schema)
    if not tool_schema or not tool_schema.parameters then
        return true, args -- No validation schema available
    end
    
    local schema = {}
    local parameters = tool_schema.parameters
    
    -- Convert tool schema to validation schema
    if parameters.properties then
        for prop_name, prop_def in pairs(parameters.properties) do
            local rules = {}
            
            -- Add type validation
            if prop_def.type then
                rules.type = prop_def.type
            end
            
            -- Add enum validation
            if prop_def.enum then
                rules.enum = prop_def.enum
            end
            
            -- Add required validation
            if parameters.required and type(parameters.required) == "table" then
                for _, required_field in ipairs(parameters.required) do
                    if required_field == prop_name then
                        rules.required = true
                        break
                    end
                end
            end
            
            schema[prop_name] = rules
        end
    end
    
    -- Add strict mode if tool schema specifies it
    if tool_schema.strict then
        schema._strict = true
    end
    
    local valid, result = InputValidator.validate_object(args, schema)
    
    if not valid then
        local error_msg = string.format("Tool %s validation failed", tool_name)
        if type(result) == "table" then
            local error_messages = {}
            for _, error in ipairs(result) do
                table.insert(error_messages, tostring(error))
            end
            error_msg = error_msg .. ": " .. table.concat(error_messages, "; ")
        end
        return false, error_msg
    end
    
    return true, result
end

-- Validate API key format
function InputValidator.validate_api_key(api_key, provider)
    local rules = {
        required = true,
        type = "string",
        min_length = 8,
        max_length = 256, -- Increased max length
        sanitize = {"trim"}
    }
    
    -- Provider-specific validation
    if provider == "openai" then
        rules.min_length = 20
        -- Allows for 'sk-' and 'sk-proj-' prefixes with various characters
        rules.pattern = "^sk-(proj-)?[a-zA-Z0-9_-]+$"
    elseif provider == "gemini" then
        rules.min_length = 30
        -- Allows for 'AIzaSy' prefix
        rules.pattern = "^AIzaSy[a-zA-Z0-9_-]+$"
    else
        -- Generic pattern for other potential providers
        rules.pattern = "^[a-zA-Z0-9_.-]+$"
    end
    
    return InputValidator.validate_value(api_key, rules, "api_key")
end

-- Validate bot name
function InputValidator.validate_bot_name(bot_name)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 32,
        pattern = "bot_name",
        sanitize = {"trim", "lowercase", "alphanumeric_only"}
    }
    
    return InputValidator.validate_value(bot_name, rules, "bot_name")
end

-- Validate model name
function InputValidator.validate_model_name(model_name)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 100,
        pattern = "model_name",
        sanitize = {"trim"}
    }
    
    return InputValidator.validate_value(model_name, rules, "model_name")
end

-- Validate personality type
function InputValidator.validate_personality(personality)
    local rules = {
        required = true,
        type = "string",
        enum = {"jarvis", "all_might"},
        sanitize = {"trim", "lowercase"}
    }
    
    return InputValidator.validate_value(personality, rules, "personality")
end

-- Validate chat message
function InputValidator.validate_chat_message(message)
    local rules = {
        required = true,
        type = "string",
        min_length = 1,
        max_length = 2000,
        sanitize = {"trim", "escape_quotes"}
    }
    
    return InputValidator.validate_value(message, rules, "chat_message")
end

-- Common validation schemas
InputValidator.SCHEMAS = {
    tool_args = {
        action = {
            type = "string",
            required = true,
            enum = {"open", "close"},
            sanitize = {"trim", "lowercase"}
        },
        new_name = {
            type = "string",
            required = true,
            min_length = 1,
            max_length = 32,
            pattern = "bot_name",
            sanitize = {"trim", "lowercase", "alphanumeric_only"}
        },
        personality = {
            type = "string",
            required = true,
            enum = {"jarvis", "all_might"},
            sanitize = {"trim", "lowercase"}
        }
    }
}

-- Export validation error class
InputValidator.ValidationError = ValidationError

return InputValidator