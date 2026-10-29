# Jean on Umbrel

1. Install **Jean** from the Kevmodrome store. Copy its app password from Umbrel; this is the server access token, and there is no username.
2. In the Jean desktop app, click the server icon in the title bar, choose **Add remote**, then **Existing URL**. Enter `http://umbrel.local:13456` and the access token separately. Replace `umbrel.local` with your Umbrel hostname or IP if needed. Prefer a desktop version matching server version **1.0.13**.
3. Select that remote server. Jean keeps its desktop interface while projects, terminals and agents run on your Umbrel. Git, Node.js and npm are included, so remote prerequisite checks should pass without installing anything.
4. With the remote selected, install an agent such as Codex or Claude using its **Jean-managed** CLI setup. For GitHub CLI, choose **System PATH** because `gh` is already included.
5. Use the agent's sign-in action in Jean's embedded terminal. For Codex, the headless flow runs `codex login --device-auth`: open the displayed provider URL and enter the device code. Finish provider approval yourself, then return to Jean.
6. Create or clone a repository under `/home/jean/projects` and start a session. For Codex, keep **Full access** selected in the session's permissions menu and use trusted project folders.

The server uses port `13456`. Native-client HTTP APIs and WebSocket connections require the Jean token and can connect without an Umbrel login cookie. Opening the app from Umbrel shows the server's health status; use Jean's native client to work with the server.

The entire `/home/jean` directory persists, including repositories, worktrees, Jean settings, SSH and Git configuration, downloaded agent CLIs, and provider sign-ins. On umbrelOS 2.0, you can select a **Projects** folder in Jean's Umbrel settings; Jean sees it at `/home/jean/projects`. Jean needs write access to that folder to edit code and manage worktrees.

**Full access** is Jean's default and allows the agent to use files and commands throughout its container, including any Projects folder you selected. Codex's additional Linux sandbox can be blocked by Docker's default security profile: **Auto-accept edits**, **Auto**, **Supervised** and **Plan** may fail to run shell tools with a `bwrap` namespace error. This package keeps Docker's security profile enabled. Choose Full access only for projects you trust the agent to work on.

This package adds Node.js 22, npm and npx to Jean's official server image, which includes Git, SSH, curl and GitHub CLI. Start with Jean-managed agent CLIs. Chromium and project-specific build tools are not included; Agent Browser needs additional browser prerequisites. Tools installed only outside the persisted home are lost when the container is replaced. Agent downloads and provider authentication require internet access and your own provider account or API key.

Use Umbrel to update the app. Jean's in-app server updater does not support containers. Project preview servers use additional ports that this package does not publish automatically.

Upstream: [Jean](https://jean.build), [v1.0.13 headless server documentation](https://github.com/coollabsio/jean/blob/v1.0.13/docs/headless-server.md), [runtime Dockerfile](https://github.com/coollabsio/jean/blob/v1.0.13/Dockerfile.server-runtime).
