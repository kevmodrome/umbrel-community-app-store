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


## Opt-in Tailscale Runner ingress (candidate image 0.4.82-2)

This section describes the candidate image, **not the currently pinned
`0.4.82-1` package**. Preparing this change does not publish a release, change
registry visibility, update the installed app or pair a real Runner. After
review, build/test the image, explicitly authorize promotion, and update the
app's immutable image digest and release notes before enabling this endpoint.
Do not replace the digest with a mutable `latest` tag.

### Why a separate ingress is necessary

Umbrel's browser proxy forwards to a different container. Open Session 0.4.82
admits Runner registration, heartbeats and its control WebSocket only when it
can establish a Tailscale source. It accepts forwarded-origin evidence only
from a loopback peer. Consequently the old browser route cannot pair a Runner,
and setting `trustForwardedFor` alone is not a safe fix.

The candidate supervises a non-root Caddy proxy alongside the server:

| Listener inside the app | Access |
| --- | --- |
| `3850` | Existing Umbrel-authenticated browser route; Runner transport paths rejected |
| `3851` | Opt-in Runner-only ingress; actual TCP peer must be `100.64.0.0/10` |
| `127.0.0.1:13852` | Private application backend, never published |

The proxy overwrites `X-Forwarded-For` from the actual socket peer, strips
other origin assertions, and forwards over loopback. The launcher forces the
backend host/port and forwarded-header trust together, overriding stale
settings or environment values. Its admin API is disabled. A dead proxy or
server stops the container so Umbrel can restart it.

The Runner listener allows only `/api/runners/register`,
`/api/runners/heartbeat` and `/runner-ws`. Upstream single-use pairing codes
and bearer-token authentication still apply. The UI, pair-code creation,
settings, browser terminals and every other route are unavailable there.
No Runner port is published by the default app compose file.

### Enable after the tested image is pinned

1. Back up the app's persisted home and workspace. Keep these backups private:
   they contain provider credentials as well as project state.
2. On the **Umbrel host**, find the installed app's
   `kevmodrome-opensession/docker-compose.yml` under its app-data directory.
   Under the existing `server:` service, add this port mapping, replacing the
   example IP with **Umbrel's own Tailscale IPv4**, not the Ubuntu VM's IP:

   ```yaml
   ports:
     - "100.64.12.34:13851:3851/tcp"
   ```

   Leave `app_proxy`, its authentication, and its target port `3850` unchanged.
   Do not bind to `0.0.0.0`, your LAN address or a public address. Do not publish
   backend `13852`, the session kernel, or the proxy admin port. An unavailable
   Tailscale interface should fail closed; never add a wildcard fallback.
3. Restart Open Session using Umbrel so it recreates the container with the
   new mapping. Recheck the actual mapping with `docker port` or `docker
   inspect` on the host: only the chosen Tailscale IP may expose `13851`.
   Compose changes may be replaced by app updates; review/reapply this opt-in
   mapping after updates rather than assuming it persists.
4. From a machine on the same tailnet, request
   `http://<umbrel-tailscale-ip>:13851/`. Expect **404** (no UI bypass).
   A LAN-only client must not be able to connect. If the Runner listener says
   it requires a Tailscale source, the network path is still translating the
   source address: fix that path, **do not weaken the source check or invent
   forwarding headers**.
5. Create a fresh pairing code in Open Session's Runner settings, then on
   Ubuntu run:

   ```sh
   opensession connect --server http://<umbrel-tailscale-ip>:13851 --code <new-code>
   ```

   Verify the Runner becomes online, a bounded command succeeds, and its
   reconnecting service is active. On Linux, enable lingering for the service
   user if the Runner must return without a login after reboot:
   `sudo loginctl enable-linger "$USER"`. A successful initial pairing does not
   prove reboot recovery; test that separately.

The Ubuntu VM can stay in **Private** network mode. Runner traffic is outbound
through Tailscale; no Ubuntu port forwarding, SSH access or public exposure is
needed. HTTP on this dedicated address is carried inside Tailscale's encrypted
network; do not turn it into a public HTTP endpoint.

### Validation and rollback

The read-only pull-request workflow builds AMD64 and ARM64 candidates without
publishing them, tests real Caddy header handling, existing browser/terminal
behavior and persistence, and upgrades persisted state from `0.4.82-1`. Its
isolated Docker network supplies fixture socket addresses in the CGNAT range
for registration, heartbeat and authenticated WebSocket tests. This is not a
real Tailscale login or proof that a production ingress preserves source IPs.
It also rejects non-tailnet peers and forged forwarding headers, checks that
the backend is loopback-only, and kills the proxy to test failure propagation.

To roll back, remove the opt-in port mapping, restore the previously reviewed
image digest and recreate the app through Umbrel. Keep persisted app data.
Revoking a paired Runner in Open Session is separate from closing its ingress.
