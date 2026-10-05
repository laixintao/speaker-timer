# Releasing Speaker Timer

## One-command release

Commit all intended changes on `main`, then run:

```sh
make release
make release VERSION=1.1.0
```

The first release uses the version already stored in `SpeakerTimer/Info.plist`. Once that version has a tag, the default command increments the patch version. `VERSION` may specify any newer semantic version.

The command requires a clean working tree, a configured `origin`, Python 3.9+, Git, Make, and push access. It fetches the remote branch and tags before editing, rejects remote divergence and duplicate tags, updates the app version and build number when needed, generates release notes and a changelog entry, commits release metadata, creates an annotated tag, and atomically pushes `main` and the tag. It never force-pushes.

After the push, GitHub Actions runs the same checks used by pull requests on Apple Silicon and Intel runners. It packages a universal application, verifies the DMG and ZIP round trips, attests the installers, uploads them to a draft release, and publishes the release only after every upload succeeds.

If an atomic push fails, the release commit and tag remain locally and the command prints the exact retry command. Do not run `make release` again for the same version.

## Local verification

```sh
make ci
```

This runs project and release-script checks, native model and visual tests, universal packaging, checksum verification, signature validation, and DMG/ZIP installation round trips.

## Signing

Releases use ad-hoc signing and are not notarized. GitHub provenance proves which workflow produced an installer, but it is not a substitute for Apple Developer ID signing and does not remove Gatekeeper's first-launch warning.
