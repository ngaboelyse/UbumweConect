# Ubumwe Connect — System Architecture

## Overview

Ubumwe Connect is a multilingual real-time communication platform designed to break language barriers between speakers of Kinyarwanda, English, French, and Swahili. The system uses AI-powered translation to automatically convert messages into each participant's preferred language in real time.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │  Flutter    │  │  Flutter    │  │  Flutter    │                │
│  │  Android    │  │    iOS      │  │    Web      │                │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                │
└─────────│────────────────│────────────────│─────────────────────────┘
          │ HTTPS/WSS      │ HTTPS/WSS      │ HTTPS/WSS
┌─────────▼────────────────▼────────────────▼─────────────────────────┐
│                         NGINX REVERSE PROXY                          │
│           Rate Limiting · SSL Termination · Load Balancing           │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                      FASTAPI APPLICATION                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  REST API    │  │  WebSocket   │  │   Background Tasks       │  │
│  │  Routers     │  │  Manager     │  │   (Translation, FCM)     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────────────┘  │
│         │                 │                                          │
│  ┌──────▼─────────────────▼───────────────────────────────────────┐ │
│  │                    SERVICE LAYER                                 │ │
│  │  AuthService · TranslationService · VoiceService · FileService  │ │
│  └──────────────────────────────────────────────────────────────── ┘ │
└─────────────────────────────────────────────────────────────────────┘
          │                   │                       │
┌─────────▼──────┐  ┌─────────▼──────┐  ┌───────────▼──────────────┐
│  PostgreSQL    │  │     Redis      │  │   External Services      │
│  (Primary DB)  │  │   (Cache +     │  │  ┌─────────────────────┐ │
│                │  │  Rate Limits)  │  │  │  OpenAI GPT-4o-mini │ │
│  · Users       │  │                │  │  │  (Translation)      │ │
│  · Messages    │  │  · Trans Cache │  │  ├─────────────────────┤ │
│  · Convs       │  │  · Sessions    │  │  │  OpenAI Whisper     │ │
│  · Calls       │  │  · Presence    │  │  │  (Speech-to-Text)   │ │
│  · Trans Log   │  │                │  │  ├─────────────────────┤ │
└────────────────┘  └────────────────┘  │  │  OpenAI TTS         │ │
                                        │  │  (Text-to-Speech)   │ │
                                        │  ├─────────────────────┤ │
                                        │  │  Firebase Auth      │ │
                                        │  │  + FCM Notifications│ │
                                        │  ├─────────────────────┤ │
                                        │  │  AWS S3             │ │
                                        │  │  (File Storage)     │ │
                                        │  └─────────────────────┘ │
                                        └──────────────────────────┘
```

---

## Component Architecture

### 1. Flutter Frontend

```
lib/
├── app/
│   ├── router.dart          # GoRouter — auth-guarded navigation
│   └── theme/               # Material 3 design system
├── core/
│   └── constants/           # API URLs, language configs, WS events
├── features/
│   ├── auth/                # Login, register, onboarding, Firebase
│   ├── chat/                # Conversations, messages, WebSocket
│   ├── calls/               # Voice/video calls (WebRTC)
│   ├── profile/             # User profile, settings
│   └── translation/         # Language settings
└── shared/
    ├── services/            # API (Dio), WebSocket, LocalStorage
    └── widgets/             # Reusable Avatar, etc.
```

**State Management:** Flutter Riverpod (v2)
- `StateNotifier` for auth state
- `AsyncNotifier` for conversations list
- `FamilyAsyncNotifier` for paginated messages per conversation
- `StateProvider.family` for typing indicators per conversation

**Navigation:** GoRouter with ShellRoute for bottom navigation tabs

### 2. FastAPI Backend

```
app/
├── main.py              # App factory, lifespan, routers
├── config.py            # Pydantic Settings from .env
├── database.py          # Async SQLAlchemy + connection pool
├── models/              # SQLAlchemy ORM models
│   ├── user.py          # User, UserContact, UserSession
│   ├── chat.py          # Conversation, Message, MessageStatus
│   ├── call.py          # Call, CallParticipant
│   └── translation.py   # TranslationCache, Translation
├── schemas/             # Pydantic v2 request/response schemas
├── routers/             # HTTP endpoints (auth, users, chat, etc.)
├── services/            # Business logic (auth, translation, voice)
├── websocket/           # WebSocket connection manager + handlers
└── middleware/          # JWT auth middleware
```

### 3. Database Schema (PostgreSQL)

```
users ←──────────── user_contacts
  │ 1                    │
  │                      │
  ▼ N                    │
conversation_participants─┘
  │ N
  │ 1
  ▼
conversations
  │ 1
  │
  ▼ N
messages ──────────→ translation_cache
  │ 1                (text_hash + lang pair)
  │
  ▼ N
message_statuses
```

**Key design decisions:**
- Messages store `translated_contents` as PostgreSQL JSONB: `{"english": "...", "kinyarwanda": "..."}`
- Translation cache uses SHA-256 hash of source text as lookup key
- UUID primary keys throughout (no sequential IDs leaked in URLs)
- Triggers auto-update `conversation.last_message_at` on message insert

---

## Real-Time Messaging Architecture

```
User A (Kinyarwanda)          Backend                    User B (English)
        │                        │                              │
        │──── WS Connect ───────►│                              │
        │                        │◄────── WS Connect ───────────│
        │                        │                              │
        │── send_message ───────►│                              │
        │   {content: "Muraho"}  │                              │
        │                        │── detect language ──►OpenAI │
        │                        │◄─ "kinyarwanda"              │
        │                        │                              │
        │                        │── translate to EN ──►OpenAI │
        │                        │◄─ "Hello"                    │
        │                        │                              │
        │                        │── save to DB ────────────── │
        │                        │   {content: "Muraho",        │
        │                        │    translated_contents:       │
        │                        │    {english: "Hello", ...}}  │
        │                        │                              │
        │◄── new_message ────────│── new_message ──────────────►│
        │   (in Kinyarwanda)     │   (in English)               │
```

---

## Translation Pipeline

```
Incoming Message
       │
       ▼
┌─────────────────────────────┐
│  1. Detect source language  │  ← User's preferredLanguage OR
│     (from user profile)     │     OpenAI language detection
└────────────────┬────────────┘
                 │
                 ▼
┌─────────────────────────────┐
│  2. For each participant    │
│     language ≠ source:      │
│                             │
│  ┌───────────────────────┐  │
│  │  Check translation    │  │
│  │  cache (text_hash +   │  │
│  │  lang pair)           │  │
│  └──────────┬────────────┘  │
│             │               │
│    CACHE HIT│ CACHE MISS    │
│       ┌─────┴─────┐         │
│       │           │         │
│    Return      Call GPT-4   │
│    cached      o-mini API   │
│    result      └──────┬──── │
│                       │     │
│                  Save to    │
│                  cache      │
└─────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────┐
│  3. Update message JSONB    │
│     translated_contents     │
└────────────────┬────────────┘
                 │
                 ▼
┌─────────────────────────────┐
│  4. Broadcast via WebSocket │
│     to each participant     │
│     (in their language)     │
└─────────────────────────────┘
```

**Cache hit rate in production:** Expected >70% for common phrases

---

## WebRTC Call Architecture

```
Caller                    Backend                    Callee
  │                          │                          │
  │── initiate_call ────────►│                          │
  │   {type: "video",        │── call_signal ──────────►│
  │    target: callee_id}    │   {type: "incoming"}     │
  │                          │                          │
  │                          │◄── accept_call ──────────│
  │                          │                          │
  │◄── call_signal ──────────│── call_signal ──────────►│
  │   {type: "accepted"}     │                          │
  │                          │                          │
  │── WS: webrtc_offer ─────►│── WS: webrtc_offer ─────►│
  │                          │                          │
  │◄── WS: webrtc_answer ────│◄─ WS: webrtc_answer ─────│
  │                          │                          │
  │── WS: ice_candidate ────►│── WS: ice_candidate ────►│
  │◄── WS: ice_candidate ────│◄─ WS: ice_candidate ──── │
  │                          │                          │
  │◄═════════ Direct P2P WebRTC Stream ════════════════►│
  │          (Audio/Video — NOT through backend)         │
  │                          │                          │
  │  During call: Whisper STT ► GPT-4o-mini ► subtitles │
```

---

## Security Architecture

| Layer | Mechanism |
|-------|-----------|
| Transport | TLS 1.3 via Nginx (HTTPS/WSS) |
| Authentication | JWT (HS256, 30-min access + 30-day refresh) OR Firebase tokens |
| Authorization | Middleware validates token on every request; conversation membership checked per-query |
| Rate Limiting | Nginx zones: 60 req/min general, 10 req/min auth, 30 req/min translation |
| Input Validation | Pydantic v2 strict validation on all inputs |
| SQL Injection | SQLAlchemy ORM with parameterized queries only |
| File Uploads | Type whitelist, size limit, stored on S3 (not server disk) |
| Secrets | `.env` file, never committed; CI uses GitHub Secrets |

---

## Scalability Design

- **Horizontal backend scaling:** Multiple FastAPI workers behind nginx `least_conn`
- **WebSocket stickiness:** Redis pub/sub enables cross-worker message delivery
- **Database:** Read replicas can be added for analytics/reporting queries
- **Translation cache:** Redis L1 cache (hot) → PostgreSQL L2 cache (warm) → OpenAI API (cold)
- **CDN:** Avatar/media files served from AWS CloudFront via S3
- **Future:** Kubernetes HPA scales backend pods based on CPU/WebSocket connection count
