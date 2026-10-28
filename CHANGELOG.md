# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-28

First release.

### Added
- Menu bar icon with a count of pull requests waiting for your review plus failed pipelines, colored by what needs attention.
- **To review**: active pull requests across the organization where your vote is still pending, with required reviews marked.
- **My pull requests**: review state, approvals, merge conflicts and build policy result for each of your active pull requests.
- **Pipelines**: latest CI result of the pipelines you pick in Settings, with an in-progress indicator. Pull request builds are ignored.
- **Work items**: open work items assigned to you.
- Notifications for new review requests, votes on your pull requests, failing pipelines and newly assigned work items; clicking one opens it.
- Settings window: organization and personal access token (stored in the Keychain), per-project pipeline picker with filter, refresh interval, notifications, *Open at Login*.
- CLI modes: `--once`, `--selftest`, `--render-screenshots`.
- `scripts/install.sh` one-line installer.

[1.0.0]: https://github.com/recepysl/devops-status/releases/tag/v1.0.0
