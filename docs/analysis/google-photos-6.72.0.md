# Google Photos 6.72.0 compatibility audit

The supplied **Google Photos 6.72.0**, build **6.72.608184154**, joins **7.20.2** and **7.92.0** as an IPA-audited reference version. Adapters are selected per feature from the actual classes, selectors and exact Objective-C signatures, without a version-number gate. Authentication, completion callbacks, storage UI and quality UI independently use the compatible legacy API paths. Device validation is still required; binary audits and mocked contracts do not establish successful authentication or uploads against Google's servers.

## Input and OS requirements

The supplied IPA contains `GooglePhotos` and `Frameworks/ModuleFramework.framework/ModuleFramework`, both decrypted (`cryptid = 0`), thin arm64 images. Their `LC_BUILD_VERSION` declares **iOS 15.0**, SDK 17.2. Both `Info.plist` and Mach-O declare `MinimumOSVersion = 15.0`. This makes 6.72.0 the primary audited release for **iOS 15** jailbreak (Dopamine / XinaA15), TrollStore and sideload environments.

The main image yielded 6,470 classes / 68,963 instance methods; ModuleFramework yielded 14,573 / 82,924. [The scoped contract manifest](objc/6.72.0-contracts.json) records SHA-256 hashes and the selectors, encodings, and static addresses relevant to this adapter. The IPA and executable bytes are not distributed in this repository.

## Audited differences

| Integration | 6.72.0 | 7.20.2 | 7.92.0 |
| --- | --- | --- | --- |
| Minimum OS | **iOS 15.0** (SDK 17.2) | iOS 16.1 (SDK 17.5) | iOS 18.0 (SDK 18.0) |
| Native account | `PHSAccountManagerImpl.ssoService` → `SSOService.authorizationForIdentity:scopes:` | Same legacy ABI | `photosSSOService` → `fetcherAuthorizerForAccountID:scopes:` |
| Authorization callback | `authorizeRequest:completionHandler:` (`v32@0:8@16@?24`) | Same ABI | Same ABI |
| Asset completion | `didCompleteWithSuccess:resultantMediaItem:errorCode:` (`v36@0:8B16@20q28`) | Same ABI | `…error:` with object argument (`v36@0:8B16@20@28`) |
| Live Photo completion | `didCompleteWithError:resultantMediaItem:` | Same ABI | Same ABI |
| Unlimited card | Model `storageState`, native UIKit cell title; no model `title` getter | Same legacy ABI | Model `storageState` + `title`, including Swift/Bento reads |
| Unlimited localized resource | `OneGoogleStorageCardUnlimitedSubtitle`, ID **0x78** | `OneGoogleStorageCardUnlimitedTitle`, ID **0x79** | Same key as 7.20.2, ID **0x81** |
| Backup detail display | `modelForBackedupStatus` → inherited content-model factory | Same legacy ABI | `getBackupStatusModelData` → `PHSOneUpInfoPanelBackupStatusData` |
| Native library refresh | `PHSUserItemsSynchronizer.fetchData` / `fetchDataSoft` | Same ABI | Same ABI |
| Settings/menu and manual action | Existing custom-section/action and `backupLocalAssets:` signatures | Same ABI | Same ABI |
| Liquid Glass bottom bar | Inactive (`requires_photos_7_92`) | Inactive (`requires_photos_7_92`) | Supported on iOS 26+ |

### Authentication

`SSOService.authorizationForIdentity:scopes:` at ModuleFramework `0xfb0e34` uses the identity's user ID and sorted scopes for its authorization cache and constructs `SSOAuthorizationImpl` (`authorizeRequest:completionHandler:` at `0xf9edac`). `PHSAccountManagerImpl.viewingAccount` at `0x80f664` and `ssoService` at `0x80f654` provide the active account and SSO service. The adapter passes the currently viewed account's valid `_ssoIdentity` and `photos.native` scope. Native SSO retains ownership of refresh and Keychain access.

**Sign in before injecting.** First open Google Photos without the tweak and complete Google login; then install the tweak or update to the injected IPA while preserving the same app data and signing identity.

### Backup handoff and completion

`GMUAssetUploadRequest` inherits `cancel` from `GMUUploadRequest` and implements `start`, `shouldTimeout`, and `didCompleteWithSuccess:resultantMediaItem:errorCode:` (`v36@0:8B16@20q28`). `GMULivePhotoSingleUploadRequest` uses `didCompleteWithError:resultantMediaItem:` (`v32@0:8@16@24`). The legacy base completion forwards the integer error code with `BOOL` success. Hook blocks and calls use `NSInteger` error codes for this version.

6.72.0 has no Swift `ScottyUploadServiceImpl` class. The shared `GMUUploadRequest.startFetcher` and `GMUUploadMediaRequest.startCNDEUpload` payload guards remain active. Edited Live Photo data is handed to a native data-upload request in `beginUploadEditedBytesWithFingerprint:data:`. Both jailbreak and jailed modes install the common request hooks; the shared completion monitor requests native library sync via `PHSUserItemsSynchronizer.fetchData`.

`PHSUserItemsSynchronizer` inherits `accountID` via `PHSSynchronizer` → `PHSBaseComponentAnyAccountID` → `PHSBaseWithAnyAccountID` → `PHSBaseWithAccountID`. The synchronizer capture and refresh dispatch work identically to 7.20.2.

### Native unlimited display

`OGLAccountSelectorStorageCardCell` at `0x1a7778` uses `updateWithItem:`. The class method `titleTextWithStorageItem:` at `0x1a834c` builds the title text. In 6.72.0, the `OneGoogle` string table has not yet split into separate unlimited title and subtitle keys: `OneGoogleStorageCardUnlimitedSubtitle` is index **0x78** in `OGLStringResources` (table at `0x5bda898`), resolving to `"Unlimited"` (or localized equivalents: `"無制限"`, `"Unbegrenzt"`, `"Illimité"`, `"无限"`).

The adapter resolves `OGLBundle.oneGoogleResourceBundle` and checks `OneGoogleStorageCardUnlimitedTitle`, falling back to `OneGoogleStorageCardUnlimitedSubtitle` when the former is absent. This preserves the native localized title without hardcoding strings or static numeric IDs.

### Original-quality label and refresh

At main `0x10058b574`, `modelForBackedupStatus` builds the title, quality subtitle, native icon, and action through `contentViewModelWithTitle:subtitle:subtitleContainsHTML:image:` on superclass `PHSOneUpInfoPanelSectionViewController` (`0x100594c34`). The adapter overrides this inherited factory on `PHSOneUpInfoPanelDetailsViewController` only, scoped to that controller's backup-status call.

`PHSServerPhoto.storagePolicy` has type encoding `i16@0:8` (32-bit int) in 6.72.0, compared to `C16@0:8` (unsigned char) in 7.20.2 and 7.92.0. The adapter supports both encodings for the diagnostic read and optional policy hook.
