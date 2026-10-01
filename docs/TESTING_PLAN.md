# Ubumwe Connect — Testing Plan

**Version:** 1.0.0  
**Test Strategy:** Multi-layer (unit → integration → system → UAT)

---

## Table of Contents

1. [Testing Strategy Overview](#1-testing-strategy-overview)
2. [Backend Unit Tests](#2-backend-unit-tests)
3. [Backend Integration Tests](#3-backend-integration-tests)
4. [Flutter Unit & Widget Tests](#4-flutter-unit--widget-tests)
5. [API Endpoint Tests](#5-api-endpoint-tests)
6. [WebSocket Tests](#6-websocket-tests)
7. [Translation Service Tests](#7-translation-service-tests)
8. [Performance Tests](#8-performance-tests)
9. [Security Tests](#9-security-tests)
10. [User Acceptance Test Cases](#10-user-acceptance-test-cases)

---

## 1. Testing Strategy Overview

```
                    ┌─────────────────────────────────┐
     Slowest/       │  UAT / End-to-End (manual)      │
     Most costly    │  Real users, real devices        │
                    ├─────────────────────────────────┤
                    │  System / Integration Tests      │
                    │  Full stack, real DB + Redis      │
                    ├─────────────────────────────────┤
     Fastest/       │  Unit Tests                     │
     Cheapest       │  Isolated functions/services     │
                    └─────────────────────────────────┘
```

**Tools Used:**
| Layer | Tool |
|-------|------|
| Backend unit | pytest, pytest-asyncio |
| Backend API | httpx (async test client) |
| Backend coverage | pytest-cov |
| Flutter unit | flutter_test |
| Flutter widget | flutter_test + flutter_riverpod |
| Flutter coverage | flutter test --coverage |
| Performance | Locust (Python) |
| Security | OWASP ZAP (automated scan) |

---

## 2. Backend Unit Tests

### `backend/tests/test_auth.py`

```python
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_register_success(async_client: AsyncClient):
    """Test successful user registration."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": "test@example.com",
        "username": "test_user",
        "display_name": "Test User",
        "password": "SecurePass@123",
        "preferred_language": "english"
    })
    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["user"]["email"] == "test@example.com"

@pytest.mark.asyncio
async def test_register_duplicate_email(async_client: AsyncClient):
    """Test registration with already-used email fails."""
    payload = {
        "email": "duplicate@example.com",
        "username": "user1",
        "display_name": "User One",
        "password": "SecurePass@123",
        "preferred_language": "english"
    }
    await async_client.post("/api/v1/auth/register", json=payload)
    payload["username"] = "user2"
    response = await async_client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 409

@pytest.mark.asyncio
async def test_login_success(async_client: AsyncClient, test_user):
    """Test successful login."""
    response = await async_client.post("/api/v1/auth/login", json={
        "email": test_user["email"],
        "password": "SecurePass@123"
    })
    assert response.status_code == 200
    assert "access_token" in response.json()

@pytest.mark.asyncio
async def test_login_wrong_password(async_client: AsyncClient, test_user):
    """Test login with wrong password."""
    response = await async_client.post("/api/v1/auth/login", json={
        "email": test_user["email"],
        "password": "WrongPassword@123"
    })
    assert response.status_code == 401

@pytest.mark.asyncio
async def test_get_me_authenticated(async_client: AsyncClient, auth_headers):
    """Test /me endpoint with valid token."""
    response = await async_client.get("/api/v1/auth/me", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "id" in data
    assert "email" in data

@pytest.mark.asyncio
async def test_get_me_unauthenticated(async_client: AsyncClient):
    """Test /me endpoint without token."""
    response = await async_client.get("/api/v1/auth/me")
    assert response.status_code == 401

@pytest.mark.asyncio
async def test_token_refresh(async_client: AsyncClient, test_user_tokens):
    """Test refresh token exchange."""
    response = await async_client.post("/api/v1/auth/refresh", json={
        "refresh_token": test_user_tokens["refresh_token"]
    })
    assert response.status_code == 200
    assert "access_token" in response.json()

@pytest.mark.asyncio
async def test_password_complexity_validation(async_client: AsyncClient):
    """Test weak passwords are rejected."""
    for weak_pass in ["password", "12345678", "NODIGITS!", "Short1!"]:
        response = await async_client.post("/api/v1/auth/register", json={
            "email": "weak@example.com",
            "username": "weak_user",
            "display_name": "Weak User",
            "password": weak_pass,
            "preferred_language": "english"
        })
        assert response.status_code == 422, f"Expected 422 for password: {weak_pass}"
```

### `backend/tests/test_translation.py`

```python
import pytest
from unittest.mock import AsyncMock, patch
from app.services.translation_service import TranslationService

@pytest.mark.asyncio
async def test_translate_text_cache_miss(db_session):
    """Test translation when cache is empty (calls OpenAI)."""
    with patch("app.services.translation_service.openai_client") as mock_openai:
        mock_openai.chat.completions.create = AsyncMock(return_value=MockCompletion("Hello!"))
        service = TranslationService(db_session)
        result = await service.translate_text("Muraho!", "kinyarwanda", "english")
        assert result == "Hello!"
        mock_openai.chat.completions.create.assert_called_once()

@pytest.mark.asyncio
async def test_translate_text_cache_hit(db_session, seed_translation_cache):
    """Test translation returns cached result without calling OpenAI."""
    with patch("app.services.translation_service.openai_client") as mock_openai:
        service = TranslationService(db_session)
        result = await service.translate_text("Muraho!", "kinyarwanda", "english")
        assert result == "Hello!"
        mock_openai.chat.completions.create.assert_not_called()  # Cache hit!

@pytest.mark.asyncio
async def test_translate_same_language(db_session):
    """Test that translating to same language returns unchanged text."""
    service = TranslationService(db_session)
    result = await service.translate_text("Hello!", "english", "english")
    assert result == "Hello!"

@pytest.mark.asyncio
async def test_batch_translate_all_languages(db_session):
    """Test batch translation to all 4 languages."""
    with patch("app.services.translation_service.openai_client") as mock_openai:
        mock_openai.chat.completions.create = AsyncMock(
            side_effect=[
                MockCompletion("Muraho!"),
                MockCompletion("Bonjour!"),
                MockCompletion("Habari!"),
            ]
        )
        service = TranslationService(db_session)
        result = await service.translate_for_all_languages("Hello!", "english")
        assert result["english"] == "Hello!"
        assert result["kinyarwanda"] == "Muraho!"
        assert result["french"] == "Bonjour!"
        assert result["swahili"] == "Habari!"

@pytest.mark.asyncio
async def test_detect_language_kinyarwanda(db_session):
    """Test language detection for Kinyarwanda."""
    with patch("app.services.translation_service.openai_client") as mock_openai:
        mock_openai.chat.completions.create = AsyncMock(
            return_value=MockCompletion('{"language": "kinyarwanda", "confidence": 0.95}')
        )
        service = TranslationService(db_session)
        lang, confidence = await service.detect_language("Muraho! Amakuru yawe?")
        assert lang == "kinyarwanda"
        assert confidence >= 0.9
```

---

## 3. Backend Integration Tests

### `backend/tests/test_conversations.py`

```python
@pytest.mark.asyncio
async def test_create_direct_conversation(async_client, auth_headers, second_user):
    """Test creating a direct message conversation."""
    response = await async_client.post(
        "/api/v1/conversations",
        json={"participant_ids": [second_user["id"]], "type": "direct"},
        headers=auth_headers
    )
    assert response.status_code == 201
    data = response.json()
    assert data["type"] == "direct"
    assert len(data["participants"]) == 2

@pytest.mark.asyncio
async def test_send_message_triggers_translation(async_client, auth_headers, conversation):
    """Test that sending a message auto-translates for all participants."""
    response = await async_client.post(
        f"/api/v1/conversations/{conversation['id']}/messages",
        json={"content": "Hello!", "type": "text"},
        headers=auth_headers
    )
    assert response.status_code == 201
    data = response.json()
    # translated_contents should have entries for all participant languages
    assert "kinyarwanda" in data.get("translated_contents", {}) or \
           data.get("original_language") == "kinyarwanda"

@pytest.mark.asyncio
async def test_get_messages_pagination(async_client, auth_headers, conversation_with_messages):
    """Test cursor-based message pagination."""
    response = await async_client.get(
        f"/api/v1/conversations/{conversation_with_messages['id']}/messages?limit=10",
        headers=auth_headers
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data["messages"]) <= 10
    assert "has_more" in data
    assert "next_cursor" in data
```

---

## 4. Flutter Unit & Widget Tests

### `frontend/test/auth_provider_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('AuthNotifier', () {
    test('login success updates user state', () async {
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(MockApiService())],
      );
      // ... test login flow
    });

    test('login failure throws AuthException', () async {
      // ... test error handling
    });

    test('logout clears tokens and user state', () async {
      // ... test logout flow
    });
  });
}
```

### `frontend/test/message_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ubumwe_connect/features/chat/models/message_model.dart';

void main() {
  group('MessageModel', () {
    final testMessage = MessageModel(
      id: 'test-id',
      conversationId: 'conv-id',
      senderId: 'sender-id',
      type: 'text',
      content: 'Muraho!',
      originalLanguage: 'kinyarwanda',
      translatedContents: {
        'kinyarwanda': 'Muraho!',
        'english': 'Hello!',
        'french': 'Bonjour!',
        'swahili': 'Habari!',
      },
      createdAt: DateTime.now(),
    );

    test('getContentForLanguage returns correct translation', () {
      expect(testMessage.getContentForLanguage('english'), 'Hello!');
      expect(testMessage.getContentForLanguage('french'), 'Bonjour!');
      expect(testMessage.getContentForLanguage('kinyarwanda'), 'Muraho!');
    });

    test('getContentForLanguage falls back to content when no translation', () {
      expect(testMessage.getContentForLanguage('swahili'), 'Habari!');
    });

    test('hasTranslation returns true for translated languages', () {
      expect(testMessage.hasTranslation('english'), isTrue);
      expect(testMessage.hasTranslation('english'), isTrue);
    });

    test('isFromMe returns true when senderId matches', () {
      expect(testMessage.isFromMe('sender-id'), isTrue);
      expect(testMessage.isFromMe('other-id'), isFalse);
    });
  });
}
```

---

## 5. API Endpoint Tests

### Test Matrix

| Endpoint | Method | Tests |
|----------|--------|-------|
| `/auth/register` | POST | ✅ success, ❌ duplicate email, ❌ weak password, ❌ missing fields |
| `/auth/login` | POST | ✅ success, ❌ wrong password, ❌ unknown email |
| `/auth/refresh` | POST | ✅ valid token, ❌ expired token, ❌ invalid token |
| `/auth/me` | GET | ✅ authenticated, ❌ unauthenticated |
| `/users/profile` | PUT | ✅ update name, ✅ update language, ❌ duplicate username |
| `/users/search` | GET | ✅ finds user, ✅ no results, ✅ partial match |
| `/conversations` | POST | ✅ direct, ✅ group, ❌ no participants, ❌ self-chat |
| `/conversations/{id}/messages` | POST | ✅ text, ✅ triggers translation, ❌ not a participant |
| `/translation/translate` | POST | ✅ hit cache, ✅ miss cache, ✅ same language |
| `/translation/detect` | POST | ✅ kinyarwanda, ✅ english, ✅ french, ✅ swahili |
| `/calls/initiate` | POST | ✅ voice, ✅ video, ❌ not in conversation |

---

## 6. WebSocket Tests

### Connection Tests
- ✅ Connect with valid JWT token
- ❌ Connect with expired token → 401 disconnect
- ❌ Connect with no token → 403 disconnect
- ✅ Reconnect after network interruption (exponential backoff)

### Message Flow Tests
- ✅ User A sends message → User B receives `new_message` event
- ✅ Message delivered in User B's preferred language
- ✅ Typing indicator broadcast to conversation participants
- ✅ Read receipt marks messages as read
- ✅ Online status updates broadcast to contacts

### Performance Tests
- ✅ 1000 concurrent WebSocket connections stable for 10 minutes
- ✅ Message delivery latency < 200ms under normal load
- ✅ Memory usage stays below 2GB under 1000 connections

---

## 7. Translation Service Tests

### Accuracy Tests

| Source Text | Source Lang | Expected (EN) | Acceptable Range |
|-------------|-------------|---------------|-----------------|
| "Muraho! Amakuru yawe?" | kinyarwanda | "Hello! How are you?" | Semantic equivalent |
| "Bonjour! Comment ça va?" | french | "Hello! How are you?" | Semantic equivalent |
| "Habari za asubuhi!" | swahili | "Good morning!" | Semantic equivalent |
| "Ndakunda gukora kode" | kinyarwanda | "I love coding" | Semantic equivalent |

### Cache Efficiency Tests
- After 100 unique messages, cache hit rate > 0%
- After 1000 messages with repetition, cache hit rate > 60%
- Cache lookup P99 latency < 5ms

### Error Handling Tests
- ✅ OpenAI API timeout → graceful fallback (return original text)
- ✅ OpenAI rate limit → retry with exponential backoff
- ✅ Invalid language code → 422 validation error
- ✅ Empty text input → 422 validation error

---

## 8. Performance Tests

### Load Test Scenarios (Locust)

```python
# locustfile.py
from locust import HttpUser, task, between

class ChatUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        response = self.client.post("/api/v1/auth/login", json={
            "email": "test@example.com",
            "password": "TestPass@123"
        })
        self.token = response.json()["access_token"]
        self.headers = {"Authorization": f"Bearer {self.token}"}

    @task(3)
    def get_conversations(self):
        self.client.get("/api/v1/conversations", headers=self.headers)

    @task(5)
    def send_message(self):
        self.client.post(
            "/api/v1/conversations/test-conv-id/messages",
            json={"content": "Test message", "type": "text"},
            headers=self.headers
        )

    @task(1)
    def translate(self):
        self.client.post(
            "/api/v1/translation/translate",
            json={"text": "Hello!", "source_language": "english", "target_language": "kinyarwanda"},
            headers=self.headers
        )
```

### Performance Targets

| Metric | Target | Critical Threshold |
|--------|--------|-------------------|
| API P50 latency | < 100ms | < 500ms |
| API P99 latency | < 500ms | < 2000ms |
| Translation P50 | < 200ms (cached) | < 3000ms (uncached) |
| WebSocket message delivery | < 200ms | < 1000ms |
| Concurrent users | 500 | 1000 |
| Error rate under load | < 0.1% | < 1% |

---

## 9. Security Tests

### Authentication & Authorization

| Test | Expected Result |
|------|----------------|
| Access resource with expired token | 401 Unauthorized |
| Access another user's messages | 403 Forbidden |
| Access conversation without membership | 403 Forbidden |
| SQL injection in search query | 422 or sanitized result |
| XSS in display_name | Content stored/returned as-is (no HTML rendering) |
| Brute-force 20 login attempts | 429 Too Many Requests |

### OWASP Top 10 Checklist

- [x] **A01 Broken Access Control** — Conversation membership checked server-side
- [x] **A02 Cryptographic Failures** — JWT HS256, bcrypt passwords, TLS in transit
- [x] **A03 Injection** — SQLAlchemy ORM prevents SQL injection
- [x] **A04 Insecure Design** — Auth tokens expire, refresh tokens single-use
- [x] **A05 Security Misconfiguration** — Debug=false in prod, no default passwords
- [x] **A06 Vulnerable Components** — Dependencies audited with `pip audit` + `flutter pub outdated`
- [x] **A07 Auth Failures** — Rate limiting, account lockout, secure sessions
- [x] **A08 Integrity Failures** — CI/CD pipeline with signed commits
- [x] **A09 Logging Failures** — Structured logs, auth events logged
- [x] **A10 SSRF** — External API calls go only to whitelisted OpenAI/Firebase endpoints

---

## 10. User Acceptance Test Cases

### UAT-001: New User Onboarding

**Steps:**
1. Download app and open for first time
2. View all 3 onboarding screens
3. Tap "Get Started"
4. Register with email, select Kinyarwanda as language
5. Verify welcome screen appears

**Expected:** User successfully creates account and lands on empty Chats tab

---

### UAT-002: Cross-Language Messaging

**Participants:** User A (Kinyarwanda), User B (English)

**Steps:**
1. User A sends "Muraho neza!" in Kinyarwanda
2. User B opens conversation

**Expected:** User B sees "Hello there!" (or equivalent English translation), with "🌐 Translated from Kinyarwanda" label

---

### UAT-003: Group Chat with 4 Languages

**Participants:** 4 users — one per language

**Steps:**
1. Create group with all 4 users
2. Each user sends a greeting in their language
3. All users check the group

**Expected:** Each user sees all 3 other messages in their own language

---

### UAT-004: Voice Message Translation

**Steps:**
1. User A records voice message in French: "Bonjour tout le monde!"
2. User B (English) receives the message

**Expected:** User B sees text transcript + English translation displayed under the voice note

---

### UAT-005: Video Call with Live Subtitles

**Steps:**
1. User A (Kinyarwanda) calls User B (English) via video
2. User A speaks: "Ndakunda gukora kode"
3. User B views the call screen

**Expected:** User B sees live caption "I love coding" on screen within 3 seconds of User A speaking

---

### UAT-006: Language Change Persistence

**Steps:**
1. User changes preferred language from English to French in Settings
2. User closes and reopens the app
3. User checks an old conversation

**Expected:** Messages now display in French; setting persists after restart

---

### UAT-007: Offline Notification

**Steps:**
1. User B has app in background (offline)
2. User A sends a message to User B
3. User B checks their device

**Expected:** Push notification appears with sender name and translated message preview

---

### UAT-008: Contact Search & Add

**Steps:**
1. Go to Contacts tab → tap person+ icon
2. Search for username "amara_gasana"
3. Tap "Add"
4. Navigate back to Contacts tab

**Expected:** amara_gasana now appears in contacts list

---

## Test Execution

### Running Backend Tests

```bash
cd backend
pytest tests/ -v --cov=app --cov-report=html
open htmlcov/index.html
```

### Running Flutter Tests

```bash
cd frontend
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Coverage Targets

| Module | Target Coverage |
|--------|----------------|
| Backend auth service | ≥ 90% |
| Backend translation service | ≥ 85% |
| Backend routers | ≥ 80% |
| Flutter providers | ≥ 75% |
| Flutter models | ≥ 90% |
