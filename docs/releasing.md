# Releasing

Push a version tag and GitHub Actions builds the DMG and publishes a release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

You can also run the **release** workflow by hand from the Actions tab; it then
uploads the DMG as a build artifact without creating a release.

## Without an Apple Developer account

The DMG is ad-hoc signed. It works, but macOS Gatekeeper will block the first
launch: right-click Mac Audio Panel in Applications, choose **Open**, then
**Open** again. Only needed once.

## Signed and notarized (recommended)

Needs a paid Apple Developer Program membership. Add these repository secrets
(Settings > Secrets and variables > Actions):

| Secret | What |
| --- | --- |
| `MACOS_CERT_P12` | Your **Developer ID Application** certificate and key, exported from Keychain Access as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | The password you set when exporting the .p12 |
| `SIGN_IDENTITY` | The identity name, e.g. `Developer ID Application: Your Name (ABCDE12345)` (`security find-identity -v -p codesigning`) |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | Your 10-character team ID |
| `APPLE_APP_PASSWORD` | An app-specific password from appleid.apple.com |

## Locally

```sh
make dmg                                              # ad-hoc
SIGN_IDENTITY="Developer ID Application: …" VERSION=1.0.0 make dmg
APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… scripts/notarize.sh build/MacAudioPanel-1.0.0.dmg
```
