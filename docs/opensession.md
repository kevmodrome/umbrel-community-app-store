# Open Session on Umbrel

Open Session provides a browser workspace for coding sessions. The server and agents run on your Umbrel, with Codex CLI **0.166.0**, Claude Code **2.1.312**, Git, Node.js 22, npm, Bun 1.4.0, GitHub CLI and basic build tools included. You supply your own provider account or API key; no model credential is bundled.

## Start your first session

1. Install **Open Session** from the Kevmodrome store and open it from Umbrel. Sign in to Umbrel when prompted. The browser interface uses Umbrel's app proxy on port **13850**, forwarding to the app's internal port `3850`.
2. During the setup walkthrough, open **Models → Add account**, or later use **Workspace → Providers**, and add a provider:
   - **ChatGPT:** use the in-app device-code sign-in, open the displayed URL in your own browser, and approve the code. This flow does not require SSH or a terminal on your Umbrel. Your account or workspace must allow device-code login.
   - **Claude:** on a trusted machine with Claude Code installed, run `claude setup-token` and complete its sign-in. Paste the resulting setup token into Open Session's Claude account form. The separate Claude sign-in for usage and reset information does not replace this setup token.
   - **API key:** add a supported provider key and choose one of its models.
3. Create or clone a repository under `/workspace`, select it in Open Session, choose an available model, and start a session. Provider sign-in and an actual successful turn are separate checks; a healthy server alone does not verify your provider account.

Keep provider tokens in the app's provider settings. Signing into a CLI on your laptop does not automatically sign into this app. GitHub operations also need your own GitHub authentication; GitHub CLI is included, but no GitHub account is preconfigured.

## Projects and persistent state

The entire `/home/opensession` directory persists, including `~/.opensession` settings, session state, provider credentials, SSH keys and Git configuration. `/workspace` persists repositories, project files and worktrees. Back up both app data directories and any separately selected Projects folder.

The optional **Projects** folder in Umbrel's app settings mounts existing storage at `/workspace`. The selected files must be writable by UID/GID `1000:1000` for agents to edit them and create Git worktrees. Tools installed only outside the persisted directories are lost when the container is replaced.

Agents execute commands inside the app container and can access its project files and configured credentials. This package does not mount Umbrel's Docker socket or provide a host terminal. Project-specific compilers, browsers and build dependencies may require additional setup. Project preview ports are not published automatically.

## Access and updates

Use the browser interface opened from Umbrel. Umbrel login protects the app's UI, API and WebSocket routes; this package does not exempt native-client API paths from that login. A native client that cannot complete Umbrel's browser login needs a separately configured, authenticated ingress compatible with that client. Native-client connections and real provider-account authentication have not been verified by the automated image smoke test.

The app publishes only its browser endpoint through Umbrel's proxy. The session kernel and public integration ingress are not published. For access away from home, use your existing secure access to Umbrel; do not expose the container's internal port as an unauthenticated endpoint.

Use Umbrel to update the app. The package uses a prebuilt Open Session **0.4.82** image pinned by digest. The [image workflow](../.github/workflows/opensession-image.yml) builds AMD64 and ARM64 images and runs the [smoke test](../images/opensession/smoke-test.sh) on both architectures, including replacement of 0.4.79 with saved data. These checks use disposable data and no real provider login. Update the package's image digest only after the image checks pass.

If an integration setting asks for a server restart, restart **Open Session** from Umbrel's app menu. Open Session's own restart button expects systemd or launchd; Umbrel supervises this container instead.

Upstream: [Open Session](https://github.com/tellahq/opensession), [v0.4.82 setup guide](https://github.com/tellahq/opensession/tree/v0.4.82/docs/setup), [provider setup](https://github.com/tellahq/opensession/blob/v0.4.82/docs/setup/install.md#fastest-path-nothing-to-a-first-session), [account pools](https://github.com/tellahq/opensession/blob/v0.4.82/docs/setup/engines.md), and [network trust model](https://github.com/tellahq/opensession/blob/v0.4.82/docs/setup/README.md#trust-model-read-this).
