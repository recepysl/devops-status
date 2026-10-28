# Security Policy

DevOps Status works with an Azure DevOps personal access token, so it is designed to touch as little as possible.

## What the app accesses

| Resource | Access | Why |
| --- | --- | --- |
| Azure DevOps organization you connect | Read only: connection data, pull requests, policy evaluations, projects, build definitions, builds, work items (WIQL query + batch read) | The four sections in the dropdown |
| Keychain | Read / write its own item | The personal access token you enter in Settings |
| `UserDefaults` | Read / write | Organization URL, watched pipelines, refresh interval, notification setting |
| Notification Center | Post | Local alerts, if enabled |
| Default browser | Open | When you click an item |

The token is only sent to the organization URL you entered. The app never writes to Azure DevOps, never stores the token anywhere but the Keychain, and sends no data anywhere else. There is no analytics or telemetry.

Give the token the narrowest scopes it needs: **Read** on Code, Build, Work Items and Project and Team, and a short expiry.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, use GitHub's [private vulnerability reporting](https://github.com/recepysl/devops-status/security/advisories/new) for this repository. You can expect an initial response within a few days.
