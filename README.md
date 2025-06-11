# Jarvis - A ComputerCraft Assistant

## Getting Started

### Prerequisites

- A Minecraft instance with [CC: Tweaked](https://tweaked.cc/) and [Advanced Peripherals](https://docs.advanced-peripherals.de/latest/) installed.
- HTTP API enabled in the `computercraft-common.toml` config file.

### Installation

On your ComputerCraft computer, run the following command:
```
wget run https://raw.githubusercontent.com/n0es/cc-jarvis/main/dist/install.lua
```
This will download and run the installer, placing all the necessary files on your computer.

### LLM Configuration

Jarvis uses an LLM (like GPT-4o) to understand commands and respond to you. **This is a required step.**

1.  **Get an OpenAI API Key:**
    If you don't already have one, create an API key on the [OpenAI Platform](https://platform.openai.com/api-keys).

2.  **Create the Config Directory:**
    On your ComputerCraft computer, create a new directory for the config file:
    ```
    mkdir /etc/jarvis
    ```

3.  **Create and Edit the Config File:**
    Now, create and edit the config file itself:
    ```
    edit /etc/jarvis/config.lua
    ```

4.  **Add Your Key:**
    Paste the following code into the editor, replacing `"YOUR_API_KEY_HERE"` with your actual secret key.
    ```lua
    -- /etc/jarvis/config.lua
    local config = {}

    -- Your OpenAI API key.
    config.openai_api_key = "YOUR_API_KEY_HERE"

    -- The model to use. "gpt-4o" is a good default.
    config.model = "gpt-4o"

    return config
    ```
    Save the file (`Ctrl+S`) and exit the editor (`Ctrl+T`).


## Usage

After installation and configuration, reboot the computer. Jarvis will start automatically by running `/programs/jarvis`.

To run it manually, use the command:
```
jarvis
```