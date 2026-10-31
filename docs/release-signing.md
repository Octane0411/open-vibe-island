# Fork release and update gate

**Distribution and updates are blocked.** The inherited automatic release workflow no longer imports credentials, publishes assets, merges appcasts, or modifies upstream repositories. Tags and manual invocations fail with an explanation. Both automatic and manual Sparkle checks are disabled in the app, and packaging omits the upstream feed and key. The inherited appcast offers no releases. There is no environment-variable bypass.

The default package identity is `io.github.robinedquist.openisland.dev`, for local development only. Choosing a production identity, release name, website/feed, and signing credentials remains a maintainer decision. This does not establish side-by-side compatibility: session registries, installed helpers, agent hook entries, and socket paths still overlap with upstream. Only one listener can own a socket path.

## Requirements before enabling distribution

1. Choose the production bundle identity and ownership/migration rules for all shared paths. Test an upstream-to-fork migration and uninstall without removing unrelated user hooks.
2. Provision a Developer ID Application identity and Apple notarization credentials under maintainer control. Keep private credentials in the platform keychain or protected CI secrets. Do not copy upstream credentials or keys.
3. Generate a fork-owned Sparkle signing key, publish only its public key, and configure an HTTPS feed controlled by the fork. Implement configuration validation before removing the runtime restriction.
4. Build the exact reviewed commit with its lockfile and recorded toolchain. Verify helper/resources/license notices, both intended architectures, code signatures, notarization acceptance, and stapling. A local ad-hoc signature is not distribution approval.
5. Complete the platform, terminal, agent, GUI, and permission-denied matrix in `docs/quality.md`. Record exact versions and evidence; narrow public compatibility claims when a platform has not been tested.
6. Test a signed upgrade, correct signature rejection, helper compatibility, interrupted-update recovery, and rollback on a separate test account/machine.
7. Restore a reviewed publication workflow that creates a draft and uploads assets first. After explicit publication, verify every asset through an anonymous HTTPS download and compare its length/hash to the signed artifact. Only then generate/promote update metadata. Draft or failed releases must not alter appcast or package-manager metadata. Use normal reviewed PRs; no administrative auto-merge or force-push to a third-party tap.

## Local verification

`zsh scripts/package-app.sh --verify-configuration` checks the disabled update configuration without building, signing, installing, or launching an app. Attempts to supply an update feed/key or enable flag fail before building. The packaging script produces local artifacts only; nothing in this workflow authorizes publishing them.

Desktop smoke tests must run explicitly in an isolated test account. Building a package must not silently start the app against the developer's existing sessions. Required manual evidence remains a release blocker, not a claim implied by a successful compiler run.
