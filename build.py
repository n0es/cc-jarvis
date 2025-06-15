import os
import textwrap
import re
import datetime
import json

# --- Configuration ---
# The directory containing the source Lua files.
SRC_DIR = 'src'
# The directory for library files on the ComputerCraft computer.
LIB_DIR_ON_CC = 'lib/jarvis'
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
# Version file for tracking releases
VERSION_FILE = 'version.json'

# --- Version Management ---
def load_version():
    """Load version information from version.json"""
    default_version = {
        "major": 1,
        "minor": 0,
        "patch": 0,
        "build": 0,
        "prerelease": None
    }
    
    if os.path.exists(VERSION_FILE):
        try:
            with open(VERSION_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load version file: {e}")
    
    return default_version

def save_version(version):
    """Save version information to version.json"""
    try:
        with open(VERSION_FILE, 'w') as f:
            json.dump(version, f, indent=2)
        return True
    except IOError as e:
        print(f"Warning: Failed to save version file: {e}")
        return False

def increment_version(version, increment_type='build'):
    """Increment version based on type"""
    if increment_type == 'major':
        version['major'] += 1
        version['minor'] = 0
        version['patch'] = 0
        version['build'] = 0
    elif increment_type == 'minor':
        version['minor'] += 1
        version['patch'] = 0
        version['build'] = 0
    elif increment_type == 'patch':
        version['patch'] += 1
        version['build'] = 0
    else:  # build
        version['build'] += 1
    
    return version

def format_version(version):
    """Format version as string"""
    base = f"{version['major']}.{version['minor']}.{version['patch']}"
    if version['build'] > 0:
        base += f".{version['build']}"
    if version['prerelease']:
        base += f"-{version['prerelease']}"
    return base

# --- Installer template ---
INSTALLER_TEMPLATE = textwrap.dedent("""
    -- Jarvis Installer v{version}
    -- Build #{build_number} ({build_date})

    local files = {{}}

    -- Packed files will be inserted here by the build script.
    {packed_files}

    local function install()
        print("Installing Jarvis v{version}...")
        print("Build #{build_number} ({build_date})")
        
        -- Delete the main program file and the library directory to ensure a clean install.
        local program_path = "{program_to_run}"
        local lib_path = "{lib_dir}"
        
        print("Removing old version if it exists...")
        if fs.exists(program_path) then
            print("  Deleting " .. program_path)
            fs.delete(program_path)
        end
        if fs.exists(lib_path) then
            print("  Deleting " .. lib_path)
            fs.delete(lib_path)
        end

        print("Installing new files...")
        for path, content in pairs(files) do
            print("Writing " .. path)
            local dir = path:match("(.*)/")
            if dir and not fs.exists(dir) then
                fs.makeDir(dir)
            end

            local file, err = fs.open(path, "w")
            if not file then
                printError("Failed to open " .. path .. ": " .. tostring(err))
                return false
            end
            file.write(content)
            file.close()
        end
        
        -- Create build info file
        local build_info_path = "/etc/jarvis/build_info.txt"
        local build_info_dir = "/etc/jarvis"
        if not fs.exists(build_info_dir) then
            fs.makeDir(build_info_dir)
        end
        
        local build_file = fs.open(build_info_path, "w")
        if build_file then
            build_file.write("Jarvis v{version} - Build #{build_number} ({build_date})")
            build_file.close()
        end
        
        -- Create placeholder config file if it doesn't exist
        local config_path = "/etc/jarvis/config.lua"
        if not fs.exists(config_path) then
            print("Creating placeholder config file at " .. config_path)
            local config_content = [[-- Configuration for Jarvis v{version}
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
                print("Placeholder config created. Edit " .. config_path .. " and add your API keys.")
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
            local llm_config_content = [[-- LLM Configuration for Jarvis v{version}
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

-- Personality mode ("jarvis" or "all_might")
config.personality = "jarvis"

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
        
        -- Add to startup if not already present
        local startup_path = "startup.lua"
        local program_to_run = "{program_to_run}"
        
        local current_startup_content = ""
        if fs.exists(startup_path) then
            local f = fs.open(startup_path, "r")
            if f then
                current_startup_content = f.readAll()
                f.close()
            end
        end

        if not current_startup_content:find(program_to_run, 1, true) then
            print("Adding Jarvis to startup file.")
            local startup_file = fs.open(startup_path, "a")
            if startup_file then
                startup_file.write(('shell.run("%s")\\n'):format(program_to_run))
                startup_file.close()
            end
        else
            print("Jarvis already in startup file.")
        end

        print([[

    Installation complete! Jarvis v{version}
    Build #{build_number} ({build_date})
    
    IMPORTANT: Edit /etc/jarvis/config.lua and add your API keys:
    - OpenAI API key: https://platform.openai.com/api-keys
    - Gemini API key: https://ai.google.dev/
    
    Configuration files created:
    - /etc/jarvis/config.lua     (API keys and model settings)
    - /etc/jarvis/llm_config.lua (LLM provider settings)
    
    The new unified configuration system will automatically migrate
    your settings on first run.
    
    Reboot the computer to start Jarvis automatically.
    Or, to run Jarvis now, execute: '{program_to_run}'
    ]])
        
        return true
    end

    local success = install()
    if not success then
        printError("Installation failed!")
    end
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

def create_build_manifest(version_info, build_number, build_date, files):
    """Create a build manifest for tracking"""
    manifest = {
        "version": format_version(version_info),
        "build_number": build_number,
        "build_date": build_date,
        "files": files,
        "generator": "build.py",
        "source_dir": SRC_DIR
    }
    
    manifest_path = os.path.join(DIST_DIR, "build_manifest.json")
    try:
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        print(f"Build manifest created: {manifest_path}")
    except IOError as e:
        print(f"Warning: Failed to create build manifest: {e}")

def main():
    """Main function to build the installer."""
    # Load and increment version
    version_info = load_version()
    increment_type = os.environ.get('VERSION_INCREMENT', 'build')
    version_info = increment_version(version_info, increment_type)
    version_string = format_version(version_info)
    
    # Get build number from environment or use version build number
    build_number = os.environ.get('BUILD_NUMBER', str(version_info['build']))
    build_date = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    print(f"Building Jarvis v{version_string}")
    print(f"Build number: {build_number}")
    print(f"Build date: {build_date}")
    
    # Save updated version
    save_version(version_info)
    
    if not os.path.exists(SRC_DIR):
        os.makedirs(SRC_DIR)
        print(f"Created '{SRC_DIR}' directory. Place your Lua source files here.")
        return

    if not os.path.exists(DIST_DIR):
        os.makedirs(DIST_DIR)

    packed_files_lua = []
    program_file_on_cc = ""
    program_to_run_on_cc = f"{PROGRAMS_DIR_ON_CC}/{PROGRAM_NAME}"
    processed_files = []

    for root, _, files in os.walk(SRC_DIR):
        for file in files:
            if not file.endswith('.lua'):
                continue
                
            src_path = os.path.join(root, file)
            rel_path = os.path.relpath(src_path, SRC_DIR).replace('\\', '/')

            try:
                with open(src_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    
                # Replace build placeholders in the content
                content = content.replace('{{BUILD_NUMBER}}', build_number)
                content = content.replace('{{BUILD_DATE}}', build_date)
                content = content.replace('{{VERSION}}', version_string)
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
            processed_files.append({
                "source": src_path,
                "destination": dest_path,
                "size": len(content)
            })
    
    if not program_file_on_cc:
        print(f"Error: Main source file '{MAIN_SRC_FILE}' not found in '{SRC_DIR}'.")
        # Create a placeholder if it doesn't exist
        main_lua_path = os.path.join(SRC_DIR, MAIN_SRC_FILE)
        if not os.path.exists(main_lua_path):
            with open(main_lua_path, "w", encoding="utf-8") as f:
                f.write(f"-- Jarvis v{version_string} - Placeholder main.lua\nprint('Hello from Jarvis placeholder!')\n")
            print(f"Created a placeholder '{main_lua_path}'. Please add your code and run the build script again.")
        return

    # Generate installer content
    installer_content = INSTALLER_TEMPLATE.format(
        version=version_string,
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

    # Create build manifest
    create_build_manifest(version_info, build_number, build_date, processed_files)

    print(f"\nBuild completed successfully!")
    print(f"Version: {version_string}")
    print(f"Installer created: {installer_path}")
    print(f"Files processed: {len(processed_files)}")
    
    total_size = sum(f['size'] for f in processed_files)
    print(f"Total source size: {total_size:,} bytes")
    
    print("\nTo use this installer:")
    print("1. Commit and push your changes to your repository")
    print("2. In your ComputerCraft world, ensure HTTP is enabled")
    print("3. On your ComputerCraft computer, run:")
    print("   wget run https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/dist/install.lua")
    print(f"\nVersion file updated: {VERSION_FILE}")


if __name__ == "__main__":
    main() 