# Contributing

Thanks for taking the time to improve DevOps Status! Bug reports, ideas and pull requests are all welcome.

## Getting started

You need macOS 14+ and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).

```bash
git clone https://github.com/recepysl/devops-status.git
cd devops-status
make run          # build DevOpsStatus.app and launch it from the repo
```

To see real data without the UI, run `make once` after connecting in Settings, or `AZURE_DEVOPS_EXT_PAT=… swift run DevOpsStatus --once --org <organization>`.

## Before you open a pull request

- `make selftest` passes (and `make test` if you have Xcode).
- `swift build -c release` builds without warnings.
- If you changed anything visible, run `make screenshots` and commit the updated images in `docs/images/`.
- User-facing changes have an entry under an *Unreleased* heading in [CHANGELOG.md](CHANGELOG.md).

## Guidelines

- **Read-only.** The app may only call read endpoints; it must never vote, comment, queue builds or change work items.
- **Keep it dependency-free.** Apple frameworks only.
- **Keep logic in `DevOpsKit`.** Anything that doesn't need SwiftUI belongs there, with assertions in `SelfCheck.swift`.
- **Be lenient with responses.** Treat every field as optional; unknown states must degrade to something sensible, never a crash.
- **Never commit real data.** Fixtures and screenshots use made-up organizations and people only.

## Commit messages

The history follows [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(app): filter pipelines by branch
fix(kit): treat broken build policies as failed
docs: explain token scopes
```

Common types are `feat`, `fix`, `docs`, `test`, `build`, `ci`, `refactor` and `chore`. Scopes are `kit`, `app` and `cli`.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Move the *Unreleased* changelog entries under the new version.
3. Tag and push: `git tag v1.3.0 && git push origin v1.3.0`.

The release workflow builds the DMG and publishes the GitHub release with the changelog section as notes.
