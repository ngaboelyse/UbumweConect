# Ubumwe Connect — Technical Analysis

**Analysis date:** 29 September 2026
**Analyst role:** Software engineering review (read-only; no production code was modified)
**Scope reviewed:** `backend/`, `frontend/`, `database/`, `deployment/`, `docs/`, `alembic/`
**Repository root:** `d:/ALL/Project/UbumweConnect`

---

## 1. Executive summary

Ubumwe Connect is a capstone-scale multilingual chat application: a Flutter client, a FastAPI/PostgreSQL
backend, and a set of OpenAI-backed translation endpoints covering Kinyarwanda, English, French and Swahili.

The parts that exist are **genuinely working and well written** — the backend in particular is coherent,
tested and idiomatic. However, a large share of the feature set described in `docs/PROJECT_REPORT.md`
is **not implemented in the code that is present in this repository**. The gap is not a matter of polish;
several headline capabilities (real-time message delivery, voice/video calling, WebRTC, live subtitles,
the AI assistant, the admin dashboard, voice-message transcription) are either absent, stubbed with
simulated data, or dead code that is never reachable from the running app.

### Verified status at a glance

| Area | Claimed in report | Actual state in repository |
|---|---|---|
| Backend REST API (auth, users, conversations, messages, calls, translation, admin) | Complete | **Implemented.** 43 backend tests pass. |
| Real-time messaging over WebSocket | Live bidirectional, <200 ms | **Backend implemented, client never connects.** `WebSocketService.connect()` has no call site. |
| Message translation pipeline | GPT-4o, cached, <500 ms | **Implemented** (backend only), but the shipped `OPENAI_API_KEY` is a placeholder, so it cannot run. |
| Voice message transcription (Whisper) + TTS | Implemented | Backend endpoint exists; **no client calls it**. |
| Voice/video calling over WebRTC | Implemented, 93% success | **Not implemented.** Call screens are UI mock-ups with `Timer`-driven fake subtitles and hard-coded "Contact Name". `flutter_webrtc` is a declared dependency that is never imported. |
| Live subtitles during calls | 1.6 s latency | **Not implemented.** Simulated with a hard-coded string array. |
| Group conversations with per-member translation | Implemented | Backend **implemented** (translates once per unique language). Client group UI is partial. |
| AI conversation assistant | Implemented (FR-032) | **Not implemented.** `frontend/lib/features/ai_assistant/` is an empty directory; no backend route or table. |
| Admin dashboard | Implemented, full | Backend admin routes exist but are **unreachable** (no way to create an `admin` user) and there is **no admin UI**. |
| Email verification / password reset email | Implemented | **Stubbed.** `/auth/forgot-password` returns 202 and does nothing; there is no `is_verified` field on the model. |
| Redis for cache + WebSocket Pub/Sub + rate limiting | Core to the design | **Never used.** `redis` is not imported anywhere in the backend. |
| Alembic migrations | Used for schema management | `backend/alembic/versions/` is **empty**. Schema is created implicitly by `Base.metadata.create_all`. |
| Test suite | 100 unit + 45 integration + 73 system, 91% coverage | **43 backend tests** (all passing) plus **1 frontend test, which fails**. No integration, system, load or security suite exists in the repo. |
| UAT with 15 participants, SUS 78.3 | Reported | No UAT artefacts (scripts, raw data, consent forms) are present in the repository. |

### Headline conclusions

1. **The backend is the real, valuable asset of this project.** It is a clean, async, well-factored
   FastAPI service with sensible models, Pydantic validation, JWT auth, middleware and a passing test suite.
2. **The frontend is a polished UI shell with partial wiring.** Authentication, conversation lists, chat
   rendering, attachments and profile editing are wired to the API. Calling, AI assistance and notifications
   are not.
3. **Real-time messaging does not work end-to-end** because nothing calls `WebSocketService.connect()`.
   The WebSocket client is written and the screen subscribes to its stream, but the stream never emits.
4. **The architectural documentation does not describe the code that is present.** Redis Pub/Sub,
   multi-instance WebSocket scaling, a separate `message_translations` table, `ai_messages`, `audit_logs`
   and `push_tokens` tables, S3 pre-signed direct uploads, and a `flutter_webrtc` call stack are all
   described in `PROJECT_REPORT.md` but do not exist here.
5. **The two schema definitions in the repo are incompatible.** `database/schema.sql` uses different
   column names than the SQLAlchemy models, so the Docker `initdb` path produces a database the API
   cannot query.

---

## 2. How this analysis was verified

Everything below is based on reading the source and on executable checks, not on the contents of
`docs/PROJECT_REPORT.md`.

| Check | Command | Result |
|---|---|---|
| Backend test suite | `cd backend; .venv\Scripts\python.exe -m pytest tests -q` | **43 passed, 0 failed** in 47.03 s (340 warnings) |
| Static analysis (Dart) | `cd frontend; flutter analyze --no-pub` | **102 issues, 0 errors** (2 warnings, 100 infos) |
| Frontend test suite | `cd frontend; flutter test --no-pub` | **0 passed, 1 failed** — the only frontend test in the repository fails |
| Config/runtime probe | inline script reading `app.config.settings` | `DATABASE_URL` host `postgres` → **DNS FAIL**; `redis` host → **DNS FAIL**; `OPENAI_API_KEY = sk-placehold…`; AWS not configured; Firebase path empty; TURN URL empty |
| Dead-code / wiring greps | `search_files` across `backend/app` and `frontend/lib` | See Findings 3.1–3.6 |

The backend test suite is run against SQLite (`sqlite+aiosqlite`) with the app's `get_db` dependency
overridden — see `backend/tests/conftest.py`. It does **not** exercise PostgreSQL-specific behaviour
(`JSONB`, `UUID`, the `translations_cache` unique/partial indexes) nor any WebSocket flow.

---

## 3. Repository inventory (verified)

```
UbumweConnect/
├── backend/                    FastAPI service (Python 3.12 target)
│   ├── app/
│   │   ├── main.py             app factory, middleware stack, routers, /ws/{user_id}
│   │   ├── config.py           pydantic-settings; requires SECRET_KEY, DATABASE_URL, OPENAI_API_KEY
│   │   ├── database.py         async engine, session factory, Base, init_db/close_db
│   │   ├── middleware/         auth_middleware.py, rate_limit.py, logging.py
│   │   ├── models/             user.py, chat.py, call.py, translation.py
│   │   ├── routers/            auth, users, conversations, calls, translation, admin
│   │   ├── schemas/            user, chat, call, translation (Pydantic v2)
│   │   ├── services/           auth_service, translation_service, voice_service,
│   │   │                       file_service, notification_service
│   │   ├── websocket/          manager.py (in-memory), handlers.py
│   │   └── utils/              EMPTY
│   ├── alembic/versions/       EMPTY  (no migrations exist)
│   ├── tests/                  conftest.py, test_auth.py, test_messaging.py, test_translation.py
│   ├── requirements.txt, Dockerfile, pytest.ini, .env, .env.example
│   └── dev.db, test.db         stray SQLite files, unused by the configured PostgreSQL stack
├── frontend/                   Flutter app
│   └── lib/
│       ├── main.dart, app/     app.dart (MaterialApp.router), router.dart (GoRouter), theme/
│       ├── core/constants/     app_constants.dart
│       ├── core/errors/        EMPTY
│       ├── core/utils/         EMPTY
│       ├── features/
│       │   ├── ai_assistant/   EMPTY  (no implementation at all)
│       │   ├── auth/           models, providers, screens (splash, onboarding, login,
│       │   │                   register, forgot-password); widgets/ EMPTY
│       │   ├── calls/          screens only (3 mock screens); providers/ EMPTY; widgets/ EMPTY
│       │   ├── chat/           models, providers, screens, widgets (bubble, typing)
│       │   ├── notifications/  EMPTY
│       │   ├── profile/        screens only; providers/ EMPTY; widgets/ EMPTY
│       │   └── translation/    screens only; "{services}/" — a literal brace-named EMPTY dir
│       └── shared/             services/ (api, storage, websocket, push), widgets/ (avatar)
├── database/
│   ├── schema.sql              standalone DDL — INCOMPATIBLE with the ORM (see Finding 4.1)
│   ├── seed_data.sql           seeds messages against the incompatible schema
│   ├── migrations/             EMPTY
│   └── seeds/                  EMPTY
├── deployment/
│   ├── docker/                 docker-compose.yml, docker-compose.prod.yml
│   ├── kubernetes/             EMPTY
│   ├── nginx/                  nginx.conf, conf.d/proxy_params.conf
│   └── scripts/                setup.sh, migrate.sh, backup.sh
└── docs/                       8 markdown documents incl. PROJECT_REPORT.md, API_DOCUMENTATION.md
    ├── architecture/           SYSTEM_ARCHITECTURE.md, UML_DIAGRAMS.md
    └── diagrams/               EMPTY
```

### Empty directories are a signal worth reading

`ai_assistant/`, `notifications/`, `calls/providers/`, `calls/widgets/`, `profile/providers/`,
`profile/widgets/`, `auth/widgets/`, `core/errors/`, `core/utils/`, `backend/app/utils/`,
`database/migrations/`, `database/seeds/`, `deployment/kubernetes/`, `docs/diagrams/` and
`backend/alembic/versions/` are all empty.

The directory `frontend/lib/features/translation/{services}/` — whose name contains literal `{` and `}`
characters — is a scaffolding artefact: a shell/script template placeholder (`${services}`) that was
never substituted. It is harmless at runtime but is a clear indicator of how the tree was generated.

---

## 4. Architecture as actually built

### 4.1 Runtime topology

```
Flutter app (Dart)
   │  HTTPS  → Dio (ApiService) .............. WORKING
   │  WSS    → WebSocketService .............. NEVER CONNECTED
   ▼
FastAPI (uvicorn) ── middleware: RequestLogging → RateLimit → GZip → TrustedHost → CORS
   │
   ├── PostgreSQL (asyncpg) .................. configured; required at startup
   ├── In-memory dict ConnectionManager ...... WebSocket registry, per-process only
   ├── In-memory sliding-window rate limiter . per-process only
   ├── In-memory asyncio task per translate .. no queue
   ├── OpenAI (chat.completions, whisper, tts)  configured, key is a placeholder
   ├── Firebase Admin (FCM + ID-token verify)   optional, unconfigured
   └── AWS S3 via boto3 (sync client!) ........ optional, unconfigured

Redis ....................................... configured in .env and config.py, NEVER USED
Celery ...................................... in requirements.txt, NEVER USED
```

### 4.2 What the API surface actually is

Registered routers (`backend/app/main.py`), all under `/api/v1` and `/ws/{user_id}`:

| Router | Prefix | Notable endpoints |
|---|---|---|
| `auth` | `/auth` | register, login, firebase-login, refresh, logout, me, forgot-password (stub) |
| `users` | `/users` | profile (GET/PUT), push-token, avatar, search, `{user_id}`, contacts/list, contacts/{id}, language |
| `conversations` | `/conversations` | list, create, search, get, messages (GET/POST), message edit/delete/read, attachments, reactions, conversation read |
| `calls` | `/calls` | create, accept, reject, end, history, signal, turn-credentials |
| `translation` | `/translation` | translate, detect, batch, voice, tts, improve |
| `admin` | `/admin` | dashboard/stats, users, user status, analytics/languages, analytics/translations, system/health |
| WebSocket | `/ws/{user_id}?token=` | join/leave conversation, typing, read_receipt, call_signal, ping |

Note: the report's Appendix B lists a top-level `/api/v1/messages/` group and a
`/api/v1/translate/` prefix. Neither exists — messages are nested under `/conversations/{id}/messages`
and translation lives at `/translation`.

### 4.3 Data model as actually defined

SQLAlchemy 2.0 declarative models with `Mapped[]` typing (good, modern style):

- **`users`** — `id` UUID, `email`, `username`, `display_name`, `hashed_password`, `firebase_uid`,
  `phone`, `avatar_url`, `bio`, `preferred_language` (native PG enum), `role` (native PG enum),
  `is_online`, `last_seen`, `is_active`, `push_token`, timestamps.
- **`user_sessions`** — refresh-token store (`refresh_token` unique, `expires_at`, `is_active`).
- **`user_contacts`** — directed contact pairs with optional `nickname`.
- **`conversations`** — `type` direct|group, `name`, `description`, `avatar_url`, `created_by`.
- **`conversation_participants`** — `role` admin|member, `joined_at`, `last_read_at`.
- **`messages`** — `message_type`, `original_content`, `original_language`,
  **`translated_contents` as a `JSONB` dictionary keyed by language**, `audio_url`, `file_url`,
  `file_name`, `file_size`, `duration_seconds`, `is_edited`, `is_deleted`, `reply_to_id`, `metadata`
  (JSONB), timestamps.
- **`message_statuses`**, **`message_reactions`**.
- **`calls`**, **`call_participants`**.
- **`translations_cache`** — `text_hash`, source/target language, `original_text`, `translated_text`,
  `hit_count`, `last_used_at`. (`source_text` is exposed via a `synonym`, purely so tests can use it.)
- **`translations`** — defined but **never used anywhere** in the application.

Two design choices are worth calling out explicitly, because they differ from the report:

1. **Translations are stored as a JSONB map on the message row**, not in a separate
   `message_translations` table with one row per target language. This is a legitimate and arguably
   simpler design — it makes a message a single round-trip and avoids a join. The report describes the
   other design.
2. **Translation caching is in PostgreSQL** (`translations_cache`), not Redis. The cache key is
   `sha256(original_text)` + source + target, which is correct and language-pair-scoped.

### 4.4 The WebSocket layer (backend)

`backend/app/websocket/manager.py` is a single-process, in-memory registry:

```python
self.active_connections: Dict[str, WebSocket] = {}      # user_id -> socket  (ONE socket per user)
self.conversation_members: Dict[str, Set[str]] = {}     # conversation_id -> {user_ids}
```

It supports `send_personal_message`, `broadcast_to_conversation`, `send_new_message`,
`send_typing_indicator`, `send_message_status`, `send_call_signal`, `notify_online_status`,
and join/leave room bookkeeping. `handlers.py` verifies the JWT from the query string, compares
`sub` to the path `user_id`, flips `is_online`, and dispatches `join_conversation`,
`leave_conversation`, `typing`, `read_receipt`, `call_signal`, and `ping`.

This is a correct implementation for a **single process**. It is incompatible with the
`--workers 4` flag in `backend/Dockerfile` (Finding 5.2).

---
## 5. Backend assessment

### 5.1 What is genuinely good

The backend is the strongest part of this project and is worth being explicit about:

- **Consistently async.** `asyncpg` + `AsyncSession` + `AsyncOpenAI` throughout; no hidden sync database calls.
- **Clean layering.** `routers/` → `services/` → `models/`, with `schemas/` kept separate from ORM classes.
  Routers stay thin; business logic that is worth reusing lives in `services/`.
- **Real input validation (Pydantic v2).** Password complexity policy, `preferred_language` regex enum,
  username character pattern, min/max lengths on content and file names. Weak passwords are rejected with 422.
- **Auth done thoughtfully.** bcrypt via passlib; JWTs carry a `type` claim (`access` vs `refresh`) plus a
  `jti`; refresh tokens are rotated and tracked server-side in `user_sessions`; logout can invalidate one
  session or all of them. `get_current_user` re-checks `is_active` on every request, so deactivating a user
  takes effect immediately rather than after token expiry.
- **Access control is enforced per endpoint, not per route group.** Message, attachment, reaction and
  search endpoints all verify participation via `_require_participant`; `list_messages` and `send_message`
  verify membership before touching data. Non-participants get 403.
- **A subtle async-SQLAlchemy trap is handled deliberately.** Serialising an ORM object after `commit()`
  raises `MissingGreenlet` unless relationships are eagerly loaded. This project has an explicit helper
  (`_get_message_full`) with `selectinload` for exactly that reason, and comments explaining it. That is a
  mark of someone who hit the bug and understood it.
- **Edit window and authorship rules are enforced server-side** (sender-only, 15 minutes), not just hidden in the UI.
- **Translation failure is non-fatal by design** — `send_message` catches translation errors, logs a warning,
  and still delivers the message untranslated. Correct product decision.
- **Middleware order is deliberate and documented** (`RequestLoggingMiddleware` added last so it runs first),
  and the rate limiter correctly honours `X-Forwarded-For` behind nginx while exempting `/health` and the docs.
- **Structured logging** with one shared formatter, and noisy third-party loggers (`botocore`, `uvicorn.access`)
  quieted rather than spamming production logs.

### 5.2 Findings — architecture and correctness

**B-1 (High) — Multi-worker deployment silently breaks real-time messaging.**
`backend/Dockerfile` starts uvicorn with `--workers 4`. `ConnectionManager.active_connections` is a plain
per-process dict and there is **no Redis Pub/Sub anywhere**, despite `REDIS_URL` being configured and the
report describing broker-based fan-out. With four workers, two participants in one conversation are normally
on different processes, so `broadcast_to_conversation` reaches only the users who happen to share a worker.
The failure is intermittent and load-dependent — the worst kind to diagnose in the field. Either run a single
worker, or implement the Redis broker the documentation already claims exists.

**B-2 (High) — `database/schema.sql` is incompatible with the ORM.**
The standalone DDL and the SQLAlchemy models disagree on column names:

| `database/schema.sql` | ORM (`app/models/chat.py`, `translation.py`) |
|---|---|
| `messages.type` | `messages.message_type` |
| `messages.content` | `messages.original_content` |
| `messages.media_url` | `messages.file_url` + `messages.audio_url` |
| `messages.deleted_at` | `messages.is_deleted` |
| `translation_cache` (singular) | `translations_cache` (plural) |
| `translation_cache.source_text` | `translations_cache.original_text` |
| `notifications` table | no corresponding ORM model |

`deployment/docker/docker-compose.yml` mounts `schema.sql` and `seed_data.sql` into
`/docker-entrypoint-initdb.d/`, so Postgres creates `messages` with `type` and `content`. At startup
`init_db()` runs `Base.metadata.create_all`, which **skips tables that already exist**. The API then queries
`message_type`, `original_content` and `is_deleted` against a table that has none of them, and every message
operation fails with an undefined-column error. The documented Docker deployment path is broken as shipped.

**B-3 (High) — No migrations exist; the schema is created implicitly.**
Alembic is installed, `alembic.ini` and a correct async `alembic/env.py` are present — but
`alembic/versions/` is empty. Schema management is therefore `Base.metadata.create_all` at application
startup, which cannot alter an existing table. Any future model change silently does nothing against a
populated database, and there is no downgrade path. `deployment/scripts/migrate.sh` targets a migration
system that contains nothing.

**B-4 (High) — Every text message costs three sequential OpenAI calls, always.**
`send_message` calls `translate_message_for_all_languages(...)`, which selects *all* supported languages
other than the source and then translates them **one after another**:

```python
target_languages = [lang for lang in SUPPORTED_LANGUAGES if lang != source_language]
translations = await batch_translate(text, source_language, target_languages, db)
# batch_translate:
for target_lang in target_languages:
    result = await translate(text, source_language, target_lang, db)   # sequential awaits
```

Two consequences:

1. Translation happens into languages **nobody in the conversation speaks**. A direct chat between two
   English speakers still generates Kinyarwanda, French and Swahili translations of every message.
2. The calls are **sequential**, not concurrent. The report claims `asyncio.gather` batching; the code
   awaits each round-trip in turn, so latency is the sum, not the maximum.

This is the single largest cost and latency lever in the codebase. Translating only into the distinct
languages of the *other participants* and issuing them with `asyncio.gather` would cut both cost and latency
by roughly 3× for the common direct-chat case, and would make the 500 ms target realistic.

**B-5 (Medium) — `Message.metadata` shadows SQLAlchemy's reserved `MetaData` attribute.**
`messages.metadata: Mapped[dict | None] = mapped_column(JSONB, ...)` emits, on every import of the app:

```
SAWarning: Attribute name 'metadata' should be left reserved for the MetaData instance
when using a Declarative class.
```

Reproducible and visible in the test run output. It also collides conceptually with `Base.metadata`.
Rename it (e.g. `extra_data`).

**B-6 (Medium) — The admin API is unreachable by design.**
Every `/admin/*` endpoint depends on `require_admin`, which requires `role == UserRole.ADMIN`. However:
registration always creates `role = UserRole.USER`, `PUT /users/profile` cannot change `role`, and there is
no seed script, CLI command, environment flag or bootstrap path that promotes anyone. From a clean install,
**no user can ever call the admin API.** The Flutter app has no admin UI either — `UserModel.isAdmin` is
defined and never referenced anywhere. The "administrative dashboard" has no route into it.

**B-7 (Medium) — Email verification and password reset are stubs.**
`/auth/forgot-password` looks the address up and returns the same 202 either way (correct
anti-enumeration behaviour) but sends no email and creates no reset token; there is no
`/auth/verify-email`, no verification-token table, and **no `is_verified` field on the `User` model at all**.
FR-003 (email verification) and the password-reset flow described in the requirements are not implemented.

**B-8 (Medium) — Blocking SDKs are awaited from `async def`, stalling the event loop.**
- `FileService` uses **synchronous `boto3`**. `client.put_object` is called directly inside
  `async def upload_bytes` / `upload_file_object`, with no threadpool offload. A 25 MB document upload
  blocks that worker's entire event loop for its duration — including every other HTTP request and every
  WebSocket message — because the whole thing is one process.
- `NotificationService.send_push_notification` calls the synchronous Firebase `messaging.send(message)`
  inside an `async def`, once per recipient in a loop.

Both should be dispatched via `anyio.to_thread.run_sync` / `starlette.concurrency.run_in_threadpool`,
or replaced with an async client (`aioboto3`).

**B-9 (Medium) — The rate limiter leaks memory.**
`RateLimitMiddleware._requests` is a `defaultdict(deque)` keyed by `"{ip}:{limit}"`. Entries inside each
deque are aged out, but the **dict key itself is never deleted**. Every distinct client IP observed since
process start persists for the lifetime of the process — unbounded growth on a public deployment. Being
in-process, it also means the effective global limit is `RATE_LIMIT_PER_MINUTE × worker_count`.

**B-10 (Low/Medium) — Dead and duplicated code.**
- `VoiceService.generate_live_subtitle` — no route and no caller. The backend half of "live subtitles"
  does not exist as a feature; the only subtitles in the product are the frontend's fake ones (F-2).
- `VoiceService.process_voice_message` is reachable only through `POST /translation/voice`, which the client
  never calls.
- `POST /translation/tts` is never called by the client.
- `models/translation.py::Translation` is never instantiated anywhere in the codebase (only
  `TranslationCache` is used) — a table with no writer and no reader.
- `detect_language` exists **twice**: a module-level function returning a `str`, and a `TranslationService`
  method returning `(language, confidence)`, with subtly different heuristics. Two sources of truth for the
  same judgement.

**B-11 (Low) — Heuristic language detection is fragile.**
`LANGUAGE_HINTS` does substring matching on lowercased text. Several hints are extremely short and appear
inside unrelated words — English `"the"` occurs inside "there", French `"est"` inside "guest", and
`"je"`/`"les"`/`"are"`/`"is"` are near-universally ambiguous substrings. Short messages will be misdetected.
The design partly mitigates this because `send_message` uses the sender's stored `preferred_language` as the
source rather than detecting — but the heuristic is still what backs `/translation/detect` and
`/translation/translate` when `source_language` is omitted.

**B-12 (Low) — N+1 queries in mark-conversation-read.**
`mark_conversation_read` fetches all message ids, then issues a separate `SELECT MessageStatus` per message
id inside a loop. A long conversation means hundreds of round-trips in one request. This wants a single
bulk upsert (`INSERT ... ON CONFLICT DO UPDATE`).

**B-13 (Low) — No timeout or retry policy on OpenAI calls.**
`AsyncOpenAI(api_key=...)` is constructed with library defaults and no `timeout` / `max_retries`. In
`send_message` the call happens inside the request, before `commit()`, so a slow or hung OpenAI request holds
both the HTTP request and a database transaction open for as long as the client library allows.

**B-14 (Low) — Repository hygiene.**
- `backend/.env` is present in the working tree with a **populated `SECRET_KEY`**. If it is tracked, that is
  a leaked signing secret; tracking or not, it is the file that ended up pointing the app at Docker-only
  hostnames (`postgres`, `redis`), which is why the backend cannot start outside Compose.
- `backend/dev.db` and `backend/test.db` are stray SQLite files from before the PostgreSQL switch. Nothing
  references them — `DATABASE_URL` is Postgres — and `conftest.py` builds its own SQLite file in `tmp_path`.
- `requirements.txt` lists `celery`, `redis` and `psycopg2-binary`; none of the first two are imported
  anywhere, and `httpx` is listed twice. `DATABASE_URL_SYNC` is defined but never used.
- `pip_out.txt`, `pip_err.txt`, `pip_probe/`, `ca-bundle.pem` are build/debug debris in the repo root tree.
- There is no root `.gitignore` (only `frontend/.gitignore`), which is why the above sit in the tree.

### 5.3 Test coverage assessment

43 tests, all passing, across three files:

| File | Covers |
|---|---|
| `test_auth.py` | register (weak-password matrix, duplicate email/username, all four languages), login success/failure, `/me` authentication, refresh, logout invalidation |
| `test_messaging.py` | send, edit within window, edit authorisation, delete, react/toggle/replace, search + min-length, unread counts + mark-read, media attachment fields |
| `test_translation.py` | same-language passthrough, cache miss / hit / store, batch, detection, and the four translation HTTP endpoints with the service patched |

What this suite does well: it patches OpenAI rather than calling it, so it is deterministic and offline;
the fixtures rebuild the schema per test rather than relying on rollback (correct, because the endpoints
commit); and the auth tests exercise the unhappy paths, not just the happy one.

Gaps that matter:

- **No tests for `users`, `calls`, `admin`, or the WebSocket handler at all**, and none for
  `GET/POST /conversations` (list and create — both used by the client on every launch). Roughly half the
  API surface is unverified.
- Tests run on **SQLite**, so `JSONB`, the native Postgres `enum` types, `UUID` server defaults and the
  `translations_cache` indexes are never exercised. A Postgres-backed run would surface **B-2 immediately**.
- No test asserts that a non-participant is refused `GET /conversations/{id}/messages` — the code is
  correct, but the security property is untested.
- No load, soak, or security tests. The report's figures (100 unit + 45 integration + 73 system tests,
  91% coverage, k6 load runs, OWASP ZAP scans, 15-participant UAT with SUS 78.3) are **not reproducible
  from this repository** — no k6 scripts, no ZAP reports, no UAT instruments or raw data are present.

---
## 6. Frontend assessment

### 6.1 What is genuinely good

- **Feature-first structure** (`features/<name>/{models,providers,screens,widgets}`) with shared concerns in
  `shared/services/` and `shared/widgets/`. The layout is easy to navigate.
- **Riverpod is used idiomatically**, not fought against: `AsyncNotifierProvider` for the conversation list,
  `AsyncNotifierProviderFamily` for per-conversation messages, `StateProvider.family` for typing users,
  and `ref.invalidate(contactsProvider)` behind a `RefreshIndicator` for pull-to-refresh. This is modern,
  testable state management and it is applied consistently.
- **`ApiService` is real production plumbing.** Dio with a request interceptor that injects
  `Authorization: Bearer …` from secure storage, and an error interceptor that on a 401 refreshes the token
  once, replays the original request, and falls back to clearing storage if the refresh fails.
- **Token storage is done correctly** — `flutter_secure_storage` with
  `AndroidOptions(encryptedSharedPreferences: true)` for tokens, `SharedPreferences` for non-sensitive data
  (profile, language, onboarding flag). `LocalStorageService` is a clean typed facade over both.
- **`WebSocketService` is well engineered in isolation**: exponential backoff over `[1, 2, 5, 10, 30, 60]`
  seconds, a 30-second ping keepalive, a broadcast message stream and a separate connection-state stream.
  The problem is not its quality — it is that it is never started (F-1).
- **`MessageModel` encodes the translation contract properly** — `getContentForLanguage`,
  `hasTranslation`, `getTranslationSource`, aggregated `reactionCounts` — and `MessageBubble` implements the
  translated/original toggle (FR-016) cleanly, including a "Translated from <language>" affordance and a
  revealed original in italics.
- **`PushNotificationService` handles the genuinely awkward parts**: creating the Android notification
  channel, displaying foreground notifications manually (FCM deliberately does not show them in the
  foreground), handling `onMessageOpenedApp` and `getInitialMessage` for cold-start routing, and introducing
  a `NavigationService` indirection so the push service does not import GoRouter directly.
- **Routing is declarative** — GoRouter with a `redirect` guard keyed on auth state, a `ShellRoute` for the
  bottom navigation, and typed path parameters for chats, calls and profiles.

### 6.2 Findings

**F-1 (Critical) — The WebSocket is never connected, so real-time messaging does not exist end to end.**
`WebSocketService.connect(String userId)` has **no call site anywhere in the application**. A repository-wide
search for `.connect(` across `frontend/lib` returns exactly one hit: the internal
`WebSocketChannel.connect(uri)` inside the service itself.

`ChatScreen.initState` calls `_subscribeToWebSocket()`, which does `ws.messages.listen((event) { … })` and
correctly handles `new_message`, `typing_indicator` and `message_status`. But `ws.messages` is a broadcast
controller that only ever receives data from the channel's `stream.listen` callback, and the channel is
never created. **The screen listens to a stream that can never emit.**

Consequences, in order of severity:

1. **Messages are not delivered in real time.** A sent message appears for the sender only because
   `MessagesNotifier.sendMessage` calls `prependMessage(...)` on the local state after the REST POST
   succeeds. The recipient sees the message only when they re-open the conversation or the provider
   refetches. FR-014 (delivery within 200 ms) is not satisfied.
2. **Typing indicators never appear**, because `ws.sendTyping(...)` returns early
   (`if (_channel == null || _state != WsConnectionState.connected) return;`) and the inbound event never
   arrives.
3. **Read receipts never reach the sender.** `mark_as_read` on the server does call
   `manager.send_message_status(...)`, but the client is not listening.
4. **Online/offline presence is stale.** `update_online_status` on the server is only triggered by the
   WebSocket handler, which is never entered, so `users.is_online` stays `false` and the chat header always
   reads "Offline".
5. **Incoming-call signalling is dead** — the `call_signal` / `incoming_call` events that
   `IncomingCallScreen` depends on never arrive.

The fix is small (call `connect(currentUser.id)` once at sign-in and on reconnect) but until it is made,
the product's core real-time premise is not functioning.

**F-2 (Critical) — Voice and video calling are UI mock-ups, not an implementation.**
This is the project's headline differentiator, and no part of it is real.

- `voice_call_screen.dart` — the callee is the literal string `'Contact Name'`; `_startCall()` uses
  `Future.delayed(const Duration(seconds: 2))` then sets status to `'Connected'` and starts a local
  `Timer.periodic` as the duration counter; `_simulateSubtitles()` cycles a hard-coded four-element list
  (`'Muraho! Amakuru yawe?'`, `'(Translated: Hello! How are you?)'`, …) on a 4-second timer. There is no
  microphone capture, no peer connection, no SDP exchange.
- `video_call_screen.dart` — the "remote video" comment sits directly above a `Container` filled with a flat
  colour and a `CircleAvatar`. Captions are again a hard-coded list on a 5-second timer, under the label
  "Live Captions (English)".
- **`flutter_webrtc` is declared in `pubspec.yaml` and never imported.** A search for
  `flutter_webrtc|RTCPeerConnection|createPeerConnection` across `frontend/lib` returns nothing.
- **The entire `/calls` API is never called from the client.** A search for `/calls` finds only the router
  imports of the call *screens*.
- **Nothing navigates to the call routes.** `/call/voice/:callId`, `/call/video/:callId` and
  `/incoming-call` are registered in `router.dart` but no `context.push`/`go` targets them. The chat AppBar
  buttons are `IconButton(… onPressed: () {})` — literal no-ops.

So the calling feature is unreachable mock UI. The backend signalling endpoints (`/calls/{id}/signal`,
`accept`, `reject`, `end`, `/turn-credentials`) are implemented and waiting for a client that does not exist.

**F-3 (High) — Voice recording writes to a hard-coded POSIX `/tmp` path.**
```dart
await _recorder.start(
  const RecordConfig(),
  path: '/tmp/voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
);
```
`/tmp` does not exist on Android, iOS, or Windows — and `frontend/windows/` is a configured build target in
this repository. Recording will fail (or resolve unpredictably) on every platform the project ships for.
This must use `path_provider`'s temporary directory.

**F-4 (High) — Voice messages are neither transcribed, translated, nor playable.**
The client records audio, uploads it via `POST /conversations/{id}/attachments`, then sends a normal message
with `message_type: 'voice'` and the caption `'Voice message'`. On the server, `send_message` translates
**only when `message_type == "text"`**, and the client never calls `POST /translation/voice` (which is the
endpoint that would run Whisper → translate → TTS). So FR-019/FR-020 — automatic transcription and
translation of voice messages — are not implemented end to end. The recipient gets a URL and the literal
text "Voice message".

Compounding this: **`audioplayers` is declared in `pubspec.yaml` and never imported.**
`MessageBubble._buildVoiceMessage()` renders a play icon and a *synthetic* waveform
(`List.generate(20, (i) => Container(height: (i % 3 + 1) * 8.0))`) with no playback widget behind it.
There is no way to play a received voice message.

**F-5 (Medium) — Replying to a text message silently does nothing (ordering bug).**
```dart
_messageController.clear();
setState(() { _replyToId = null; _replyToContent = null; });   // cleared BEFORE use
try {
  await ref.read(messagesProvider(...).notifier).sendMessage(
    content: text, type: 'text', replyToId: _replyToId,          // always null
  );
```
`_replyToId` is nulled one line before it is read, so `reply_to_id` is never sent and the reply context is
always lost. The UI presents the feature fully — long-press → Reply, a reply preview bar with a cancel
button — so the failure is silent and only visible in the API payload. Note `_sendAttachment` does *not*
have this bug (it clears the state *after* the call), so attachments correctly carry `replyToId` while text
messages do not.

**F-6 (Medium) — `fontFamily: 'Poppins'` is set everywhere but no font is bundled.**
Essentially every `TextStyle` in the app sets `fontFamily: 'Poppins'`. `pubspec.yaml` contains **no `fonts:`
section at all**, and `frontend/assets/fonts/` contains **0 files**. Flutter cannot resolve the family and
silently falls back to the platform default (Roboto on Android). The intended typography — part of the
project's stated visual identity — is absent on every screen.

**F-7 (Medium) — API and WebSocket base URLs are hard-coded to `localhost`.**
```dart
static const String baseUrl   = 'http://localhost:8000/api/v1';
static const String wsBaseUrl = 'ws://localhost:8000/ws';
```
On an Android emulator `localhost` refers to the emulator, not the host — it must be `10.0.2.2`. On a
physical device it must be the host's LAN address. `backend/.env` already whitelists `http://10.0.2.2:8000`
in CORS, so the emulator case was anticipated, but the Dart constant was never parameterised. There is no
`--dart-define`, no flavour, and no HTTPS/WSS scheme, so the app cannot be pointed at any deployed backend
without editing source.

**F-8 (Low) — Declared dependencies that are never imported.**
Declared in `pubspec.yaml`, with zero imports anywhere in `lib/`:

`flutter_webrtc`, `audioplayers`, `photo_view`, `lottie`, `flutter_svg`, `badges`, `flutter_animate`,
`firebase_storage`, `cloud_firestore`, `permission_handler`, `uuid`, `json_annotation`.
Dev: `json_serializable`, `build_runner`, `riverpod_generator`, `mockito` — and no generated `*.g.dart`
files exist, confirming the codegen stack is unused and models are hand-written.

Each unused dependency is build size, an attack surface, and a version-constraint liability. `flutter_webrtc`
being unused is the significant one — it is the dependency that signals "calling is implemented".

**F-9 (Medium) — Declared assets are empty.**
`pubspec.yaml` declares `assets/images/` and `assets/icons/`; **both directories contain 0 files**, and no
image asset is referenced from `lib/` (all icons are `Icons.*` Material glyphs). Harmless today, but the
declarations point at nothing.

**F-10 (Low/Medium) — 102 analyzer issues, including one real correctness smell.**
`flutter analyze` reports **102 issues, 0 errors** — the app compiles. Two are `warning` level:
unused import in `settings_screen.dart`, unused field `_isSaving` in `language_settings_screen.dart`,
plus an unnecessary cast in `user_profile_screen.dart`.

The notable one is an `info` that is genuinely a bug class:
```
info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check
        - lib/features/translation/screens/language_settings_screen.dart:58:44
```
A `BuildContext` is used after an `await`, guarded by a check that does not actually establish the widget
is still mounted — the exact pattern that produces "Looking up a deactivated widget's ancestor" crashes.
The remaining ~98 are `deprecated_member_use` (`withOpacity`, `activeColor`) and `prefer_const_constructors`.

**F-11 (Low) — No interface localisation, despite FR-020.**
The requirements state "The interface shall be available in all four supported languages". There is no
`flutter_localizations` delegate, no `.arb` files, and no `intl` message catalogue. Every user-facing string
is a hard-coded English literal in the widget tree. Selecting a language changes the *content translation
target* only, never the UI language.

**F-12 (High) — The frontend has exactly one test, and it fails.**
`frontend/test/widget_test.dart` contains a single test asserting that `UbumweConnectApp` builds. Running it:

```
$ cd frontend; flutter test --no-pub
00:02 +0 -1: Ubumwe Connect app builds [E]
  A Timer is still pending even after the widget tree was disposed.
  Failed assertion: line 2242 pos 12: '!timersPending'
00:03 +0 -1: Some tests failed.
```

**Root cause.** `SplashScreen` is the router's `initialLocation`, so every app launch — and therefore every
test — mounts it. Its `initState` calls `_navigate()`, which opens with:

```dart
await Future.delayed(const Duration(milliseconds: 2800));
```

A `Future.delayed` cannot be cancelled by `dispose()`, so the timer outlives the widget tree and trips
`AutomatedTestWidgetsFlutterBinding`'s `!timersPending` invariant. The `if (!mounted) return;` guards that
follow are good practice, but they do not clear a pending timer.

Holding this as a `Timer?` field cancelled in `dispose()` fixes the test **and** fixes a real behavioural
consequence: a user who lands on the splash and leaves within 2.8 seconds currently leaves an uncancellable
timer behind.

A secondary design issue is visible in the same method. `SplashScreen` drives navigation imperatively
(`context.go('/home')`, `/onboarding`, `/login`) while the GoRouter `redirect` callback in `router.dart`
independently decides where an unauthenticated or authenticated user is allowed to go. Two components own
the same decision. Funnelling "where do I land" through `redirect` (or a single startup provider) would
remove the duplication — and would also make the app's landing behaviour testable without a 2.8-second wait.

Beyond this one test there is nothing: no widget tests for `MessageBubble`, `ChatScreen`, the auth forms or
any provider, and no golden or integration tests — nothing resembling the widget test coverage the report
describes.

**F-13 (Low) — Structure and polish observations.**
- `chat_screen.dart` is **631 lines** and mixes audio recording, image/file picking, WebSocket subscription,
  three modal sheets, two dialogs, list layout and input layout in one `State` class. It should be split into
  a controller/notifier plus several presentational widgets.
- No-op affordances are presented as working controls: the chat AppBar's `videocam`, `call` and `more_vert`
  buttons all have `onPressed: () {}`, as does "Flip" in the video call screen.
- Emoji are used as functional UI (a `'👋'` illustration in the empty-message state, emoji reaction rows,
  emoji flags in `AppConstants.supportedLanguages`) where icons would be more consistent.
- Several screens reference placeholder content (`'Contact Name'` on both call screens).

---
## 7. Security and API-contract review

### 7.1 Verified findings

**A-1 (Medium, verified) — Every specific 404 message is swallowed by a global status-code handler.**
`backend/app/main.py` registers:

```python
@app.exception_handler(404)
async def not_found_handler(request, exc):
    return JSONResponse(status_code=404, content={"detail": "Resource not found"})
```

In Starlette, a handler registered **by status code** takes precedence over the default `HTTPException`
handler for that code. The result is that every endpoint's carefully written 404 detail is discarded.
Verified by exercising the real app with a SQLite session and a freshly registered user:

```
GET  /api/v1/conversations/{random-uuid}        -> 404 {'detail': 'Resource not found'}
GET  /api/v1/users/{random-uuid}                -> 404 {'detail': 'Resource not found'}
POST /api/v1/conversations/{random-uuid}/messages -> 404 {'detail': 'Resource not found'}
POST /api/v1/auth/login (wrong password)        -> 401 {'detail': 'Invalid email or password'}
GET  /api/v1/no-such-route                      -> 404 {'detail': 'Resource not found'}
```

The handlers intended `"User not found"`, `"Conversation not found"` and `"Message not found"`.
Only 401 (and other codes with no registered handler) keep their detail. The test suite does not catch this
because the affected tests assert only `response.status_code == 404`, never the body.

This is a real API-contract degradation: clients cannot distinguish "this resource does not exist" from
"the route does not exist", and the Flutter error surfaces (`_extractError`) will show a generic message.
Fix: remove the status-code handlers and register a handler for `StarletteHTTPException` that passes
non-default details through, or simply let FastAPI's default handler do its job.

**S-1 (High) — Access tokens are written to the nginx access log in plaintext.**
`deployment/nginx/nginx.conf` defines:

```
log_format main '$remote_addr - $remote_user [$time_local] "$request" ...';
access_log /var/log/nginx/access.log main;
```

`$request` is the full request line **including the query string**, and the `/ws/` location block does not
override `access_log`. The client connects as:

```dart
final uri = Uri.parse('${AppConstants.wsBaseUrl}/$userId?token=$token');
```

so every WebSocket connection writes a live 30-minute access token into the access log. Anyone who can read
that log — operations staff, a log-shipping pipeline, a backup, a support tool — obtains usable credentials
for the corresponding user. Fix: authenticate the socket with a short-lived single-use ticket exchanged over
the authenticated REST API, or pass the token in `Sec-WebSocket-Protocol`; at minimum add
`access_log off;` to the `/ws/` block.

**S-2 (High) — A real signing key and real passwords are committed in `backend/.env`.**
The file contains a populated 64-hex-character `SECRET_KEY`, plus the database and Redis passwords
(`ubumwe_pass`, `redis_pass`). JWTs are signed HS256 with that key, so anyone with the file can mint valid
access and refresh tokens for **any** user id, including an admin. Treat the key as compromised: rotate it,
move it out of the repository, and add a root `.gitignore` (there is currently none — see B-14).

**S-3 (Medium) — No rate limiting or connection cap on the WebSocket endpoint.**
`RateLimitMiddleware.dispatch` returns early for `request.scope.get("type") == "websocket"`, so `/ws/{user_id}`
is completely unthrottled — an unauthenticated client can open connections freely. There is also no cap on
concurrent sockets, and since `ConnectionManager.active_connections` is a plain `Dict[str, WebSocket]`, a
second connection from the same user **silently replaces** the first. The displaced socket is orphaned: it
stays open, receives nothing (the map no longer points at it), and is only cleaned up when the client
disconnects. Multi-device use is therefore unsupported, and reconnect loops can accumulate orphans. Note the
report's own Chapter 5 sample code uses `Dict[str, List[WebSocket]]`; the implementation does not.

**S-4 (Medium) — Upload validation is extension-only, and the avatar size guard is bypassable.**
`FileService.validate_file_type` inspects the filename extension; there is no MIME sniffing, no magic-byte
check, and no content scanning — despite NFR-013 claiming uploads are "scanned for malicious content".
Separately, `upload_avatar` guards with `validate_file_size(file.size or 0, max_mb=5)`; if `UploadFile.size`
is `None`, that becomes `0 <= 5 MB` and passes, after which the whole file is read into memory and pushed to
S3. The attachment endpoint does this correctly (reads the bytes, then checks `len(data)`) — the two paths
disagree and should be unified.

**S-5 (Low) — Search terms are not escaped for `LIKE` wildcards.**
`User.username.ilike(f"%{q}%")` and the equivalent message searches are parameterised, so there is no SQL
injection. However `%` and `_` in user input are interpreted as wildcards, so searching for `%` matches every
record. Cosmetic and abusable, not a vulnerability.

**S-6 (Low) — The default trusted-host list is permissive.**
`TRUSTED_HOSTS` defaults to `["localhost", "127.0.0.1", "testserver", "test", "0.0.0.0"]`. The `test*` and
`0.0.0.0` entries exist for pytest and dev, but as a *default* they widen the Host-header allow-list in any
deployment that forgets to override it.

**S-7 (Low) — No moderation surface at all.**
`ReactionCreate.emoji` accepts any 1–16-character string, and there is no report endpoint, no
`audit_logs` table, and no admin UI (B-6). FR-036 ("view and moderate reported content") and the report's
audit-logging claims have no implementation.

### 7.2 What the security design gets right

These are worth stating, because the security posture is not uniformly weak:

- **No SQL injection surface.** All access goes through the SQLAlchemy ORM with bound parameters; there is no
  raw SQL, no string-formatted query, and no `text()` with interpolation anywhere in `app/`.
- **Password hashing is correct** — bcrypt via passlib, never a reversible encoding, never logged.
- **JWTs separate access from refresh** with a `type` claim that `get_current_user` and the refresh endpoint
  both check, so a refresh token cannot be used as an access token.
- **Refresh tokens are rotated and revocable server-side** (`user_sessions`), and logout invalidates them.
- **`is_active` is re-checked on every request**, so deactivating a user takes effect immediately rather than
  when their token expires.
- **Authorisation is positive-path**: every conversation resource checks participation explicitly rather than
  relying on the URL being unguessable.
- **CORS uses an explicit origin allow-list** with `allow_credentials=True` — not a wildcard, which would be
  invalid with credentials anyway.
- **The container runs as a non-root user**, nginx has `server_tokens off` and sets
  `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy` and a CSP.
- **Generic 500 bodies** rather than stack traces, and Pydantic validation on all request bodies.

One dependency item to verify rather than assume: `requirements.txt` pins `passlib[bcrypt]==1.7.4` but does
not pin `bcrypt` itself. passlib 1.7.4 is known to misread the version of bcrypt ≥ 4.1 (it removed
`bcrypt.__about__`), which produces errors on hash verification in some combinations. The resolved version in
`backend/.venv` should be pinned explicitly.

---

## 8. Dependency, build and deployment health

**Backend dependencies.** `requirements.txt` has no lock file and contains unused entries: `celery` and
`redis` are never imported, `psycopg2-binary` is unused (everything is asyncpg), and `httpx` is listed twice.
`DATABASE_URL_SYNC` is defined in settings and never read.

**Docker.** `backend/Dockerfile` is a two-stage build that installs into a non-root user's home, sets
`PYTHONUNBUFFERED`, exposes a healthcheck via `curl`, and is referenced correctly by
`docker-compose.yml` (`target: production`). Two problems:

1. `--workers 4` is incompatible with the in-memory WebSocket registry and rate limiter (B-1, B-9).
2. `docker-compose.yml` mounts `../../backend:/app`, which shadows the code baked into the image with the
   host working tree. That is normal for a *development* compose file, but it means the image's `COPY . .`
   is only exercised in production — and it also mounts `schema.sql`/`seed_data.sql` into `initdb`, which is
   the source of B-2.

**nginx.** The reverse-proxy configuration is competent: `least_conn` upstream with `keepalive`,
per-location rate-limit zones with separate stricter buckets for auth and translation, `client_max_body_size`
tuned per upload route, and `proxy_read_timeout 86400` for WebSockets. Gaps: it listens on **port 80 only**,
so there is no TLS termination here at all, despite NFR-008 and the report's "TLS 1.3 enforced" claim; and
`/ws/` logs tokens (S-1).

**No CI.** There is no `.github/workflows/`, no `.gitlab-ci.yml`, no `Jenkinsfile` — nothing. The report
claims `safety` scanning is integrated in CI and that OWASP ZAP scans were run; neither is present.

**Empty infrastructure directories.** `deployment/kubernetes/`, `database/migrations/`, `database/seeds/`
and `backend/alembic/versions/` all exist but contain nothing.

**Repository hygiene.** No root `.gitignore`. `backend/dev.db`, `backend/test.db`, `backend/pip_out.txt`,
`backend/pip_err.txt`, `backend/pip_probe/` and `backend/ca-bundle.pem` are committed working-tree debris,
and `backend/.env` carries a live secret (S-2).

---
## 9. Prioritised remediation roadmap

Ordered by "value delivered per unit of effort", not by severity of the label. Items 1-6 are small changes
that turn the existing code into something that actually works.

### P0 — Make the product do what it already claims (hours, not days)

1. **Call `WebSocketService.connect(userId)`.** Connect on login and on session restore, disconnect on
   logout. Reconnect is already handled internally. This single change restores real-time message delivery,
   typing indicators, read receipts and online presence (F-1).
2. **Fix the reply ordering bug** in `_sendMessage` — move the `setState` that clears `_replyToId` to after
   the `await` (F-5). One-line move.
3. **Replace the hard-coded `/tmp` recording path** with `path_provider`'s temp directory (F-3).
4. **Remove the `@app.exception_handler(404)` / `(500)` status-code handlers** in `main.py`, or re-register
   them against `StarletteHTTPException` in a way that preserves non-default `detail` (A-1).
5. **Reconcile `database/schema.sql` with the ORM** — either regenerate it from the models or stop mounting
   it into `initdb` and let the application own the schema (B-2). Without this, the documented Docker
   deployment does not work at all.
6. **Set `--workers 1`** in the Dockerfile until a broker exists (B-1). Multi-worker with in-memory socket
   state is worse than single-worker, because the failure is silent.

### P1 — Correctness, cost and security

7. **Translate only into the languages the other participants actually speak, concurrently.**
   Derive the target set from `conversation.participants[*].user.preferred_language`, then
   `await asyncio.gather(*(translate(...) for lang in targets))`. This is the largest cost and latency win
   available — roughly 3x fewer API calls for a direct chat, and sum-latency becomes max-latency (B-4).
8. **Rotate `SECRET_KEY`, move it out of the repo, add a root `.gitignore`** (S-2, B-14).
9. **Stop logging tokens:** add `access_log off;` to the nginx `/ws/` block, and move the token off the
   query string onto a header or a short-lived ticket (S-1).
10. **Offload blocking SDK calls to a threadpool** — `boto3` uploads and Firebase `messaging.send` (B-8).
11. **Write the initial Alembic migration** and stop relying on `create_all` (B-3).
12. **Add an admin bootstrap path** — promote an address listed in settings at startup, or provide a CLI
    command — so the admin API is reachable at all (B-6).
13. **Rename `Message.metadata`** to something non-reserved and stop the SAWarning (B-5).
14. **Bound the rate limiter's key map** and add a WebSocket connection cap plus support for multiple
    sockets per user (B-9, S-3).
15. **Add explicit timeouts and a retry policy to the OpenAI client** (B-13).

### P2 — Close the feature gap, or stop claiming it

16. **Decide on calling.** Either implement WebRTC properly — `flutter_webrtc` peer connections, the existing
    `/calls/{id}/signal` endpoint for SDP/ICE relay, `/turn-credentials` for relays, and working navigation
    from the chat header — or delete the three call screens, the `/calls` router, and the WebRTC/TURN
    claims. As it stands the mock screens assert a capability that does not exist, which is worse than
    having no calling feature at all (F-2).
17. **Wire voice messages end to end:** send `message_type: 'voice'` through the transcription path, and use
    `audioplayers` to make the bubble playable (F-4).
18. **Resolve FR-032.** Implement the AI assistant, or remove the empty directory and the requirement (F-13).
19. **Add `flutter_localizations` and ARB catalogues** if a four-language interface is genuinely required (F-11).
20. **Bundle Poppins, or remove the `fontFamily` overrides** so intent matches reality (F-6).
21. **Parameterise `baseUrl` / `wsBaseUrl`** via `--dart-define`, with `10.0.2.2` for the Android emulator
    and WSS/HTTPS support (F-7).
22. **Prune unused dependencies and empty directories** (F-8, section 3).

### P3 — Tests and documentation honesty

23. **Extend the backend suite** to `users`, `conversations` list/create, `calls`, `admin` and the WebSocket
    handler. Add a Postgres-backed run (for example via `testcontainers`) so B-2 cannot recur undetected.
24. **Add a widget test** for the `MessageBubble` translation toggle and the `ChatScreen` send flow.
25. **Reconcile `docs/PROJECT_REPORT.md` with the implementation.** The report currently describes Redis
    Pub/Sub, a separate `message_translations` table, `ai_messages`, `audit_logs` and `push_tokens` tables,
    S3 pre-signed direct uploads, BLoC/Cubit state management, WCAG 2.1 AA compliance, 24-hour access tokens
    and a ~218-test regime — none of which match the code. Note in particular that the report names BLoC as
    the frontend state-management choice while the code uses Riverpod throughout.
26. **Add a root `.gitignore`** and remove `dev.db`, `test.db`, `pip_out.txt`, `pip_err.txt`,
    `pip_probe/` and `ca-bundle.pem` from the tree (B-14).
27. **Hold the splash delay in a cancellable `Timer?` and cancel it in `dispose()`**, so the frontend suite
    goes green and leaving the splash early stops leaking a timer. Then decide whether landing-page
    selection belongs in `SplashScreen` or in GoRouter's `redirect` — currently both do it (F-12). This one
    is small enough to fold into the P0 pass.

---

## 10. Running the project today

**The backend cannot be started locally as shipped.** `backend/.env` points `DATABASE_URL` at host
`postgres` and `REDIS_URL` at host `redis` — both are Docker Compose service names. Probed directly, both
fail DNS resolution on the host, so the `lifespan` startup hook cannot complete `init_db()` and the app does
not come up. The OpenAI key is the placeholder `sk-placeholder-add-your-key-here`, AWS credentials are empty,
`FIREBASE_CREDENTIALS_PATH` is empty and `TURN_SERVER_URL` is empty.

Two workable paths:

* **Intended path (Docker).** `docker compose -f deployment/docker/docker-compose.yml up`. This will start
  Postgres, Redis, pgAdmin and the backend — but the database is initialised from the incompatible
  `database/schema.sql`, so message endpoints fail until B-2 is fixed (or until the `initdb` mounts are
  removed).
* **Verified path (tests / local dev).** `backend/.venv` exists with the dependencies installed. Running
  `cd backend; .venv\Scripts\python.exe -m pytest tests -q` gives **43 passed** using a SQLite database and a
  `get_db` override — no Postgres, no Redis, no network. The same technique (SQLite URL plus a dependency
  override) is what was used above to exercise the real app and verify A-1.

For translation to work at all, a real `OPENAI_API_KEY` must be supplied; without it, messages are still
stored and returned, because `send_message` deliberately swallows translation errors and delivers the
original text.

**Frontend.** `flutter analyze --no-pub` reports 102 issues and **0 errors**, so the app compiles. Running it
requires a reachable backend; on an Android emulator the hard-coded `localhost` in `AppConstants` must be
changed to `10.0.2.2` (F-7). Neither Firebase nor push notifications will initialise without configuration —
`main.dart` guards both with try/catch, so the app degrades rather than crashing.

---

## 11. Overall assessment

**Strengths.** The backend is a genuinely competent, modern async FastAPI service: clean layering, real
Pydantic validation, thoughtful authentication with refresh-token rotation and server-side revocation,
correct per-endpoint authorisation, deliberate handling of async-SQLAlchemy eager-loading pitfalls, and a
small but meaningful passing test suite that exercises the unhappy paths. The Flutter app is well organised,
uses Riverpod idiomatically, ships a properly built Dio client with transparent token refresh, stores tokens
in secure storage, and contains a well-engineered WebSocket client and push-notification service. The
authentication, conversation-list, chat-rendering, contacts, profile and attachment flows are wired end to
end and would work against a functioning backend.

**The central problem is a systematic divergence between the documentation and the code.** `PROJECT_REPORT.md`
describes a system with WebRTC calling, live translated subtitles, an AI assistant, an administrative
dashboard, Redis-backed horizontal scaling, a migration-managed schema, end-to-end encryption in transit
with TLS 1.3 enforced, and a ~218-test quality regime. What the repository contains is a well-built backend
for messaging and translation, a partially wired client, and mock screens for the differentiating features.
Of the report's ten declared "achieved" objectives, the translation pipeline, the REST API, group-conversation
translation and the cross-platform application are real; the real-time delivery, calling, subtitle, AI
assistant and admin objectives are not.

**Two things worth stating plainly.**

First, the claim at the heart of the project — seamless real-time multilingual conversation — cannot currently
be demonstrated, because messages never travel between two users in real time (F-1). The translation engine
works, the storage works, the UI works; only the transport between users is missing, and it is missing for
want of one function call. That single fix changes the demo more than anything else on this list.

Second, several of the most consequential defects found here are small and unglamorous: a nullable variable
cleared one line too early, a `/tmp` path on platforms without `/tmp`, an unused `connect()` method, a status
code handler that shadows another. None of them are architectural. All of them are the difference between a
system that works and one that does not, and all of them are cheap to fix. They are worth clearing before any
further feature work begins.

**Suggested immediate scope (one focused pass).** Items 1-6 of the P0 list, which together restore real-time
messaging, fix two silent client bugs, correct the API's error contract, and make the documented deployment
path actually start. That is a small, self-contained body of work with a disproportionate effect on whether
the project demonstrates what it sets out to demonstrate.
