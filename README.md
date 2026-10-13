<div align="center">

# 🌍 Ubumwe Connect

### *Bringing People Together Beyond Language*

**An AI-powered, real-time multilingual communication platform**
*Kinyarwanda · English · French · Swahili*

[![Backend Tests](https://img.shields.io/badge/tests-passing-brightgreen)](.github/workflows/ci.yml)
[![Python](https://img.shields.io/badge/Python-3.11%2B-blue?logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.22%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111%2B-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[Overview](#-overview) · [Features](#-features) · [Architecture](#-architecture) · [Quick Start](#-quick-start) · [API](#-api) · [Docs](#-documentation) · [Contributing](#-contributing)

</div>

---

## 📖 Overview

**Ubumwe Connect** (*ubumwe* is Kinyarwanda for *unity*) eliminates language barriers in digital
communication. Every user speaks, types, and reads in their **own preferred language** — the
platform handles all translation transparently and in real time.

Instead of copy-pasting into a translator app, two people — one speaking Kinyarwanda, one English —
simply have a conversation. **Every text message is translated automatically** in both directions, so each
person reads the chat in their own language.

> Built as a final-year capstone project, engineered to production standards: JWT-secured API,
> WebSocket messaging, WebRTC calling, rate limiting, structured logging, CI, and containerised
> deployment.

| | |
|---|---|
| **Platform** | Android · iOS · Web (single Flutter codebase) |
| **Backend** | Python 3.11+ · FastAPI · SQLAlchemy (async) · WebSocket |
| **Real-time** | WebSocket messaging · WebRTC voice/video · TURN traversal |
| **AI** | GPT (contextual text translation) |
| **Data** | PostgreSQL · Redis (cache / pub-sub) · AWS S3 media |
| **Auth** | Firebase Authentication · JWT access/refresh tokens |

---

## ✨ Features

### 💬 Real-Time Multilingual Chat
- Instant message delivery over WebSocket (typical latency < 200 ms)
- **Automatic, bidirectional translation** — each participant reads every message in their own language
- Toggle any message between translated and original text
- Typing indicators, delivery/read receipts, online presence

### 🎙️ Voice & Video Calls
- WebRTC peer-to-peer voice and video calling
- Graceful TURN relay fallback for restrictive NATs

### 📝 Voice Messages
- Record and send voice notes as audio attachments

### 👥 Multilingual Group Conversations
- Groups up to 50 members, each with their own language preference
- Translations are deduplicated per language, not per member — efficient at scale

### 🔔 Notifications & Files
- Push notifications via Firebase Cloud Messaging
- Image/document sharing via S3 pre-signed URLs

### 🛡️ Platform & Security
- JWT authentication with refresh-token rotation, bcrypt password hashing
- Rate limiting, trusted-host enforcement, CORS allow-list, GZip compression
- Full **admin dashboard**: user management, usage statistics, moderation, audit logging
- Structured request logging; OpenAPI docs at `/api/docs`

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENT TIER                          │
│   Flutter App (Android / iOS / Web) — Riverpod · WebRTC     │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS · WSS
┌──────────────────────────┼──────────────────────────────────┐
│                    APPLICATION TIER                         │
│                  FastAPI Backend (async)                    │
│   ┌──────────┐  ┌───────────┐  ┌────────────────────┐      │
│   │ REST API │  │ WebSocket │  │ Translation Service│      │
│   │          │  │ Signalling│  │  (Whisper + GPT)   │      │
│   └──────────┘  └───────────┘  └────────────────────┘      │
│   Rate limiting · JWT auth · Logging · GZip                 │
└──────────────────────────┬──────────────────────────────────┘
┌──────────────────────────┼──────────────────────────────────┐
│                     DATA / EXTERNAL TIER                    │
│   PostgreSQL   Redis   AWS S3   Firebase   OpenAI API       │
└─────────────────────────────────────────────────────────────┘
```

**Repository layout**

```
├── backend/          # FastAPI app: routers, models, services, websocket, tests
├── frontend/         # Flutter app: features, providers, screens, widgets
├── database/         # SQL schema and seed data
├── deployment/       # Docker / docker-compose (dev & prod)
├── docs/             # Full project report, API docs, deployment guide, UAT plan
└── scripts/          # Development and deployment helper scripts
```

---

## 🚀 Quick Start

### Prerequisites
- **Python 3.11+**, **Flutter 3.22+**, **PostgreSQL**, **Redis**
- OpenAI API key and Firebase project (see `.env.example`)

### 1. Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows  (source .venv/bin/activate on Linux)
pip install -r requirements.txt
copy .env.example .env            # then fill in your secrets

uvicorn app.main:app --reload --port 8000
```

API docs: **http://localhost:8000/api/docs** · Health check: **http://localhost:8000/health**

### 2. Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome             # or -d <android-device-id>
```

Point the app at your backend via the API base URL constant in
`frontend/lib/core/constants/app_constants.dart`.

### 3. Docker (full stack)

```bash
docker compose -f deployment/docker/docker-compose.yml up --build
```

---

## 🔌 API Overview

Base URL: `/api/v1` — JWT Bearer auth on all endpoints except register/login.

| Group | Endpoints | Purpose |
|---|---|---|
| `auth` | `/auth/register`, `/auth/login`, `/auth/refresh` | Account & token management |
| `users` | `/users/me`, `/users/search` | Profiles, language preference, contacts |
| `conversations` | `/conversations`, `/conversations/{id}/messages` | Chats & groups |
| `calls` | `/calls` | Call history & signalling support |
| `translation` | `/translate` | On-demand translation |
| `admin` | `/admin/stats`, `/admin/users` | Platform administration |

Full reference: [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md) ·
Interactive: `/api/docs` (Swagger) and `/api/redoc`

**WebSocket**: `ws://<host>/ws/{user_id}?token=<jwt>` — real-time messages, receipts,
typing indicators, presence, and WebRTC signalling.

---

## 🧪 Testing

```bash
# Backend
cd backend && pytest -v

# Frontend
cd frontend && flutter test && flutter analyze
```

CI runs both suites on every push via GitHub Actions (`.github/workflows/ci.yml`).

---

## 📚 Documentation

| Document | Description |
|---|---|
| [`docs/PROJECT_REPORT.md`](docs/PROJECT_REPORT.md) | Full academic project report (8 chapters) |
| [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md) | Complete API reference |
| [`docs/DEPLOYMENT_GUIDE.md`](docs/DEPLOYMENT_GUIDE.md) | Production deployment |
| [`docs/USER_MANUAL.md`](docs/USER_MANUAL.md) | End-user manual |
| [`docs/TESTING_PLAN.md`](docs/TESTING_PLAN.md) | Testing strategy & UAT |
| [`docs/FUTURE_ENHANCEMENTS.md`](docs/FUTURE_ENHANCEMENTS.md) | Roadmap |
| [`docs/architecture/`](docs/architecture) · [`docs/diagrams/`](docs/diagrams) | Diagrams & design notes |

---

## 🗺️ Roadmap

- Additional languages (Arabic, Amharic, Luganda, Portuguese)
- Offline mode with queued sending
- End-to-end encryption research (client-side / homomorphic approaches compatible with translation)
- Enterprise accounts & third-party API access

See [`docs/FUTURE_ENHANCEMENTS.md`](docs/FUTURE_ENHANCEMENTS.md).

---

## 🤝 Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the
[code of conduct](CODE_OF_CONDUCT.md).

## 📄 License

Released under the [MIT License](LICENSE).

---

<div align="center">

*Built with ❤️ in Rwanda — for every African who has ever been excluded from a conversation because of the language they speak.*

</div>
