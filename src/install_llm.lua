-- install_llm.lua
-- Installation script for the LLM provider system

print("===== LLM Provider System Installation =====")
print()

-- Load the LLM module
local LLM = require("llm")

-- Run the installation process
print("Installing LLM configuration system...")
local success, message = LLM.install()

print()
if success then
    print("✓ LLM system installed successfully!")
    print("✓ You can now use the LLM system with provider switching.")
    print()
    print("Quick start commands:")
    print("  LLM.get_current_provider()     -- Check current provider")
    print("  LLM.get_available_providers()  -- List available providers")
    print("  LLM.set_provider('provider')   -- Switch providers")
    print("  LLM.print_config()             -- Show current config")
    print()
    print("Test your setup with: lua src/test_providers.lua")
else
    print("! Installation completed with warnings:")
    print("! " .. message)
    print("! The system will still work but configuration may not persist.")
end

print()
print("===== Installation Complete =====")

return success 