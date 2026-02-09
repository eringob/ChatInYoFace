# ChatInYoFace
Show your chat messages in the middle of your screen.

## How It Works
ChatInYoFace listens to selected chat events and mirrors those messages into a custom on-screen message frame. You can choose which channels appear, adjust font styling, size, line count, and display duration, and optionally play a sound per channel. The addon can also hide the original chat frame while keeping the active edit box available for typing.

## Install
1. Copy this folder to your WoW AddOns directory as ChatInYoFace.
2. Restart the game or reload the UI.

## Usage
- /cif unlock — show the anchor and drag it.
- /cif lock — hide the anchor.
- /cif font <path> — set the font file path.
- /cif size <8-64> — set font size.
- /cif lines <1-20> — set number of lines.
- /cif time <1-30> — set seconds on screen.

## Changelog
### 1.2.0
- Persistently hide the original chat frame across UI reloads.
- Keep chat tabs hidden while allowing the active edit box for input.
- Prevent stray edit boxes from lingering when toggling chat visibility.
- Align options panel controls to a consistent layout.
- Make outline text more visible with thicker outlines.
- Keep dropdown text legible by placing the backdrop behind labels.

### 1.1.0
- Options panel refresh and styling updates.
- ElvUI-like dropdown/slider styling and anchor styling.
- Per-channel sounds with preview.
- Dynamic channel list and community handling.
- GMotD option with login/reload display.
- Message width wrapping and auto spacing for multi-line text.
