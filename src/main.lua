-- Jarvis: Main Program
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

main() 