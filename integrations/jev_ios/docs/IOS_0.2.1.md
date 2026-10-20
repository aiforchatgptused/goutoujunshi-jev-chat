# 0.2.1 (14): third-party signing compatibility

- Read App Group/keychain hints from the executable's actual XML code-signature entitlements, not the embedded profile's allowlist. The iOS container API still decides whether access is authorized. Missing XML/unsupported signatures use only the configured group with an OS access check.
- Prefer the configured group if signed; accept a single remapped group; refuse ambiguous multiple groups. No private APIs or profile authorization bypass.
- Shared keychain groups must be concrete and match the configured suffix with the actual signing prefix. Wildcards are never used as query groups. Otherwise use the existing protected shared-container credential storage.
- Main app saves independently if no shared container exists, using private defaults and private keychain (protected local files on missing keychain entitlement). Extensions still require sharing and fail with a specific message. Local saving does NOT mean keyboard AI is working. Local credentials are not auto-migrated to a newly authorized shared group: re-enter them and save after re-signing.
- Build embeds ad-hoc App Group entitlement metadata into all three executables before packaging, extensions first. This gives re-signers actual entitlements to inspect rather than a bare unsigned executable. It is NOT an authorized installable signature. The final signer must supply allowed entitlements and matching profiles; a signer that removes groups can still fail.

## Device verification

1. Re-sign the new IPA, preserving both extensions and application-group permission. Keep the same bundle ID for an update if the signing service allows it.
2. Open Configuration. Confirm version 0.2.1 build 14 and inspect Keyboard sharing diagnostics.
3. Enter endpoint/model/key, test, save. Reopen the app to verify settings persist.
4. If local-only, verify main-app generation works, but do not count keyboard sharing as fixed.
5. If shared, enable keyboard full access and verify the keyboard sees saved configuration and performs a real API request.
6. If keyboard sharing still fails, inspect the newly re-signed IPA to compare main/extension entitlements. Do not infer success from installation or the main app's shared-container check alone.

macOS CI checks synthetic signed Mach-O parsing, malformed/truncated inputs and group selection, existing core regressions, simulator/device builds and embedded ad-hoc signature metadata.
