# 🔥 Ember

> Private AI that knows you.

---

## What is Ember?

Ember is a personal AI assistant that lives entirely on your iPhone. It remembers who you are, knows your schedule, reads your documents, and gets smarter the more you use it — with zero data ever leaving your device.

No accounts. No cloud. No analytics. Just a private AI that's yours.

---

## For Users

**An AI that remembers you**
Ember learns from your conversations over time — your preferences, projects, relationships, and life events. The more you talk, the better it knows you.

**Knows your schedule**
Connect your Calendar and Reminders and Ember can answer questions like "What do I have this week?" or "Do I have time Thursday?" without sending your calendar to anyone.

**Your personal knowledge base**
Import documents and PDFs, or write notes directly in the app. Ember reads everything and uses that context when answering your questions.

**Agents that work while you sleep**
Set up automated AI assistants that run on a schedule — daily market summaries, weekly project check-ins, morning briefings. Ember runs the task in the background and sends you the result.

**Live web search, on your terms**
Ember can look up current information — stock prices, news, weather — but only when you ask, and only with your permission.

**Locked with Face ID**
Every conversation is protected behind Face ID. No one else can open Ember, even if they have your phone.

**What makes Ember different**
- Nothing goes to the cloud. Ever.
- It remembers you across every conversation, not just the current one.
- It works around your actual life — your calendar, your documents, your notes.

---

## For Developers

### Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI + `@Observable` |
| LLM | Apple FoundationModels (`LanguageModelSession`, `@Generable`) |
| Database | GRDB (`DatabasePool`, 7 migrations) |
| Embeddings | `NLEmbedding` · SHA-256 SQLite cache |
| Background | `BGAppRefreshTask` |
| HTML parsing | SwiftSoup |
| Project generation | XcodeGen (`project.yml`) |
| Tests | Swift Testing framework |

### Requirements

- Xcode 27 beta (`Xcode-beta.app`)
- iOS 26.0+ deployment target (iOS 27 APIs guarded with `#available`)
- Device with Apple Intelligence support (iPhone 15 Pro or later; A17 Pro+)
- iOS 27 simulator runtime for running tests (Xcode-beta → Settings → Platforms)

### Architecture

All services are `actor`-isolated. ViewModels are `@MainActor`. There are no shared mutable globals — all cross-actor communication goes through `async/await`.

```
App
├── Services (actors)
│   ├── LLMService          — prompt assembly, streaming + non-streaming LLM calls
│   ├── MemoryService       — 3-band absorption, profile synthesis, MMR retrieval
│   ├── RAGService          — chunking (512w/50w overlap), MMR retrieval (λ=0.7)
│   ├── EmbeddingService    — NLEmbedding wrapper, SHA-256 SQLite cache
│   ├── CalendarService     — EventKit read access, schedule context builder
│   ├── WebSearchService    — DuckDuckGo HTML, LLM-routed for agents
│   ├── WebFetchService     — URL → text (HTML + PDF), 10 s timeout
│   ├── BackgroundJobService — BGAppRefreshTask handler, result notifications
│   └── AgentService        — agent + job CRUD, notification scheduling
├── ViewModels (@MainActor)
│   ├── ConversationViewModel      — character-drip streaming, memory extraction
│   └── AgentConversationViewModel — same + schedule-intent detection
├── Database
│   └── AppDatabase         — GRDB DatabasePool, 7 migrations, file protection
└── Models
    ├── Memory / MemoryExtraction  — @Generable extraction + supersession structs
    ├── Agent / AgentJob           — schedule math (isDue, nextFireDate)
    ├── RAGDocument / RAGChunk     — source taxonomy, chunk round-trip
    └── ScheduleIntentModels       — @Generable structured schedule parsing
```

### Memory System

Facts are extracted from every user message and absorbed through a 3-band pipeline:

| Similarity to existing memory | Action |
|---|---|
| ≥ 0.97 | Reinforce (update `lastAccessedAt`, skip duplicate) |
| 0.70 – 0.96 | Batch LLM supersession check → maybe delete old, always save new |
| < 0.70 | Save as new fact |

Categories: `preference`, `project`, `relationship`, `episodic` (episodic expires after 30 days).

A 2–4 sentence profile paragraph is synthesised from non-episodic memories and injected into every prompt.

### Getting Started

```bash
# Clone and generate the Xcode project
git clone https://github.com/KushalBKusram/Ember.git
cd Ember
xcodegen generate   # requires xcodegen: brew install xcodegen

# Open in Xcode 27 beta
open Ember.xcodeproj
```

Build and run on a physical device (Apple Intelligence requires A17 Pro+ hardware). The simulator can be used for UI work but FoundationModels calls will not execute.

### Running Tests

Tests use the Swift Testing framework (`@Suite`, `@Test`, `#expect`).

```bash
# Requires iOS 27 simulator runtime installed in Xcode-beta
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project Ember.xcodeproj -scheme Ember \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

Current test suites: `MemoryExpirationTests`, `MemoryCategoryTests`, `RAGDocumentTests`, `AgentJobScheduleTests`, `NotificationRoutingTests`, `EmbeddingRoundTripTests`, `WebFetchURLDetectionTests`, `DeviceCapabilityTests`.

### Dependencies

| Package | Purpose |
|---|---|
| [GRDB](https://github.com/groue/GRDB.swift) `6.0+` | SQLite ORM, migrations, `ValueObservation` |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) `2.7+` | HTML parsing for web search and URL fetching |

---

## Status

| Area | Status |
|---|---|
| Core chat + streaming | ✅ Done |
| Memory (extraction, synthesis, retrieval) | ✅ Done |
| Knowledge sources (files, notes, calendar, reminders) | ✅ Done |
| Web search | ✅ Done |
| Agents + background jobs | ✅ Done |
| Notification routing | ✅ Done |
| Onboarding | ✅ Done |
| Face ID lock | ✅ Done |
| iOS 26/27 dual target | ✅ Done |
| TestFlight submission | 🔜 Pending iOS 27 simulator runtime |
| Voice input | ❌ Removed from v1 |
