import os
import textwrap
import re
import datetime

# --- Configuration ---
# The directory containing the source Lua files.
SRC_DIR = 'src'
# The directory for library files on the ComputerCraft computer.
LIB_DIR_ON_CC = 'programs/lib/jarvis'
# The directory for program files on the ComputerCraft computer.
PROGRAMS_DIR_ON_CC = 'programs'
# The main program file in SRC_DIR. This will be placed in PROGRAMS_DIR_ON_CC.
MAIN_SRC_FILE = 'main.lua'
# The name of the program on the ComputerCraft computer.
PROGRAM_NAME = 'jarvis'
# The output directory for the installer script.
DIST_DIR = 'dist'
# The name of the installer script.
INSTALLER_NAME = 'install.lua'

# --- Installer template ---
INSTALLER_TEMPLATE = textwrap.dedent("""
    -- Jarvis Installer

    local files = {{}}

    -- Packed files will be inserted here by the build script.
    {packed_files}

    local function install()
        print("Removing old version if it exists...")
        -- Delete the main program file and the library directory to ensure a clean install.
        local program_path = "{program_to_run}"
        local lib_path = "{lib_dir}"
        if fs.exists(program_path) then
            print("  Deleting " .. program_path)
            fs.delete(program_path)
        end
        if fs.exists(lib_path) then
            print("  Deleting " .. lib_path)
            fs.delete(lib_path)
        end

        print("Installing Jarvis...")

        for path, content in pairs(files) do
            print("Writing " .. path)
            local dir = path:match("(.*)/")
            if dir and not fs.exists(dir) then
                fs.makeDir(dir)
            end

            -- No need to check for existence, we are performing a clean install.
            local file, err = fs.open(path, "w")
            if not file then
                printError("Failed to open " .. path .. ": " .. tostring(err))
                return
            end
            file.write(content)
            file.close()
        end
        
        -- Create placeholder config file if it doesn't exist
        local config_path = "/etc/jarvis/config.lua"
        if not fs.exists(config_path) then
            print("Creating placeholder config file at " .. config_path)
            local config_dir = "/etc/jarvis"
            if not fs.exists(config_dir) then
                fs.makeDir(config_dir)
            end
            
            local config_content = [[-- Configuration for Jarvis
local config = {{}}

-- Your OpenAI API key from https://platform.openai.com/api-keys
-- Replace YOUR_OPENAI_KEY_HERE with your actual OpenAI API key
config.openai_api_key = "YOUR_OPENAI_KEY_HERE"

-- Your Gemini API key from https://ai.google.dev/
-- Replace YOUR_GEMINI_KEY_HERE with your actual Gemini API key  
config.gemini_api_key = "YOUR_GEMINI_KEY_HERE"

-- The model to use
-- OpenAI models: "gpt-4o", "gpt-4o-mini", "gpt-4"
-- Gemini models: "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"
config.model = "gpt-4o"

return config
]]
            
            local config_file = fs.open(config_path, "w")
            if config_file then
                config_file.write(config_content)
                config_file.close()
                print("Placeholder config created. Edit " .. config_path .. " and add your API key.")
            else
                printError("Failed to create config file at " .. config_path)
            end
        else
            print("Config file already exists at " .. config_path)
        end
        
        -- Create default LLM config file if it doesn't exist
        local llm_config_path = "/etc/jarvis/llm_config.lua"
        if not fs.exists(llm_config_path) then
            print("Creating default LLM config file at " .. llm_config_path)
            local config_dir = "/etc/jarvis"
            if not fs.exists(config_dir) then
                fs.makeDir(config_dir)
            end
            
            local llm_config_content = [[-- LLM Configuration for Jarvis
local config = {{}}

-- Default LLM provider ("openai" or "gemini")
config.provider = "openai"

-- Enable debug logging for LLM requests
config.debug_enabled = true

-- Request timeout in seconds
config.timeout = 30

-- Number of retry attempts for failed requests
config.retry_count = 3

-- Delay between retries in seconds
config.retry_delay = 1

return config
]]
            
            local llm_config_file = fs.open(llm_config_path, "w")
            if llm_config_file then
                llm_config_file.write(llm_config_content)
                llm_config_file.close()
                print("Default LLM config created.")
            else
                printError("Failed to create LLM config file at " .. llm_config_path)
            end
        else
            print("LLM config file already exists at " .. llm_config_path)
        end
        
        local startup_path = "startup.lua"
        local program_to_run = "{program_to_run}"
        
        local current_startup_content
        if fs.exists(startup_path) then
            local f = fs.open(startup_path, "r")
            current_startup_content = f.readAll()
            f.close()
        end

        if not current_startup_content or not current_startup_content:find(program_to_run, 1, true) then
            print("Adding Jarvis to startup file.")
            local startup_file = fs.open(startup_path, "a")
            startup_file.write(('shell.run("%s")\\n'):format(program_to_run))
            startup_file.close()
        else
            print("Jarvis already in startup file.")
        end

        print([[

    Installation complete! Build #{build_number} ({build_date})
    
    IMPORTANT: Edit /etc/jarvis/config.lua and add your API keys:
    - OpenAI API key: https://platform.openai.com/api-keys
    - Gemini API key: https://ai.google.dev/
    
    Configuration files created:
    - /etc/jarvis/config.lua     (API keys and model settings)
    - /etc/jarvis/llm_config.lua (LLM provider settings)
    
    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: '{program_to_run}'
    ]])
    end

    install()
""")

def pack_file_content(content):
    """
    Packs content into a Lua long string, automatically handling nesting.
    It finds the longest sequence of equals signs in any existing long bracket
    sequences in the content and uses a level of equals signs that won't conflict.
    """
    # Find all occurrences of "[=[...[=" or "]=...]=]" to determine the required level of nesting.
    all_brackets = re.findall(r"\[(=*)\[|\](=*)\]", content)
    
    max_len = -1
    for group in all_brackets:
        # group is a tuple, e.g., ('=', '') or ('', '=='). Get the one that matched.
        matched_equals = group[0] if group[0] else group[1]
        max_len = max(max_len, len(matched_equals))
        
    equals = "=" * (max_len + 1)
    
    # Prepending a newline is a good practice to handle content that starts
    # with something that could be misinterpreted after the opening bracket.
    return f"[{equals}[\n{content}\n]{equals}]"

def main():
    """Main function to build the installer."""
    # Get build number from environment or default to 0
    build_number = os.environ.get('BUILD_NUMBER', '0')
    build_date = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    print(f"Building with build number: {build_number}")
    
    if not os.path.exists(SRC_DIR):
        os.makedirs(SRC_DIR)
        print(f"Created '{SRC_DIR}' directory. Place your Lua source files here.")

    if not os.path.exists(DIST_DIR):
        os.makedirs(DIST_DIR)

    packed_files_lua = []
    program_file_on_cc = ""
    program_to_run_on_cc = f"{PROGRAMS_DIR_ON_CC}/{PROGRAM_NAME}"

    for root, _, files in os.walk(SRC_DIR):
        for file in files:
            src_path = os.path.join(root, file)
            rel_path = os.path.relpath(src_path, SRC_DIR).replace('\\', '/')

            try:
                with open(src_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                # Replace build placeholders in the content
                content = content.replace('{{BUILD_NUMBER}}', build_number)
                content = content.replace('{{BUILD_DATE}}', build_date)
            except IOError as e:
                print(f"Could not read file {src_path}: {e}")
                continue

            if rel_path == MAIN_SRC_FILE:
                dest_path = program_to_run_on_cc
                program_file_on_cc = dest_path
            else:
                dest_path = f"{LIB_DIR_ON_CC}/{rel_path}"
            
            dest_path = dest_path.replace('\\', '/')
            packed_files_lua.append(f'files["{dest_path}"] = {pack_file_content(content)}')
    
    if not program_file_on_cc:
        print(f"Error: Main source file '{MAIN_SRC_FILE}' not found in '{SRC_DIR}'.")
        # Create a placeholder if it doesn't exist
        main_lua_path = os.path.join(SRC_DIR, MAIN_SRC_FILE)
        if not os.path.exists(main_lua_path):
            with open(main_lua_path, "w", encoding="utf-8") as f:
                f.write("-- Placeholder main.lua\nprint('Hello from placeholder!')\n")
            print(f"Created a placeholder '{main_lua_path}'. Please run the build script again.")
        return

    installer_content = INSTALLER_TEMPLATE.format(
        packed_files='\n'.join(packed_files_lua),
        program_to_run=program_to_run_on_cc,
        lib_dir=LIB_DIR_ON_CC,
        build_number=build_number,
        build_date=build_date
    )

    installer_path = os.path.join(DIST_DIR, INSTALLER_NAME)
    try:
        with open(installer_path, 'w', encoding='utf-8') as f:
            f.write(installer_content)
    except IOError as e:
        print(f"Could not write installer file: {e}")
        return

    print(f"\\nInstaller script created at: {installer_path}")
    print("\\nTo use this installer:")
    print("1. Set up a public GitHub repository for this project.")
    print("2. Commit and push your files, including the generated installer.")
    print("3. In your ComputerCraft world, ensure HTTP is enabled in the config.")
    print("4. On your ComputerCraft computer, run the `wget` command from README.md.")


if __name__ == "__main__":
    main() 