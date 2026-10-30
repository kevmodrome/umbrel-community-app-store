# Jean on Umbrel

1. Install **Jean** from the Kevmodrome store. Copy its app password from Umbrel; this is the server access token, and there is no username.
2. In the Jean desktop app, click the server icon in the title bar, choose **Add remote**, then **Existing URL**. Enter the server URL and access token separately. The direct HTTP endpoint is `http://umbrel.local:13456`; replace the hostname with your Umbrel address when needed. **On recent macOS versions, Jean 1.0.13 can block plain HTTP and show “unreachable”; use trusted HTTPS, such as the Tailscale Serve setup below.** Prefer a desktop version matching server version **1.0.13**.
3. Select that remote server. Jean keeps its desktop interface while projects, terminals and agents run on your Umbrel. Git, Node.js and npm are included, so remote prerequisite checks should pass without installing anything.
4. With the remote selected, install an agent such as Codex or Claude using its **Jean-managed** CLI setup. For GitHub CLI, choose **System PATH** because `gh` is already included.
5. Use the agent's sign-in action in Jean's embedded terminal. For Codex, the headless flow runs `codex login --device-auth`: open the displayed provider URL and enter the device code. Finish provider approval yourself, then return to Jean.
6. Create or clone a repository under `/home/jean/projects` and start a session. For Codex, keep **Full access** selected in the session's permissions menu and use trusted project folders.

The server uses port `13456`. Native-client HTTP APIs and WebSocket connections require the Jean token and can connect without an Umbrel login cookie. Opening the app from Umbrel shows the server's health status; use Jean's native client to work with the server.

The entire `/home/jean` directory persists, including repositories, worktrees, Jean settings, SSH and Git configuration, downloaded agent CLIs, and provider sign-ins. On umbrelOS 2.0, you can select a **Projects** folder in Jean's Umbrel settings; Jean sees it at `/home/jean/projects`. Jean needs write access to that folder to edit code and manage worktrees.

## Connect from a Mac over Tailscale

Jean 1.0.13's macOS webview is subject to App Transport Security. A plain HTTP IP address can fail with error `-1022` even when Tailscale, the server and the access token work. Changing the token does not resolve that transport error. Give Jean a trusted HTTPS endpoint using [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve).

1. In Umbrel, open **Tailscale → Settings → Advanced → Open terminal** and run `tailscale serve status`. Check the existing configuration before choosing an HTTPS port.
2. If HTTPS port 443 is unused, run:

   ```sh
   tailscale serve --bg http://127.0.0.1:13456
   ```

   If port 443 already serves another app, choose an unused HTTPS port instead, for example `tailscale serve --bg --https=8443 http://127.0.0.1:13456`. The Umbrel Tailscale app uses host networking, so `127.0.0.1:13456` reaches Jean's host port.
3. If the command prints a link to enable HTTPS, complete that setup and rerun it. Run `tailscale serve status` again and copy the exact HTTPS URL it prints. `--bg` preserves this configuration across restarts. Serve makes the endpoint available within the tailnet.
4. In Jean, edit the remote's **Web Access URL** to that HTTPS URL and keep the same access token. Omit `:13456`; include the chosen HTTPS port only when it is not 443. Save, then use **Reconnect** if the existing connection still shows its previous error.

The HTTPS hostname must resolve on the Mac. If it does not, check **Use Tailscale DNS settings** in Tailscale's preferences and **MagicDNS** in the tailnet's DNS settings. Test with `dscacheutil -q host -a name <the-hostname-printed-by-Serve>` on macOS. See [Tailscale's DNS troubleshooting guidance](https://tailscale.com/docs/reference/dns-in-tailscale).

**Full access** is Jean's default and allows the agent to use files and commands throughout its container, including any Projects folder you selected. Codex's additional Linux sandbox can be blocked by Docker's default security profile: **Auto-accept edits**, **Auto**, **Supervised** and **Plan** may fail to run shell tools with a `bwrap` namespace error. This package keeps Docker's security profile enabled. Choose Full access only for projects you trust the agent to work on.

This package adds Node.js 22, npm and npx to Jean's official server image, which includes Git, SSH, curl and GitHub CLI. Start with Jean-managed agent CLIs. Chromium and project-specific build tools are not included; Agent Browser needs additional browser prerequisites. Tools installed only outside the persisted home are lost when the container is replaced. Agent downloads and provider authentication require internet access and your own provider account or API key.

Use Umbrel to update the app. Jean's in-app server updater does not support containers. Project preview servers use additional ports that this package does not publish automatically.

Upstream: [Jean](https://jean.build), [v1.0.13 headless server documentation](https://github.com/coollabsio/jean/blob/v1.0.13/docs/headless-server.md), [runtime Dockerfile](https://github.com/coollabsio/jean/blob/v1.0.13/Dockerfile.server-runtime), [Apple App Transport Security rules for IP addresses](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), and [Tailscale Serve CLI reference](https://tailscale.com/docs/reference/tailscale-cli/serve).
