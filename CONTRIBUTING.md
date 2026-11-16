# Contributing to Ember

Thanks for your interest. Ember is a small, privacy-first iOS app, and contributions that keep it
**reliable, predictable and private** are very welcome.

## Ground rules

Ember's v1 promise is: *a private, on-device personal knowledge assistant — not an autonomous life agent.*
Changes are judged against it:

- **Nothing leaves the device.** No analytics, no cloud calls, no telemetry. Web search and URL fetching
  are the only network paths and are opt-in.
- **Bounded behaviour over cleverness.** Repeating an action must not create duplicates; a failed action
  must say so; cancel must cancel. See "Behavioural guarantees" in the README.
- **Core vs Beta.** Chat, memory, files/notes, calendar/reminders and the lock screen are Core and held to
  release quality. Agents, scheduled jobs, web search and image generation are Beta.

## Getting set up

```bash
brew install xcodegen
git clone https://github.com/KushalBKusram/Ember.git
cd Ember
xcodegen generate
open Ember.xcodeproj
```

Requirements: Xcode 26 or later (developed on Xcode 27), an iOS 26+ simulator or an Apple Intelligence
capable iPhone (A17 Pro or newer). The Xcode project is generated from `project.yml` and is not committed;
change `project.yml`, not the `.xcodeproj`.

## Running the tests

```bash
xcodegen generate
xcodebuild test -project Ember.xcodeproj -scheme Ember \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). Two suites, `SemanticRetrievalEvalTests` and
`MemoryBandingEvalTests`, measure real `NLEmbedding` behaviour and print `[EVAL]` lines; they need the
on-device language asset, which headless CI runners usually lack, so CI skips them.

## Making a change

1. Open an issue first for anything bigger than a small fix.
2. Branch from `main`; keep the change focused.
3. Add or update tests. Bug fixes should come with a test that fails without the fix.
4. Run the full suite and make sure it passes.
5. Open a pull request using the template. Describe the user-visible behaviour, not just the code.

### Code style

- Swift 6 with strict concurrency. Services are actors; view models are `@MainActor`.
- Don't swallow errors in user-facing code paths: report them with `UserFacingError` / `.errorAlert`.
- Prefer small, pure, testable functions for decisions (see `MemoryService.band(forSimilarity:)`).
- Default to no comments; explain *why* only when it isn't obvious.

## Reporting bugs and security issues

Bugs: use the issue templates. Security or privacy problems: see [SECURITY.md](SECURITY.md) and do not
open a public issue.
