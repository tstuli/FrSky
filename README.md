# FrSky — VS Code Lua Workspace

This workspace is configured for Lua development.

How to open

- Open `FrSky.code-workspace` in Visual Studio Code to load the workspace and recommended settings.

Recommended extensions

- Lua language server (sumneko.lua / Lua Language Server) — provides completions, diagnostics, and navigation.

Quick tasks

- Run the current Lua file: open Command Palette -> Tasks: Run Task -> "Run Lua" or use the task in `.vscode/tasks.json`.
- Build (if present): run the "Make Build" task which calls `make build`.

If you want, I can add a GitHub Actions workflow to cross-compile binaries or run tests automatically.
