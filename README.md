# GoToHP for iOS — Gunshot

[English](README.md) · [日本語](README.ja.md)

A Google Photos uploader for jailbreak, sideloading and LiveContainer, using the Go core from [xob0t/gotohp](https://github.com/xob0t/gotohp). Jailbreak builds upload through a separate daemon; jailed builds run inside Google Photos.

**Development build.** Automatically selects compatible legacy or modern native APIs **per feature**, without a version-number allowlist. The IPA-audited reference versions are **6.72.0 (iOS 15.0+)**, **7.20.2 (iOS 16.1+)** and **7.92.0 (iOS 18.0+)**. Other releases can work when their APIs match; this is not a claim of device verification. See the compatibility audits for [6.72.0](docs/analysis/google-photos-6.72.0.md) and [7.20.2](docs/analysis/google-photos-7.20.2.md).

## Screenshots

<p>
  <img src="docs/images/unlimited-storage.png" width="240" alt="Google Photos profile menu showing the native Unlimited storage card">
  <img src="docs/images/profile-menu.png" width="240" alt="GoToHP settings entry in the Google Photos profile menu">
</p>
<p>
  <img src="docs/images/upload-settings.png" width="240" alt="Signed-in account and original-quality Pixel 1 upload settings">
  <img src="docs/images/backup-routing.png" width="240" alt="Manual and automatic backup routing and queue management settings">
  <img src="docs/images/appearance-settings.png" width="240" alt="Language and Show unlimited storage settings">
</p>

## Disclaimer

An unofficial project unaffiliated with Google or Apple, provided **as is, without warranty**. Private APIs and app updates may break functionality or lead to account restrictions, data loss or storage charges. Keep a separate backup of your originals. Google Photos binaries, signing certificates and credentials are not distributed here.

## Install and use

> [!IMPORTANT]
> **Install and enable the tweak before Google sign-in.** For sideloading, inject **GunshotJailed** into the IPA first. It corrects the re-signed app identifier within compatible Google Photos SSO APIs and handles missing shared-Keychain access automatically. No separate Sideload Spoofer is required for these corrections. Device sign-in verification is still pending.
>
> 1. Install/enable the jailbreak tweak, or install Google Photos from an IPA with **GunshotJailed** injected. In LiveContainer, import the dylib and enable it for the Google Photos guest before launching.
> 2. Open **Google Photos** with the tweak enabled and sign in to your Google account. When updating an existing installation, preserve the **signing account, bundle identifier and app data**, or the **same guest/data container** in LiveContainer.
> 3. GoToHP automatically connects the signed-in account once native sign-in is ready. Use **Profile menu → GoToHP settings** to change upload settings or retry with **Reconnect**.
>
> Do not delete the logged-in app/guest or create a new data container. Session retention is not guaranteed, including when moving from the App Store version to a separately signed app. See the [installation guide](docs/jailed.md).

### Sideloading / LiveContainer

Get `gotohp-tweak-jailed` from [GitHub Actions](https://github.com/tqmane/gunshot/actions): it contains the `.deb`, `GunshotJailed.dylib` and notices. Use the [installation guide](docs/jailed.md) to inject the package or import the dylib into LiveContainer.

GoToHP automatically connects the signed-in account when Google Photos opens; opening GoToHP settings is not required. Choose **Uploads → Choose photos and videos** to upload. **Keep Google Photos in the foreground**; jailed uploads cannot continue after the app closes.

On jailed Google Photos with compatible native APIs, **Route manual and automatic backups through GoToHP** is off by default. Enable it and confirm the destination to route supported backup actions without opening GoToHP. Automatic backup also requires backup to be on in Google Photos. See [supported routes](docs/analysis/backup-routing.md) and [remaining coverage gaps](docs/native-routing.md).

### Jailbreak

Install the `gotohp-tweak-rootless` or `gotohp-tweak-rootful` `.deb` from GitHub Actions with your package manager. libSandy 1.1.6 or later ([opa334’s repository](https://opa334.github.io/)) and a substrate-compatible injection system are required. Install with a package manager so it resolves these dependencies. The package includes a restricted libSandy profile for the GoToHP daemon; libSandy itself is installed as a shared system dependency. **If Google Photos crashes, use Choicy to enable only Gunshot for Google Photos.**

Opening **Google Photos** automatically connects the account already signed into the app. No token paste or visit to GoToHP settings is required. Use **Profile menu → GoToHP settings** to change options or retry with **Reconnect**. Jailbreak packages do not add an iOS Settings entry or require PreferenceLoader. Upload from this page, the Apple Photos GoToHP button or a supported **Upload with GoToHP** share action.

**Route manual and automatic backups through GoToHP** is also available on jailbreak builds, including the audited 7.20.2 APIs. Enable it once in GoToHP settings and confirm the destination; native backup buttons then enqueue silently, and automatic backup works when Google Photos backup is on. After a committed upload, the app requests its own server sync without opening settings or restarting. [Routing and completion details](docs/analysis/backup-routing.md).

Keep Google Photos open until media reaches the queue. The daemon can continue using its in-memory authorization after the app closes. Native authorization is refreshed by Google Photos while it runs; the daemon retains each bearer for at most five minutes. When authorization is unavailable or the daemon restarts, pending jobs wait for Google Photos to reopen and refresh it without consuming retries. This does not provide indefinite authentication refresh while the host is closed. [Authentication details](docs/analysis/native-account.md).

## Quality and queue

For bulk imports, open **GoToHP settings → Uploads → Choose album**. Browse folders to an album, then add all accessible photos and videos. This avoids loading thousands of selections through the system photo picker. **Choose photos and videos** accepts up to 100 items per selection. If that picker shows **Unable to Load Items**, cancel it and use **Choose album**.

Originals are prepared one at a time. Keep the app open during preparation; **Stop preparing** stops after the current item and keeps jobs already queued. An unreadable photo is counted as failed while the remaining selection continues. Check photo permissions and iCloud availability before retrying it. See [bulk import and HEIC troubleshooting](docs/bulk-import.md).

| Setting | Device profile / requested behavior |
| --- | --- |
| Original | Pixel XL (Pixel 1), original quality without storage usage |
| Storage saver | Pixel 2, storage saver |
| Account storage | Pixel 8, original quality using normal quota |

These are requests, not guarantees. Verify original-data availability and Google storage usage separately; a successful upload does not establish quota treatment. Account and quality are fixed when each item is queued; changing settings does not alter existing jobs.

PhotoKit uploads use original resources without re-encoding, including both Live Photo components. The queue supports progress, retry, cancellation and restart recovery. Retries restart the file transfer. An interrupted commit with an unknown outcome needs manual review/retry and may produce duplicates. Cancellation does not delete media already saved in Google Photos.

Under **GoToHP settings → Queue management**, you can manage queued and completed jobs:
- **Retry failed uploads**: Resets retry counts and re-enqueues all failed items.
- **Clear failed uploads**: Removes failed items and deletes their staged files on disk.
- **Clear completed history**: Removes completed and cancelled items from upload history.
- **Clear all tasks**: Cancels any in-flight uploads, purges all pending and historical jobs, and removes all staging data.

## Languages

English and Japanese are included. Choose **GoToHP settings → Appearance → Language**; unsupported device languages fall back to English. No separate translation bundle is needed. [Add translations](docs/localization.md).

## Build

Requires macOS, Xcode command line tools, Go 1.26.0, Theos, `ldid` and `dpkg`.

```sh
git clone --recurse-submodules https://github.com/tqmane/gunshot.git
cd gunshot
export THEOS="$HOME/theos"
bash scripts/package.sh jailed  # or rootless / rootful
```

Run the local checks:

```sh
python3 scripts/localization.py --check
python3 scripts/prepare-core.py
go test -race -tags cli ./...
go test -tags cli app/backend
go vet -tags cli ./...
```

CI runs tests and builds all three packages. Successful `v*` tags publish release assets. To update the pinned upstream, run `bash scripts/sync-upstream.sh [commit]`; keep its license and generated notices with distributions.

If a release already exists, CI uploads the built assets to it, replacing assets with the same names while preserving its title and notes. To recover publication for an existing tag (for example `v0.2.1`), select **Actions → Build and test → Run workflow**, choose `main`, and enter that tag in **release_tag**. The updated workflow builds and tests the tag's source, then uploads its packages; it does not move the tag. Leaving **release_tag** empty runs a build only. Re-running an old failed job uses its old workflow, so use **Run workflow** for this recovery.

## License

Gunshot is licensed under [GNU GPL v3.0 or later](LICENSE).
Copyright (C) 2026 tqmane.

The bundled [gotohp upstream](GotohpCore/upstream/LICENSE) remains MIT-licensed,
Copyright (c) 2024 xob0t. Other third-party components retain their own licenses.
Distribution packages include these notices in `ThirdPartyNotices.txt`.

## Development docs

- [Architecture, credentials and upstream integration](docs/architecture.md)
- [Google Photos analysis](docs/analysis/index.md) (Japanese)
- [Device validation](docs/device-validation.md)
