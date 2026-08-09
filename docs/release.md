# macOS release process

## Requirements

- Apple Developer Program membership
- a Developer ID Application certificate
- an app-specific password for the Apple Account
- Xcode command-line tools

## Build a local application bundle

```sh
rake app
open build/Mrbmacs.app
```

The application bundle includes `Scintilla.framework`. When one Developer ID
Application identity is available in the keychain, the bundle is signed with
Hardened Runtime and a secure timestamp. Otherwise it is ad-hoc signed. Set
`CODESIGN_IDENTITY` to select an identity explicitly. Use `rake run_app` to
build and open the bundle in one command.

## Store notarization credentials

Create an app-specific password for the Apple Account, then store the
notarization credentials in the login keychain:

```sh
APPLE_ID=you@example.com rake notarization_credentials
```

The keychain profile name defaults to `mrbmacs-notary`. Set `NOTARY_PROFILE`
to use another profile name.

## Create a release archive

```sh
rake release
```

The release task:

- builds the application bundle;
- signs it with the Developer ID Application identity;
- submits it to the Apple notary service;
- staples and validates the notarization ticket;
- verifies it with `codesign` and Gatekeeper;
- creates the distribution ZIP; and
- extracts and verifies the final ZIP.

The resulting archive is written to:

```text
build/Mrbmacs-<version>-macos-arm64.zip
```
