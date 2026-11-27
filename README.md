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

# AI gauge discard
When a gauge-discard effect lets the affected opponent choose (`opponent_chooses`),
the AI randomly discards one of its own gauge cards. Effects where the owner
chooses an opponent's gauge card retain their existing AI policy.

# S8 boost infuse
Normal and shortcut boost selection ask “是否要灌注？” before boost payment or
effects when an uninfused S8 character selects a boost with an Infused conditional
effect (including nested effects) and can pay an existing infuse option.
The options reuse the character's set-strike ability, including Akimo's life
payment, on both sides of all 16 S8 characters. UI and engine share the same
payability check: exclude the boost and reserved payment cards, include passive
free gauge, and require enough life after any reserved life payment.
No payable option means no infuse prompt.
Accepting selects the infuse payment, then the boost payment. Both payments are
validated together by the game engine; a card cannot pay for both, and the boost
cannot pay for itself. Infuse resolves before boost payment and effects.
The optional `infuse_payment` field travels with the boost network/replay action:
an empty array explicitly declines, a card-ID array pays gauge, `{"life": 2}`
selects a supported life-payment option, and `{"free_gauge": 1}` uses a passive
gauge discount without consuming it. Absent fields retain the legacy post-payment
prompt for AI and older recorded actions.
Declining continues normally; already-infused characters, passive-infuse boosts,
and boosts without Infused effects do not receive an extra prompt.

# Rules hint card
Use the light-blue “游戏规则提示卡” button below the main menu's reference-card
button or beside the in-game surrender button to open the rules image.
The image is centered and scaled to fit the window. Click outside the image
or the image's top-right corner to close it; clicking elsewhere on the image
does not dismiss it or interact with the game.

# Reconnect UI
Reconnect hellos describe temporary connections and do not replace the previous
player name. The client restores the old session before requesting a name change.
If the session has expired, it requests the previous name on the new connection;
this preserves the name but does not recover the old match. If the server assigns
a different name (for example, because of a collision), the client reports it and
keeps the saved name preference. Reconnect name updates do not overwrite local
settings. Refresh/close session recovery is not added by this change.

Historical card-naming events (including Focus's Reading boost) do not reopen
selection UI during restore fast-forward. Once restoration finishes, the client
restores a naming prompt only if the current decision still requires it. This
keeps the opponent deck reference usable after a completed Reading.

# Online strike UI
Gauge/sealed strike prompts carry their source zone in the local event payload.
They must not read the current decision when displayed: another network action
can already have cleared it while the prompt waits behind animations. Otherwise
a delayed Hyde character-action prompt can drop the attack and response UI even
though later emotes still display. This is a client fix; no server protocol
change is required. Regression coverage: `test/unit/test_delayed_gauge_strike_ui.gd`.

# Deck reference history
Both players' in-game deck references support switching between current counts
and the snapshot before their latest reshuffle (or deck/discard swap).
Each player's history is independent. Historical views hide current topdeck and
hand-information icons; reopening a reference shows current counts again.

# Card ID speed hints
Action-menu instructions and choices, and both players' boost summaries, append
the existing card-type/printed-speed hint to recognized card definition IDs and
display names, including localized normal names (for example,
`Flight 13` becomes `Flight 13（特4速）`). Name matching uses the current game's
definitions; effect choices with a card ID use that specific card's definition.
Ambiguous bare names with different printed hints are not guessed.
When distinct cards in the same character deck share a type and printed speed,
their hints also include printed power after the speed, for example `（特5速7攻）`. Duplicate
copies of one definition and cards from different decks do not cause this
extra annotation; set-aside cards and skin decks are included.
Already annotated references (with either full-width or ASCII parentheses) are
left unchanged. Rich-text tags, unknown IDs, and cards without a speed hint are
preserved. Custom card definitions are supported once loaded.

The shared index is maintained in `data/decks/_card_name_index.gd`, not a
handwritten duplicate of card data. It builds per-deck printed-stat hints from
the existing JSON definitions, caches definition-ID lookups and name matchers,
and shares one matcher across an action-menu refresh. Skin decks use their
actual definition IDs and embedded custom definitions; equal image indices
never imply equal speed or power. Context caches include printed stats and
are bounded to 64 entries. Loading cards/decks invalidates the index, which
rebuilds once on the next lookup. Code that directly edits the data dictionaries
must call `CardDataManager.invalidate_card_name_index()` after editing.

# Numeric effect text
Effect descriptions, choices, resource summaries, card stats, and stat/movement
notices display whole-valued floats as integers (`2.0` becomes `2`).
Formatting reuses the card-data numeric normalizer on display-only copies;
runtime values, genuine fractions, symbolic stats, and authored strings
(including card names and rich-text markup) remain unchanged.

# Server
Replay saving starts local download/save and server upload independently. Upload
errors do not invalidate an already saved local replay. Failure dialogs distinguish
`CONNECTION_UNAVAILABLE`, `REQUEST_SEND_FAILED`, `SERVER_UPLOAD_FAILED`,
`INVALID_UPLOAD_RESPONSE`, and `UPLOAD_REASON_MISSING`. Server failures retain
provided error/code/message/detail, HTTP status, and request/trace identifiers.
When reporting a failure, include the dialog details and time so server upload
logs can be correlated. If the server supplies no reason, the client explicitly
says so rather than guessing an OSS/network cause. An accepted upload request
can remain deferred until match settlement.

See server project:
https://github.com/daniel-k-taylor/exceedgameserver
