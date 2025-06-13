-- ChatBox Queue Module
-- Manages message sending with a queue to prevent rapid message issues

local chatbox_queue = {}

-- Load tools module for bot name management
local tools = require("lib.jarvis.tools")
local debug = require("debug")

-- Queue state
local message_queue = {}
local last_send_time = 0
local min_delay_ticks = 20  -- 1 second (20 ticks per second)
local chatbox_peripheral = nil

-- Initialize the queue with a chatbox peripheral and optional delay
function chatbox_queue.init(peripheral, delay_seconds)
    chatbox_peripheral = peripheral
    if delay_seconds then
        min_delay_ticks = delay_seconds * 20  -- Convert seconds to ticks
    end
    message_queue = {}
    last_send_time = 0
    debug.info("ChatBox Queue initialized with " .. (delay_seconds or 1) .. " second delay")
end

-- Add a message to the queue
function chatbox_queue.sendMessage(message, sender, target)
    if not chatbox_peripheral then
        error("ChatBox queue not initialized. Call chatbox_queue.init() first.", 2)
    end
    
    table.insert(message_queue, {
        message = message,
        sender = sender or "Computer",
        target = target or "<>"
    })
    
    debug.debug("ChatBox Queue message queued: " .. tostring(message))
end

-- Process the queue - call this regularly in your main loop
function chatbox_queue.process()
    if not chatbox_peripheral then
        return
    end
    
    -- Check if we have messages to send
    if #message_queue == 0 then
        return
    end
    
    local current_time = os.clock() * 20  -- Convert to ticks
    
    -- Check if enough time has passed since last send
    if current_time - last_send_time >= min_delay_ticks then
        local msg_data = table.remove(message_queue, 1)  -- Remove first message from queue
        
        local ok, err = chatbox_peripheral.sendMessage(msg_data.message, msg_data.sender, msg_data.target)
        if ok then
            debug.info("ChatBox Queue message sent: " .. msg_data.message)
            last_send_time = current_time
        else
            debug.error("ChatBox Queue failed to send message: " .. tostring(err))
            -- Re-add message to front of queue to retry
            table.insert(message_queue, 1, msg_data)
        end
    end
end

-- Get queue status
function chatbox_queue.getQueueSize()
    return #message_queue
end

-- Clear the queue (useful for emergencies)
function chatbox_queue.clearQueue()
    local cleared_count = #message_queue
    message_queue = {}
    debug.warn("ChatBox Queue cleared " .. cleared_count .. " messages from queue")
    return cleared_count
end

-- Simple interface for sending public messages
function chatbox_queue.send(message)
    local bot_name = tools.get_bot_name()
    return chatbox_queue.sendMessage(message, bot_name, "<>")
end

-- Create a chat interface object for even simpler usage
local chat = {}
chat.send = chatbox_queue.send

-- Export both the full interface and the simple chat interface
chatbox_queue.chat = chat

return chatbox_queue 