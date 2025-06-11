
-- Jarvis Installer

local files = {}

-- Packed files will be inserted here by the build script.
files["programs/jarvis.lua"] = [[-- Jarvis: Main Program
-- Responds to chat messages from an Advanced Peripherals Chat Box.

local function main()
    -- Find the chat box peripheral.
    -- This requires an "Chat Box" block from Advanced Peripherals to be placed next to the computer.
    local chatBox = peripheral.find("chatBox")

    if not chatBox then
        error("Could not find a 'chatBox' peripheral. Please place one next to the computer.", 0)
    end

    print("Jarvis is online. Waiting for messages.")

    while true do
        -- Wait for a chat message event from the chat box.
        -- This event is specific to the Advanced Peripherals mod.
        local event, player, message, uuid = os.pullEvent("chat_message")

        -- Send a static response back to the player who sent the message.
        local response = "Hello, " .. player .. "! This is a static reply from Jarvis."
        print("Replying to " .. player .. ": " .. response)
        
        -- Use sendMessageToPlayer for a direct reply.
        chatBox.sendMessageToPlayer(response, player)
    end
end

main() ]]

local function install()
    print("Installing Jarvis...")

    for path, content in pairs(files) do
        print("Writing " .. path)
        local dir = path:match("(.*)/")
        if dir and not fs.exists(dir) then
            fs.makeDir(dir)
        end

        if fs.exists(path) then
            print("  Overwriting existing file.")
        end

        local file, err = fs.open(path, "w")
        if not file then
            printError("Failed to open " .. path .. ": " .. tostring(err))
            return
        end
        file.write(content)
        file.close()
    end

    local startup_path = "startup.lua"
    local program_to_run = "programs/jarvis"

    local current_startup_content
    if fs.exists(startup_path) then
        local f = fs.open(startup_path, "r")
        current_startup_content = f.readAll()
        f.close()
    end

    if not current_startup_content or not current_startup_content:find(program_to_run, 1, true) then
        print("Adding Jarvis to startup file.")
        local startup_file = fs.open(startup_path, "a")
        startup_file.write(('shell.run("%s")\n'):format(program_to_run))
        startup_file.close()
    else
        print("Jarvis already in startup file.")
    end

    print([[

Installation complete!
Reboot the computer to start Jarvis automatically.
Or, to run Jarvis now, execute: 'programs/jarvis'
]])
end

install()
