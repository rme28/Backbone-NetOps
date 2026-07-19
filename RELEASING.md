# Release process

This project uses **SemVer** with a pre-release channel until `1.0.0`:
`vMAJOR.MINOR.PATCH-channel`.

## When to bump what (before 1.0)

| Change type | Example | Bump |
|---|---|---|
| New batch of features | equipment palette, mouse cabling | `MINOR` -> `v0.2.0-alpha` |
| Fix on existing behavior | config bug, warning fixed | `PATCH` -> `v0.1.1-alpha` |
| Moving to a more stable phase | big features done, stabilizing | channel -> `v0.9.0-beta` |
| Stable release | ready for the public | `v1.0.0` |

Channel meaning: `alpha` (unstable, features still in flux) -> `beta` (features
frozen, bug hunting) -> `rc` (release candidate) -> final version with no suffix.

## Steps to publish a release

1. **Update CHANGELOG.md**: move the entries from `[Unreleased]` into a new
   `[X.Y.Z-channel] - YYYY-MM-DD` section, and update the two links at the
   bottom of the file.
2. **Commit**: `git commit -am "Release vX.Y.Z-channel"`.
3. **Annotated tag** (the message becomes the release body):
   ```bash
   git tag -a vX.Y.Z-channel -m "Title" -m "Details..."
   ```
4. **Push the commit and the tag**:
   ```bash
   git push origin master
   git push origin vX.Y.Z-channel
   ```
5. **Create the GitHub Release** from the tag:
   - **Web option** (no tooling required): on
     `https://github.com/rme28/Backbone-NetOps/releases` -> *Draft a new release*
     -> pick the tag `vX.Y.Z-channel` -> GitHub pre-fills the tag message
     -> check *Set as a pre-release* for `-alpha`/`-beta` -> *Publish release*.
   - **CLI option** (if `gh` is installed and authenticated):
     ```bash
     gh release create vX.Y.Z-channel --title "Title" --notes-file notes.md --prerelease
     ```

## Listing existing releases

```bash
git tag --list --sort=-v:refname          # local tags, newest first
git ls-remote --tags origin               # tags present on GitHub
```
