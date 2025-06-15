# Jarvis - A ComputerCraft AI Assistant

A sophisticated AI-powered assistant for ComputerCraft that uses LLM APIs (OpenAI/Gemini) to provide intelligent automation and interaction capabilities.

## Features

- **Multi-Provider LLM Support**: Compatible with OpenAI GPT models and Google Gemini
- **Unified Configuration**: Centralized configuration management with validation
- **Input Validation**: Comprehensive input sanitization and validation
- **Tool System**: Extensible tool architecture for game world interaction
- **Personality Modes**: Switch between professional Jarvis mode and heroic All Might mode
- **Debug Logging**: Comprehensive logging system for troubleshooting
- **Auto-Startup**: Automatically starts on computer boot
- **Message Queuing**: Rate-limited chat to prevent spam

## Getting Started

### Prerequisites

- A Minecraft instance with [CC: Tweaked](https://tweaked.cc/) and [Advanced Peripherals](https://docs.advanced-peripherals.de/latest/) installed
- HTTP API enabled in the `computercraft-common.toml` config file
- A ChatBox peripheral attached to your computer
- API keys for your preferred LLM provider(s)

### Installation

On your ComputerCraft computer, run the following command:

```
wget run https://raw.githubusercontent.com/n0es/cc-jarvis/main/dist/install.lua
```

This will download and run the installer, placing all necessary files on your computer.

### Configuration

After installation, you'll need to configure your API keys:

#### 1. Get API Keys

**OpenAI**: Create an API key at [OpenAI Platform](https://platform.openai.com/api-keys)  
**Gemini**: Get an API key at [Google AI Studio](https://ai.google.dev/)

#### 2. Edit Configuration

Edit the main configuration file:
```
edit /etc/jarvis/config.lua
```

Update the following values:
```lua
-- /etc/jarvis/config.lua
local config = {}

-- Your OpenAI API key (if using OpenAI)
config.openai_api_key = "sk-your-actual-key-here"

-- Your Gemini API key (if using Gemini)  
config.gemini_api_key = "your-actual-key-here"

-- The model to use
config.model = "gpt-4o"  -- or "gemini-2.0-flash"

return config
```

#### 3. Optional: Configure LLM Settings

Edit the LLM configuration file for advanced settings:
```
edit /etc/jarvis/llm_config.lua
```

Available settings:
```lua
-- /etc/jarvis/llm_config.lua
local config = {}

config.provider = "openai"        -- "openai" or "gemini"
config.debug_enabled = true       -- Enable debug logging
config.timeout = 30               -- Request timeout (seconds)
config.retry_count = 3            -- Number of retries on failure
config.retry_delay = 1            -- Delay between retries (seconds)
config.personality = "jarvis"     -- "jarvis" or "all_might"

return config
```

## Usage

After configuration, reboot the computer. Jarvis will start automatically.

To run manually:
```
jarvis
```

### Interacting with Jarvis

- **Mention the bot name** in chat to activate listening mode
- **Example**: "jarvis, what time is it?"
- **Commands work** when the bot is in listening mode (120 seconds after mention)

### Available Tools

- `get_time` - Get current in-game time
- `change_name` - Change the bot's name
- `change_personality` - Switch between personality modes
- `door_control` - Control base doors via modem (requires setup)
- `test_connection` - Test HTTP connectivity and LLM provider access
- `get_config` - View configuration values

### Personality Modes

**Jarvis Mode** (default): Professional AI assistant similar to Iron Man's Jarvis  
**All Might Mode**: Heroic and enthusiastic responses inspired by My Hero Academia

Switch personality:
"jarvis, change your personality to all_might"

## Architecture

### Project Structure

```
src/
├── main.lua                     # Main application entry point
├── llm.lua                      # LLM provider abstraction
├── tools.lua                    # Tool system and registry
├── debug.lua                    # Debug logging system
├── chatbox_queue.lua           # Message queue management
├── config/
│   ├── unified_config.lua      # Unified configuration system
│   └── llm_config.lua          # Legacy LLM configuration
├── providers/
│   ├── base_provider.lua       # Provider interface
│   ├── openai_provider.lua     # OpenAI implementation
│   ├── gemini_provider.lua     # Gemini implementation
│   └── provider_factory.lua    # Provider factory
└── utils/
    └── input_validator.lua     # Input validation system
```

### Configuration System

The new unified configuration system automatically migrates settings from legacy files and provides:

- **Validation**: All configuration values are validated
- **Defaults**: Sensible default values for all settings
- **Migration**: Automatic migration from old configuration files
- **Security**: API keys are masked in logs and debug output

### Error Handling

- **Input Validation**: All user inputs are validated and sanitized
- **Graceful Degradation**: System continues operating when non-critical components fail
- **Comprehensive Logging**: Detailed error tracking and debugging information
- **Recovery Mechanisms**: Automatic retry logic for API failures

## Development

### Building

The project uses a Python build script for packaging:

```bash
# Build with automatic version increment
python build.py

# Build with specific version increment
VERSION_INCREMENT=minor python build.py

# Build with custom build number
BUILD_NUMBER=123 python build.py
```

### Adding Custom Tools

Tools can be registered dynamically:

```lua
local tools = require("lib.jarvis.tools")

-- Register a custom tool
tools.register_tool("my_tool", function(args)
    -- Tool implementation
    return { success = true, message = "Tool executed" }
end, {
    type = "function",
    name = "my_tool",
    description = "My custom tool",
    parameters = {
        type = "object",
        properties = {
            param1 = { type = "string", description = "A parameter" }
        },
        required = {"param1"}
    }
})
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Troubleshooting

### Common Issues

**"HTTP API is not available"**
- Ensure HTTP is enabled in `computercraft-common.toml`
- Set `http_enable = true` in the config file

**"ChatBox peripheral not found"**
- Attach a ChatBox peripheral to your computer
- Ensure Advanced Peripherals mod is installed

**"API key validation failed"**
- Check that your API key is correct and properly formatted
- Ensure the key has appropriate permissions

**"LLM request failed"**
- Check internet connectivity with `test_connection` tool
- Verify API key is valid and has credits/quota remaining
- Check debug logs for detailed error information

### Debug Mode

Enable detailed debugging:
1. Edit `/etc/jarvis/llm_config.lua`
2. Set `config.debug_enabled = true`
3. Restart Jarvis
4. Check `debug.log` file for detailed information

### Getting Help

- Check the debug logs in the computer's directory
- Use the `test_connection` tool to diagnose connectivity issues
- Verify configuration with the `get_config` tool
- Report issues on the project's GitHub repository

## License

This project is open source. Please check the repository for license details.

## Changelog

### Version 1.1.0
- Added unified configuration system
- Implemented comprehensive input validation
- Improved error handling and recovery
- Added build versioning and manifest generation
- Enhanced security with API key masking
- Refactored codebase for better maintainability

### Version 1.0.0
- Initial release
- Multi-provider LLM support (OpenAI/Gemini)
- Basic tool system
- Personality modes
- Auto-startup functionality