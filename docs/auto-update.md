# GLSTT Auto Update

GLSTT now includes a built-in macOS updater that mirrors the core Sparkle flow without shipping Sparkle itself:

- poll a hosted update feed
- compare `CFBundleShortVersionString` and `CFBundleVersion`
- download a signed archive over HTTPS
- verify the archive SHA-256
- verify the extracted app's Apple signing team
- hand off replacement to a separate installer process, then relaunch

## Feed Contract

Set `GLSTT_UPDATE_FEED_URL` in the macOS target build settings to a hosted JSON document.

Expected top-level shape:

```json
{
  "updates": [
    {
      "version": "1.1.0",
      "build": "2",
      "minimumSystemVersion": "14.0",
      "archiveURL": "https://downloads.example.com/GLSTT-1.1.0-2.zip",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "notes": "Short, plain-text release notes shown inside the app.",
      "publishedAt": "2026-04-19T16:00:00Z",
      "bundleIdentifier": "com.swiftdev.GLSTT",
      "teamIdentifier": "Z5F6B8QVKJ"
    }
  ]
}
```

## Current Limits

- Archives must be `.zip` files.
- The updater only replaces the app when the current install location is writable.
- This does not implement Sparkle's delta patches, privilege escalation helper, or EdDSA appcast signing.

## Release Process

1. Build and archive a signed macOS `.app`.
2. Zip only the `.app` bundle.
3. Compute the archive SHA-256.
4. Publish the zip over HTTPS.
5. Append the new release entry to the feed JSON.
6. Set `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` so the new build compares correctly.

## Why This Is Structured Like Sparkle

Sparkle's real value is not "download a file." The important pieces are:

- a remote release manifest
- cryptographic verification
- compatibility filtering
- out-of-process installation
- relaunch after replacement

GLSTT now uses the same basic architecture with a smaller, app-specific implementation.
