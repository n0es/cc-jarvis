import os
import textwrap
import re

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
local config = {}

-- Your OpenAI API key from https://platform.openai.com/api-keys
-- Replace YOUR_API_KEY_HERE with your actual API key
config.openai_api_key = "YOUR_API_KEY_HERE"

-- The model to use. "gpt-4o" is a good default.
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

    Installation complete!
    IMPORTANT: Edit /etc/jarvis/config.lua and add your OpenAI API key.
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
        lib_dir=LIB_DIR_ON_CC
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