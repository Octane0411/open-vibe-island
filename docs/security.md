# Security boundaries and phone pairing

## Desktop use

Phone/Watch notifications remain off by default. Desktop hooks use a Unix socket and do not need SSH or a TCP listener. The app still has the current user's normal macOS access to coding-tool transcripts, processes, and terminal automation; it is not an App Sandbox boundary against malicious software running as that user.

The bridge directory is mode 0700 and its sockets are mode 0600. Accepted peers must have the app's effective user ID. Neither ordinary hook connections nor self-registered observers can submit permission decisions or question answers. These actions enter through `BridgeServer.performUserAction` from the app, including its authenticated phone callbacks. Observers can still read session events, and hooks can submit their supported events. Forwarding the socket to a remote environment grants that environment this hook/observer access.

Completion Markdown uses inert placeholders for both block and inline images. It never automatically fetches their URLs. Links still open when the user chooses them. The bundled OpenCode plugin no longer writes event payloads to a debug file.

## Phone and Watch without SSH

1. Install matching Mac and iPhone versions with the secure transport.
2. Connect them to the same trusted Wi-Fi network. Leave macOS Remote Login off; no SSH service or router port forwarding is needed.
3. Enable Watch Notifications in Mac settings, then choose **Pair New Device**.
4. Copy the pairing key and paste it into the iPhone app after selecting the Mac (or entering its address and port).
5. Choose **Revoke All Pairings** on the Mac to disconnect every phone and invalidate all keys and tokens.

Only clicking Pair New Device opens pairing. Each key works once, expires after two minutes, and closes after five unsuccessful secret submissions. Merely viewing settings or making an expired request does not reopen it. A paired phone can read events and submit decisions, so share the key only with a device you trust.

The Mac advertises `_openisland2._tcp` through Bonjour on a dynamically assigned port. Discovery metadata (such as the Mac name and port) is visible on the LAN. Pairing, event streams, status and actions all use Network.framework TLS with a random 256-bit pre-shared key. The only enabled cipher is TLS 1.2 `TLS_PSK_WITH_AES_128_GCM_SHA256`; there is no plaintext or certificate-validation fallback. This authenticates both peers and encrypts application traffic. This PSK suite does not provide forward secrecy: protecting the pairing key remains necessary after use. The platform's typed cipher API omits PSK suites, so the shared transport uses Apple's older PSK cipher API.

Pairing carries an additional random one-use secret inside TLS, then issues a separate random bearer token. Request parsing has header/body limits, connection deadlines and a 32-connection cap. The iPhone stores the key and token in its device-only Keychain. Mac credentials are memory-only: stopping the feature, restarting the Mac app, or revoking pairings requires pairing again. Revocation closes existing event streams and rotates the TLS key.

Old four-digit clients and UserDefaults tokens are deliberately incompatible. Update both apps and pair again. An old client will not discover the new service. After upgrading the OpenCode plugin, restart OpenCode to load it. Older versions may have left `/tmp/open-island-opencode-debug.log`; review and remove that file if it exists and is no longer needed.

## Dependencies and release tools

`Package.resolved` records the complete Swift dependency graph; direct dependencies also use exact versions. CI tests, builds and packaging disable automatic resolution. Updating dependencies must explicitly update and review the lockfile. GitHub Actions and the DMG packaging tool use immutable commit pins. CI uses the checked-in artwork and no longer installs Pillow to regenerate it. Deliberate local artwork regeneration remains optional.

These pins make dependency changes reviewable. They do not prove that third-party code is harmless or make the entire toolchain reproducible; the hosted macOS/Xcode image remains GitHub-managed. Published releases still need the project's signing, notarization and Sparkle verification checks.

## Verification

Security tests exercise actual local connections: successful TLS pairing and actions, missing/invalid bearer tokens, wrong TLS keys, plaintext rejection, one-use/expired/limited pairing, event delivery, and revocation. Socket tests exercise a forged approval from a registered observer and verify that only the in-process decision completes the pending hook. A rendered Markdown test first demonstrates network image loading with the default renderer, then verifies no requests from the app's private renderer.

Run `zsh scripts/harness.sh ci` for the Mac checks. CI also builds the iPhone/Watch project with `xcodebuild`. Simulator compilation does not replace testing pairing and notifications on physical devices before a release.
