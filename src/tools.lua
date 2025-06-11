-- tools.lua
-- Defines the functions that the LLM can call.

local Tools = {}

-- A registry to hold the function definitions and their callable implementations.
local registry = {}

-- Tool Definition: get_time
-- This function gets the current in-game time.
function Tools.get_time()
    return { time = textutils.formatTime(os.time("ingame"), false) }
end

-- Register the get_time tool with its implementation and schema for the LLM.
registry.get_time = {
    func = Tools.get_time,
    schema = {
        type = "function",
        ["function"] = {
            name = "get_time",
            description = "Get the current in-game time.",
            parameters = {
                type = "object",
                properties = {},
                required = {},
            },
        },
    },
}


-- Function to get all tool schemas to send to the LLM.
function Tools.get_all_schemas()
    local schemas = {}
    for name, tool in pairs(registry) do
        table.insert(schemas, tool.schema)
    end
    return schemas
end

-- Function to get a tool's implementation by name.
function Tools.get_tool(name)
    if registry[name] then
        return registry[name].func
    end
    return nil
end

return Tools 