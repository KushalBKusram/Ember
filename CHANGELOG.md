# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-11-16

First public release.

### Core
- Private on-device chat on Apple Foundation Models with streaming, titles, regenerate, edit and cancel.
- Persistent memory: extraction from your own words, three-band de-duplication, supersession of corrected
  facts, a grounded profile summary, per-memory enable/disable/delete, Incognito mode.
- Files and notes as knowledge sources (PDF, text, in-app notes) with on-device embeddings and MMR retrieval.
- Read-only calendar and reminders context, with an explicit message when access is missing.
- Face ID lock and a four-step onboarding.

### Beta
- Agents with scheduled and interval jobs, natural-language job creation, background execution and notifications.
- Opt-in web search and URL fetch (DuckDuckGo, no API key).
- Image generation.

### Fixed during release hardening
- Model echoing internal context tags into replies.
- Corrections being dropped as duplicates; profile inventing details; assistant refusals saved as memories.
- Duplicate sends, duplicate jobs and duplicate file imports from rapid taps; overlapping job runs.
- Web search answering questions about the user's own data; personal notes cited beside web answers.
- Silent failures: failed writes now report an error instead of doing nothing.
- Background job runs are atomic: a failed run no longer leaves stray prompts.

### Known limitations
- Needs an Apple Intelligence capable iPhone (A17 Pro or newer) running iOS 26+.
- Semantic retrieval top-1 accuracy is about 58% on the bundled evaluation set.
- Paraphrased duplicate memories can still be stored as separate entries.
- Background refresh timing is controlled by iOS and is not deterministic.
