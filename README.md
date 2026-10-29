# Kevmodrome App Store

Community apps for [umbrelOS](https://umbrel.com), maintained by [kevmodrome](https://github.com/kevmodrome).

## Add this store to Umbrel

1. Open the App Store on your Umbrel.
2. Open the **⋯** menu and choose **Community App Stores**.
3. Paste this repository URL and click **Add**:

   ```text
   https://github.com/kevmodrome/umbrel-community-app-store
   ```

4. Open the **Kevmodrome** store to browse its apps.

## Apps

No apps have been published yet. Jean and Paseo are planned additions; the store will be empty until their packages are added and tested.

## Add an app package

The store ID is `kevmodrome`. Every app directory and its manifest `id` must use the `kevmodrome-` prefix, for example `kevmodrome-jean` or `kevmodrome-paseo`. Keep these IDs stable after publishing.

Each app lives in a top-level directory containing its listing and container configuration:

```text
umbrel-app-store.yml
kevmodrome-<app-name>/
  umbrel-app.yml
  docker-compose.yml
  data/                 # Persistent app state, when needed
```

Use prebuilt, publicly pullable images pinned to tested versions and image digests. Persist app state under `${APP_DATA_DIR}/data`, and verify installation, browser access, agent setup, and persistence across restarts and updates before publishing a package.

See [Umbrel's current packaging guidance](https://github.com/getumbrel/umbrel-apps/blob/master/.agents/skills/umbrel-package-app/SKILL.md) for the app manifest and runtime requirements.

This store was created from [Umbrel's Community App Store template](https://github.com/getumbrel/umbrel-community-app-store).
