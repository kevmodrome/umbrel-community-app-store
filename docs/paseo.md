# Paseo on Umbrel

This package runs the Paseo server on Umbrel for its [desktop and mobile clients](https://paseo.sh/download). In your client, open **Settings → Add host → Direct connection** and enter:

- **Host:** your Umbrel's hostname or IP address, without `http://`, `https://`, a path, or a port.
- **Port:** `16767`, replacing the form's default `6767`.
- **Use SSL:** enable it for the Umbrel HTTPS endpoint; leave it disabled for HTTP on your local network or VPN. HTTPS needs a certificate trusted by the client device.
- **Password:** the app password displayed by Umbrel. There is no username.

The server's bundled web UI is disabled. Opening Paseo from the Umbrel home screen displays its `/api/health` status response. Projects, terminals, and agents are managed from your Paseo client.

The image includes Paseo **0.14.0**, Codex CLI **0.166.0**, and Claude Code **2.1.312**. The daemon and agents run inside the container as the `paseo` user, UID/GID `1000:1000`.

## Sign in to a coding provider

Connect your desktop or mobile client, create or open a project under `/workspace`, then open its built-in **Terminal**. This terminal runs inside the Umbrel app container. Authenticate at least one provider before launching an agent:

```sh
codex login --device-auth
```

Open the displayed URL in your own browser, sign in, and enter the one-time code. Your ChatGPT account or workspace must permit device-code login. Check the result with `codex login status`.

For Claude Code, run:

```sh
claude
```

Complete its first-run setup and open the login URL in your own browser. Paste the login code into the terminal if prompted. You can also start its sign-in flow with `claude auth login`.

Select the authenticated provider when creating an agent in Paseo. Provider subscriptions, API access, and usage charges are managed by the provider. Signing into a CLI on your laptop does not sign into the copy inside this app.

### Codex permissions in Docker

Paseo's **Default Permissions** and **Auto-review** Codex modes use Codex's Linux sandbox. Docker environments that block nested user namespaces can reject shell tools with a bubblewrap or namespace permission error. If this happens, select **Full Access** in the Codex agent's permissions menu.

Full Access permits commands, file edits, and network access without additional Codex approval prompts. The agent still runs as UID `1000` inside the app's Docker container, with access to its mounted projects and configured credentials. Choose this mode only for projects and commands you trust. The package keeps Docker's normal security settings.

## Projects and persistent state

By default, `/workspace` is the app's persistent projects folder. Clone repositories there from the client's terminal, or create projects through the client. In **Umbrel → Paseo → Settings → Folders**, the optional **Projects** folder lets you select existing storage. The selected folder appears at `/workspace`, replacing the default folder while selected. Its files must be writable by UID/GID `1000:1000` for edits and Git worktrees.

The entire `/home/paseo` directory persists, including Paseo configuration and history, its identity, provider credentials, SSH configuration, and agent settings. The default `/workspace` also persists. Back up both app data directories, and back up any separately selected Projects folder through your normal storage backup process.

Agents can use the files and credentials accessible inside this container. Only select project folders you intend them to read and edit. This package grants no access to Umbrel's Docker daemon or other apps' data.

The image includes the upstream Node.js 22 runtime, npm, Bash, Git, curl, and SSH client. Projects needing other language runtimes, compilers, browsers, or system packages require an appropriate custom image; installations made outside the persistent home and workspace disappear when the container is replaced.

## Connections and troubleshooting

Native clients connect to the daemon's `/ws` WebSocket endpoint and `/api/*` HTTP endpoints through Umbrel's app proxy on port `16767`. These exact routes bypass Umbrel's browser login because clients cannot send that login session. Paseo's generated app password still protects daemon control; `/api/health` is an unauthenticated health check. Other app routes retain Umbrel login.

The package allows the Umbrel device hostname and `.local` domain; IP addresses and localhost are accepted by Paseo itself. Add a custom DNS name to Paseo's `daemon.hostnames` configuration before using it. Upstream appends this hostname list to the deployment's allowed names. The packaged desktop client's `paseo://app` origin and native requests without a browser origin are supported by Paseo without widening CORS settings.

The outbound Paseo relay is disabled by deployment configuration. Changing it in the client does not override this package setting. For access away from home, use an existing VPN or a reachable endpoint with trusted HTTPS. A client cannot complete an Umbrel browser-login redirect or use a URL subpath for its daemon connection.

- If connection fails, check Host, port `16767`, SSL, and the password displayed by Umbrel. The client needs to reach your Umbrel on that port.
- If SSL fails, confirm that the endpoint serves HTTPS and the client device trusts its certificate. Accepting a certificate exception in a browser does not establish native-client trust.
- If a provider is unavailable, complete its login in Paseo's terminal and reopen the provider picker.
- If a project reports permission errors, check the selected Projects folder's ownership and write access.
- View app logs in Umbrel for startup errors. Paseo also stores its daemon log under `/home/paseo/.paseo/daemon.log`.

## Image maintenance

The derived image is built from the official multiarchitecture `ghcr.io/getpaseo/paseo:0.14.0` image, pinned in [`images/paseo/Dockerfile`](../images/paseo/Dockerfile). It adds the two pinned agent CLIs and retains the upstream entrypoint, privilege drop, and `/api/health` healthcheck. The package consumes a prebuilt image; Umbrel does not build it during installation.

Run `bash images/paseo/smoke-test.sh IMAGE` against the published image to check the headless API, disabled web UI, HTTP and native WebSocket password enforcement, host validation, CLI execution as the non-root user, and home/workspace persistence across container replacement. The test uses disposable Docker volumes and does not sign into providers.

References: [Paseo native connectivity](https://github.com/getpaseo/paseo/blob/v0.14.0/public-docs/connectivity.md), [Paseo Docker deployment](https://github.com/getpaseo/paseo/blob/v0.14.0/docs/docker.md), [Paseo security model](https://github.com/getpaseo/paseo/blob/v0.14.0/SECURITY.md), [Paseo configuration](https://github.com/getpaseo/paseo/blob/v0.14.0/public-docs/configuration.md), [Codex headless authentication](https://developers.openai.com/codex/auth), and [Claude Code authentication](https://code.claude.com/docs/en/authentication).
