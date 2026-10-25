# Exceed fan game client
This is a Godot project for an implementation of the Exceed Fighting System card game from Level 99 Games.
I do not own any of the art IP in this project and do not have affiliation with any of the creators.

The goal of this project is to have a playable version of the game in a web browser.

This project is paired with a game server written in nodeJS.

# Code Layout
- assets - all art
- data - deck/card definitions
- globals - global code scripts
- scenes - all godot scenes and script files
    - card - card related scenes
    - core - all core engine
        - ai - ai related scripts
    - menu - menu related scenes
    - game - all game UX focused scenes
- test - GUT automated tests

# Rules hint card
Use the light-blue “游戏规则提示卡” button below the main menu's reference-card
button or beside the in-game surrender button to open the rules image.
The image is centered and scaled to fit the window. Click outside the image
or the image's top-right corner to close it; clicking elsewhere on the image
does not dismiss it or interact with the game.

# Reconnect UI
Historical card-naming events (including Focus's Reading boost) do not reopen
selection UI during restore fast-forward. Once restoration finishes, the client
restores a naming prompt only if the current decision still requires it. This
keeps the opponent deck reference usable after a completed Reading.

# Server
See server project:
https://github.com/daniel-k-taylor/exceedgameserver
