# Jarvis - A ComputerCraft Assistant

This project is a ComputerCraft program designed to manage items, and interact with the player. It is built to be developed locally and then installed on in-game computers using a build script.

## Getting Started

### Prerequisites

- A Minecraft instance with [CC: Tweaked](https://tweaked.cc/) and [Advanced Peripherals](https://docs.advanced-peripherals.de/latest/) installed.
- HTTP API enabled in the `computercraft-common.toml` config file for `wget` to work.
- Python 3.6+ installed on your local machine to run the build script.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/YOUR_USERNAME/jarvis.git
    cd jarvis
    ```
    (Replace `YOUR_USERNAME` with your actual GitHub username)

2.  **Build the project:**
    Run the build script to package the Lua files into an installer.
    ```bash
    python build.py
    ```
    This will create `dist/install.lua`.

3.  **Commit and push to GitHub:**
    Commit the generated installer and push your changes to your repository's `main` branch.
    ```bash
    git add .
    git commit -m "Initial build"
    git push origin main
    ```

4.  **Install in-game:**
    On your ComputerCraft computer, run the following command. Make sure to replace `YOUR_USERNAME` and `YOUR_REPO` with your details.
    ```
    wget run https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/dist/install.lua
    ```
    This will download and run the installer, placing all the necessary files on your computer and setting up Jarvis to run on boot.

## Usage

After installation, reboot the computer. Jarvis will start automatically.

To run it manually, use the command:
```
programs/jarvis
```

## Development

-   Place all your Lua source code in the `src` directory.
-   `src/main.lua` is the main entry point for the program.
-   Other Lua files (libraries, modules) will be placed under `lib/jarvis/` on the in-game computer.
-   After making changes, run `python build.py` again and push the updated `dist/install.lua` to your repository. Then you can re-run the `wget` command in-game to update your program. 