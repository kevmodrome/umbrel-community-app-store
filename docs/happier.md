# Happier on Umbrel

This package runs two services: a private Happier relay and a coding machine that runs Happier's daemon, Codex CLI and Claude Code. Control the machine from [Happier's native desktop or mobile app](https://happier.dev). The relay's browser UI is disabled; opening Happier from Umbrel displays its `/health` status response.

## Choose the relay address

The default address is `http://umbrel.local:13005`, using your Umbrel's actual device hostname when different. Your native client must be able to reach this URL. HTTP works on a local network or VPN; use a reachable HTTPS endpoint with a certificate trusted by the client device for remote access. Forward WebSocket upgrades as well as HTTP requests.

Choose a stable address **before pairing**. If `.local` discovery does not work on your phone or you use a VPN, open **Umbrel → Happier → Settings → Environment** and set `HAPPIER_PUBLIC_SERVER_URL` to the full reachable origin, including the scheme and port, for example `http://your-umbrel-name:13005`. This applies the same canonical URL to the relay and runner. The runner continues to reach the relay over the app's private Docker network.

This address identifies the Happier server and appears in pairing links. Use the same canonical URL in all clients. A changed address may require selecting the new server profile and restoring the same account or pairing the machine again. A LAN `.local` name does not automatically work over cellular. No VPN or public ingress is configured by this package.

## Connect and pair the Umbrel machine

1. In the native client, open **Settings → Server → Add Relay**. Enter the relay URL under **Custom Relay URL** and choose **Add and use**. Create a Happier account on this server, or restore your existing account for this server. There is no Umbrel app password or username to enter.
2. In Umbrel, open Happier's **Open Terminal** and select the **runner** service. Run:

   ```sh
   happier auth login --no-open --method mobile --no-daemon-start
   ```

3. Scan the printed QR code with Happier's mobile app, or open the printed native app link on an authenticated device. Approve the pairing. Keep the terminal command running until it confirms success; rerun it if the request expires.
4. The runner waits for its credentials and starts automatically after approval. It may reconnect once automatically during this first pairing. Select the Umbrel machine in your native client and create a project under `/workspace`.

This pairing authenticates the Umbrel machine to **your Happier account**. To use another phone or desktop with that account, use Happier's account/device restore or pairing flow. Creating another account on the same relay produces a separate account with separate encrypted history. Back up your account recovery secret through the native client.

The runner's initial “waiting for authentication” state is expected. After pairing, `happier auth status` and `happier daemon status` in the runner terminal help diagnose its state. A missing online machine can also indicate that a reverse proxy is blocking Socket.IO WebSockets at `/v1/updates/`.

## Sign in to a coding provider

Happier account pairing and coding-provider authentication are separate. After pairing, open a terminal on the **Umbrel machine** from your native client, or use Umbrel's runner terminal. For Codex:

```sh
codex login --device-auth
```

Open the displayed URL in your own browser, sign in, and enter the one-time code. Your account or workspace must permit device-code login. Check with `codex login status`.

For Claude Code:

```sh
claude auth login
```

Complete the displayed login flow in your own browser. Happier's provider settings can also launch provider sign-in on the selected machine after its daemon is online. Signing in on your laptop does not sign into the CLI inside this app. Provider accounts, subscriptions, API access and usage charges are supplied by you.

If Codex reports a Linux sandbox or namespace error in Docker, use its full-access permission mode for projects and commands you trust. Agents run as the non-root app user inside the runner container and can access its selected projects and configured credentials.

## Projects and persistent state

By default, `/workspace` is a persistent projects directory. Clone repositories there from the runner terminal, or create projects through the native client. In **Umbrel → Happier → Settings → Folders**, the optional **Projects** folder mounts existing storage at `/workspace`, replacing the default directory while selected. The selected files must be writable by UID/GID `1000:1000` for edits, Git and worktrees.

The package persists:

- The entire runner `/home/happier`: Happier pairing and machine identity, daemon state, provider credentials, SSH configuration and settings.
- The default `/workspace`: repositories, project files and worktrees created there.
- The entire relay `/data`: SQLite database, local file storage and its generated master secret.

Back up all three app data directories and any separately selected Projects folder. Preserve the relay's `handy-master-secret.txt` with its database. It is generated separately for each installation and reused across restarts; replacing it invalidates authentication tokens and server-managed encrypted secrets. No master secret or provider credential is stored in this repository.

The relay stores end-to-end encrypted session content under its default required-E2EE policy. The runner needs readable files and provider credentials to execute your coding tasks. Select only folders you intend its agents to read and edit. This package grants no access to Umbrel's Docker daemon or other apps' data.

## Access and troubleshooting

Happier uses device-key accounts and Bearer tokens. Native clients cannot carry Umbrel's browser login cookie, so `/v1/*`, `/v2/*`, `/v3/*` and `/files/*` bypass Umbrel SSO and retain Happier's own authentication rules. `/health` and `/ready` are public status endpoints. Other routes retain Umbrel browser login, and the relay serves no web app.

Anonymous **account creation** is enabled by default, as upstream recommends for a private LAN/VPN relay. This permits anyone who can reach the endpoint to create their own account; it does not let them decrypt your account's content. Keep the endpoint private. To close new account signup after creating your account, set relay `AUTH_ANONYMOUS_SIGNUP_ENABLED=false` in an operator-managed Compose override. Existing device-key logins continue to work. For a public multi-user server, configure the upstream GitHub/OIDC signup and eligibility policies before exposing it.

- If the client cannot connect, check the full URL, port `13005`, network reachability and the certificate for HTTPS.
- If a pairing link points to the wrong address, set `HAPPIER_PUBLIC_SERVER_URL` consistently and rerun the pairing command.
- If the relay is healthy but your machine is offline, inspect runner logs and test WebSocket upgrades at `/v1/updates/`. Long-lived connections require appropriate reverse-proxy timeouts.
- If a provider is unavailable, authenticate its CLI inside the runner, then reopen the provider picker.
- If projects are read-only or Git fails, check the Projects folder's ownership and write access.
- App logs are available in Umbrel. `/health` tests process liveness; `/ready` also checks the relay database.

## Image maintenance

Both services use upstream stable source revision `a2c45c86804b24e60ac0b76146a3ef36dfcaa15b`. The relay is the official `happierdev/relay-server:stable-a2c45c86804b`, pinned by its multiarchitecture index digest. The runner is a derived image defined in [`images/happier/Dockerfile`](../images/happier/Dockerfile), adding pinned provider CLIs and an entrypoint that waits for native pairing. Umbrel consumes prebuilt images rather than building them at installation time.

Run the package's [`images/happier/smoke-test.sh`](../images/happier/smoke-test.sh) against the published images before upgrading. It uses disposable state and no real provider login. Review new API versions when updating the native proxy whitelist.

References: [Happier architecture](https://docs.happier.dev/self-hosting/how-it-works), [Docker deployment](https://docs.happier.dev/self-hosting/docker), [server environment variables](https://docs.happier.dev/self-hosting/env), [device-key authentication and signup policy](https://docs.happier.dev/self-hosting/auth), [daemon and headless pairing](https://docs.happier.dev/apps/daemon), and [source for native server settings](https://github.com/happier-dev/happier/blob/a2c45c86804b24e60ac0b76146a3ef36dfcaa15b/apps/ui/sources/components/settings/server/sections/AddTargetsSection.tsx).
