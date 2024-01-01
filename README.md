# Zenith - A text editor made fully in zig. 

#### Syntax Highlighting! (poorly)
#### Terminal Support! (poorly)

## Controls:
- Arrows to navigate arround
    - with support of Ctrl-(Arrow)
- Ctrl + O, open a file from cwd
- Ctrl + N, new empty tab
- Ctrl + S, save a file
- Ctrl + K, move to the left tab
- Ctrl + L, move to the right tab
- Ctrl + P, terminal
- Ctrl + W, close the tab
- Ctrl + Z, to undo last change
- Esc, To [exit](https://stackoverflow.com/questions/11828270) the editor, terminal or file opener

## To-Do:
- [ ] Improve the Syntax Highlighting
- [ ] Add colors to the Terminal
- [ ] Ctrl-F to search stuff around the file
- [ ] .gitignore Support for Ctrl + O
- [ ] Maybe better Input parsing?
- [ ] Ctrl + Y to Undo/Redo
- [ ] Text Selection (w/ Ctrl + A)
- [ ] Ctrl + D to Duplicate Line
- [ ] Alt + (Arrow) to move arround a Line
- [ ] Formatting
- [ ] Handle long Box queries
- [ ] Make the code more readable

<sub>The tests were perfomed on a kitty (w/ bash) terminal.</sub>
<sub>Ctrl + Backspace Does not work in VSCode Terminal, this is not a bug.</sub>