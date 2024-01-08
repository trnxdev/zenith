# Zenith - A Text Editor Written in Zig

## Features:
- **Syntax Highlighting:** (poorly)
- **Terminal Support:** (poorly)

## Controls:
- **Navigation:**
  - Use arrow keys to navigate around the text
    - Ctrl + arrow keys for quicker navigation
- **Line Manipulation:**
  - Alt + (Arrow Up/Down) to move a line
- **File Operations:**
  - Ctrl + O to open a file (relative from the current working directory)
  - Ctrl + N to open a new empty tab
  - Ctrl + S to save a file
- **Tab Management:**
  - Ctrl + K to move to the left tab
  - Ctrl + L to move to the right tab
  - Ctrl + W to close the tab
- **Editing:**
  - Ctrl + Z to undo the last change
  - Ctrl + D to duplicate a line
- **Search:** 
  - Ctrl + F for file-wide searching
    - Press Escape to exit the Finder
    - Press Enter to continue searching
    - Any other character will exit the Finder and use the character on the Tab
- **Terminal:**
  - Ctrl + P to open it
- **Exit:**
  - Press Esc to exit the editor, the terminal (Ctrl + P), File Explorer (Ctrl + O) or the file-wide searcher

## Config
By default it is stored in $USER/.zenith.json, you can override this by setting the $ZENITH_CONFIG_PATH
Environment Variable.

The config file is in json format, here are the options:
```json
{
    // Defines the horizontal line scroll behaviour,
    // "Line" [Default] will only scroll the line (kind of like nano does)
    // "Tab" will scroll all the visible lines 
    scrolling: "Line" | "Tab" = "Line"
};
```

## To-Do:
- [ ] Add more config options
  - [ ] When to scroll the line option in Config
      - Middle, MiddleEnd, End (?)
- [ ] Colors to the terminal (Ctrl + P)
- [ ] .gitignore support for Ctrl + O
- [ ] Implement Ctrl + Y for Redo
- [ ] Text selection
    - Ctrl + A(?)
- [ ] Implement proper Syntax Highlighting and code formatting
    - Tree-Sitter?
    - LSP?
- [ ] Handle long box queries
- [ ] Refractor input parsing (src/input.zig)
- [ ] Refractor the code (to be more readable)

<sub>The tests were conducted on a Kitty terminal with Bash.</sub>
<sub>Ctrl + Backspace does not work in the VSCode Terminal; this is not a bug.</sub>
