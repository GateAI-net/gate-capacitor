# Gate/AI Capacitor SDK

Native Gate/AI authentication and proxy requests for iOS and Android.

## Local installation

From this directory run `npm ci && npm pack`, then install the resulting tarball in your app:

```sh
npm install /absolute/path/to/gateai-capacitor-0.1.0.tgz
npx cap sync
```

Rebuild the native app after syncing. Capacitor 7 and 8 are declared peer versions; development uses Capacitor 8. CocoaPods supports both, and `Package.swift` targets Capacitor 8 for Swift Package Manager integration. The browser/PWA target explicitly rejects initialization because device attestation requires a native app.

## Usage

```ts
import { GateAIClient, GateAIError } from '@gateai/capacitor';

const client = await GateAIClient.create({
  baseUrl: 'https://yourteam.in.gate-ai.net',
  ios: { teamIdentifier: 'ABCDE12345' },
  android: {
    signingCertSha256: 'YOUR_64_HEX_CHARACTER_SIGNING_CERTIFICATE_SHA256',
    cloudProjectNumber: '123456789012',
  },
});

try {
  const response = await client.request({
    path: 'openai/chat/completions',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'your-enabled-model',
      messages: [{ role: 'user', content: 'Hello' }],
    }),
    context: { userTier: 'pro', appFeature: 'chat', quotaAnchorDay: 15 },
  });
  const completion = JSON.parse(response.body);
} catch (error) {
  if (error instanceof GateAIError && error.status === 429) {
    const retryAfter = error.header('Retry-After');
  }
  throw error;
}

// When the owning screen/service is permanently torn down:
await client.dispose();
```

## Native setup

- iOS 16+, Xcode 16+, and an Apple Team ID. Enable App Attest for the app identifier and add the `com.apple.developer.devicecheck.appattest-environment` entitlement. Configure the matching bundle ID and team in the Gate/AI portal. Physical devices use App Attest; simulators use `GATE_AI_DEV_TOKEN` set in the Xcode Run scheme's environment. An iOS development token is intentionally not accepted through JavaScript or Dart.
- Android API 24+, Java 17 or the higher version required by your framework, and Kotlin 2.0.20+. Register the application package and signing certificate SHA-256 in the portal; configure Play Integrity and supply the linked Google Cloud project number as a **decimal string**. Debug builds automatically read the host app’s `gate_ai_dev_token` resource; configure it using the steps below. Device identifier analytics are opt-in (`deviceIdentifierEnabled`, default false).
- Supply configuration for both platforms in a shared app. Only the current platform's native settings are used. Never embed provider API keys. Use opaque IDs for `userIdentifier`.

## Requests and errors

`request` buffers UTF-8 text and JSON responses and returns `{status, headers, body}`. It supports GET and POST. Serialize JSON explicitly and set `Content-Type: application/json`. Paths are relative to the configured HTTPS origin, for example `openai/chat/completions`; full URLs, query strings, fragments, percent escapes, and dot segments are rejected. Binary bodies, streaming events, and cancellation are not part of this first version.

Authentication, token refresh, device keys, and one retry on a DPoP nonce challenge are handled by the native SDK. Non-2xx responses throw a typed error with `status`, `headers`, and `body`; network/attestation failures have a code and message. Response headers preserve quota and retry information, including `X-Quota-*` and `Retry-After`. Error codes from platform attestation may differ between iOS and Android; use `status` for HTTP decisions.

`authorizationHeaders` supports custom HTTP transports. Use the configured base URL plus the exact path and method used to request the proof. Do not reuse proofs or send them to other origins. Handle a 401 with a `DPoP-Nonce` header by requesting a new proof with that nonce and retrying once. This low-level API does not perform the HTTP request.

Analytics are per request through `context`: `userStatus`, `userTier`, `userIdentifier`, `appFeature`, and `quotaAnchorDay` (1–31). Explicit headers override context values case-insensitively. Authorization, DPoP, Host, Content-Length, and Connection headers are managed by the SDK and cannot be overridden.

`clearCachedState` clears the access-token cache. `dispose` releases the native client; requests already in flight can finish. These methods do not delete device or App Attest keys. Each client has independent token state; reuse a client instead of creating one per request.

## Development and release status

This is an initial, unpublished SDK. Sample apps are intentionally deferred until the shared sample UI is updated. Install from this checkout using the instructions above. Package/repository names are provisional; no npm, pub.dev, or public mirror release has been made.

The package includes snapshots of the existing Gate/AI Swift and Kotlin SDKs plus a thin native bridge. This makes local installation self-contained and keeps device security in native code. Do not edit `ios/Core`, `native/android`, or generated `src/client.ts` directly. From the monorepo root run:

```sh
python3 sdks/scripts/sync-mobile-sdks.py
python3 sdks/scripts/sync-mobile-sdks.py --check
```

The canonical bridge and JavaScript API live in `sdks/mobile-core`. The source manifest in `native/sources.json` records hashes. Do not install the standalone Android Gate/AI SDK alongside this package because its classes are already bundled.

## Android development tokens

Use a development token when testing in an Android emulator. The development token lets your emulator app authenticate with Gate/AI without using Google Play Integrity. This applies to native Android, React Native, Capacitor, and Flutter apps.

Create a development token for your gate in the portal, follow the setup below, then rebuild and reinstall your debug app. You do not need to pass the token in application code:

1. Set `GATE_AI_DEV_TOKEN` in the environment of the Gradle build, or create `gateai.local.properties` in the **Android Gradle root** (next to `settings.gradle` / `settings.gradle.kts`). For framework apps this is usually the app's `android/` directory.
2. Add `gateai.local.properties` to your `.gitignore`. In that local file, set `GATE_AI_DEV_TOKEN=your-token` without quotes. An environment variable takes precedence, including an explicitly empty value.
3. Add the following configuration to the **host app module's** build file, merging it into any existing `android` / `buildTypes` blocks. Do not put it in the SDK library's build file or `defaultConfig`.

```groovy
// app/build.gradle — place after plugins { ... }
def gateAILocalProperties = new Properties()
def gateAILocalFile = rootProject.file("gateai.local.properties")
if (gateAILocalFile.exists()) {
    gateAILocalFile.withInputStream { gateAILocalProperties.load(it) }
}
def gateAIDevToken = providers.environmentVariable("GATE_AI_DEV_TOKEN")
    .orElse(gateAILocalProperties.getProperty("GATE_AI_DEV_TOKEN", ""))

android {
    buildTypes {
        debug {
            resValue "string", "gate_ai_dev_token", gateAIDevToken.get()
        }
    }
}
```

Sync Gradle, then rebuild and reinstall the debug app whenever the token changes. Android Studio builds must see the environment variable in the IDE's process; use the ignored local file if you normally launch the IDE from the Dock or launcher.

The native SDK automatically reads the `gate_ai_dev_token` string resource. No token argument is needed in Kotlin, JavaScript, or Dart. If no token is configured, the SDK asks Google Play Integrity to verify the app and device instead. Explicit `developmentToken` configuration remains supported in debug apps and takes precedence over the resource.

Keep the resource confined to the debug build type. This setup includes the token in the debug APK, but excludes it from release APKs/AABs. The SDK also ignores all development tokens in non-debuggable apps. Use the normal production Play Integrity setup for release builds; development tokens bypass attestation and should not be distributed.

See the [Android development token guide](https://portal.gate-ai.net/docs/android#android-dev-token) for both Kotlin DSL and Groovy examples. iOS continues to use `GATE_AI_DEV_TOKEN` in the Xcode Run scheme; see the [iOS simulator setup](https://portal.gate-ai.net/docs/ios#dev-mode).
