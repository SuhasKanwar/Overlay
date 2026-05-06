# Project_020_Overlay

This Electron app runs as a small always-on-top overlay.

When you press a keyboard shortcut, it temporarily hides itself, captures the primary screen, sends the screenshot to Groq (OpenAI-compatible API), and shows only the direct answer.

## Shortcuts

- Toggle overlay: `Ctrl+Shift+Alt+O` (macOS: `Cmd+Shift+Alt+O`)
- Capture + answer: `Ctrl+Shift+Alt+S` (macOS: `Cmd+Shift+Alt+S`)

## Setup

1. Install dependencies

   `npm install`

2. Create your local env file

   Copy `.env.example` to `.env` and set `GROQ_API_KEY`.

3. Run

   `npm start`

## Configuration

`GROQ_API_KEY` is required and must be set in `.env`.

The API URL, model, and prompts are currently hardcoded in the app code.

## Notes

- On Linux, transparency/blur depends on your compositor.
- If the configured model is not vision-capable, Groq will return an API error.
