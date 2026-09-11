# Releasing Cinema Player

Use the release script to create an auditable, repeatable macOS release from the `main` branch.

## Before you begin

- Merge the intended pull requests into `main`.
- Choose a new semantic version, such as `v0.3.0`.
- Ensure GitHub CLI is authenticated with permission to create releases.
- Work from macOS, because the app bundle is built and ad-hoc signed locally.

## Publish an app release and the website

```sh
git switch main
git pull --ff-only origin main
zsh Scripts/release.sh v0.3.0 --publish-site
```

The script refuses to run from another branch, with uncommitted changes, if `main` differs from `origin/main`, or when the version/tag already exists. It then runs the test suite, builds the app bundle, packages `Cinema Player.app` as `Cinema-Player-macOS.zip`, creates a GitHub Release, and—when requested—publishes `Website/` to the `gh-pages` branch.

## App-only release

```sh
zsh Scripts/release.sh v0.3.0
```

## Verify and roll back

Open the generated GitHub Release and download the ZIP on a clean macOS account before announcing it. Confirm that the [website](https://hessennasser.github.io/cinema-player/) points to the latest release download.

If a release is incorrect, mark it as a draft or delete it in GitHub, then publish a corrected **new** version. Do not replace a released ZIP in place; immutable versioned artifacts make it possible to identify exactly what users installed.
