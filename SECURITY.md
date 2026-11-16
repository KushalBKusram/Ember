# Security Policy

Ember keeps all data on the device and has no server component, so the main risks are local: data
at rest, the lock screen, and the two opt-in network features (web search and URL fetch).

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting:
**Security → Report a vulnerability** on this repository. Include steps to reproduce, the iOS version
and device, and the impact you expect. I aim to acknowledge reports within a few days.

## Scope

In scope: leaking data off-device, bypassing the Face ID lock, reading another app's data, unsafe handling
of imported files or fetched web content, prompt-injection that causes an action the user didn't ask for.

Out of scope: issues that require a jailbroken device, or behaviour of Apple's on-device model itself.

## Supported versions

Only the latest release on `main` receives fixes.
