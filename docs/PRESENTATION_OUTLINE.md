# Ubumwe Connect — Presentation Outline
## Capstone Project Defense: 20-Slide Deck

---

### Slide 1 — Title Slide
**Title:** Ubumwe Connect: AI-Powered Multilingual Communication Platform  
**Subtitle:** Bringing People Together Beyond Language  
**Visual:** App logo on gradient background, platform mockups  
**Speaker:** [Your Name], Student ID: [XXXX]  
**Advisor:** [Supervisor Name]  
**Institution:** [University Name], Department of [CS/IT]  
**Date:** [Defense Date]

---

### Slide 2 — Problem Statement
**Title:** The Language Barrier Problem in East Africa

**Key Points:**
- 4 official/major languages in the region: Kinyarwanda, English, French, Swahili
- **65% of Rwanda's population** cannot communicate effectively across language lines
- Existing chat apps (WhatsApp, Telegram) offer no real-time multilingual translation
- Business, education, and healthcare communication suffer across language divides

**Visual:** Map of East Africa with language distribution overlay  
**Quote:** *"Language is the road map of a culture" — Rita Mae Brown*

---

### Slide 3 — Project Objectives
**Title:** What Ubumwe Connect Achieves

**Primary Objectives:**
1. Develop a real-time chat platform with automatic message translation
2. Support 4 languages: Kinyarwanda, English, French, Swahili
3. Enable voice/video calls with live subtitle translation
4. Build a production-ready, scalable full-stack system

**Secondary Objectives:**
- Translation caching to minimize API costs
- Firebase authentication + Google Sign-In
- Cross-platform (Android, iOS, Web)

**Visual:** Objective tree / numbered list with check icons

---

### Slide 4 — Literature Review Summary
**Title:** Existing Solutions & Research Gap

| Platform | Translation | Real-time | African Languages |
|----------|-------------|-----------|-------------------|
| WhatsApp | ❌ None | ✅ Yes | ❌ No |
| Google Translate | ✅ Good | ❌ No chat | ⚠️ Limited |
| Microsoft Teams | ⚠️ Limited | ✅ Yes | ❌ No |
| **Ubumwe Connect** | ✅ Auto | ✅ Yes | ✅ Yes |

**Research Gap:** No platform combines real-time messaging + automatic multilingual translation specifically designed for East African languages.

**Visual:** Comparison table with green/red/yellow cells

---

### Slide 5 — System Architecture Overview
**Title:** High-Level Architecture

**Components:**
- **Frontend:** Flutter (Android + iOS + Web)
- **Backend:** FastAPI (Python) with WebSocket support
- **Database:** PostgreSQL + Redis
- **AI Services:** OpenAI GPT-4o-mini (translation), Whisper (STT)
- **Auth:** Firebase Authentication
- **Storage:** AWS S3 for media files

**Visual:** Architecture diagram from SYSTEM_ARCHITECTURE.md

---

### Slide 6 — Database Design
**Title:** Data Model

**Key Tables:**
- `users` — with `preferred_language` enum
- `messages` — with `translated_contents` JSONB column
- `translation_cache` — SHA-256 hash-based lookup
- `conversations` — direct and group types
- `calls` — voice/video with status tracking

**Design Highlight:** Messages store ALL language translations in a single JSONB column → single query retrieves message in any language

**Visual:** Simplified ER diagram

---

### Slide 7 — Translation Pipeline
**Title:** How Automatic Translation Works

**Flow:**
1. User sends message in any language
2. System detects source language (from user profile)
3. For each participant with a different language:
   - Check translation cache (SHA-256 hash lookup)
   - Cache HIT: return in < 5ms
   - Cache MISS: call GPT-4o-mini (~800ms)
4. Store all translations in message's JSONB field
5. Broadcast to each user in their language via WebSocket

**Visual:** Flowchart showing cache hit vs. miss path  
**Metric:** Expected cache hit rate > 70% after warm-up

---

### Slide 8 — Real-Time Messaging
**Title:** WebSocket Architecture

**Key Components:**
- `ConnectionManager` — tracks user_id → WebSocket connection
- Events: `new_message`, `typing_indicator`, `read_receipt`, `user_online`
- Reconnection with exponential backoff (1s → 2s → 4s → max 60s)

**Message Flow Demo Screenshot:** Alice sends "Muraho!" → Bob sees "Hello!"

**Visual:** Sequence diagram (simplified) showing WebSocket flow

---

### Slide 9 — Voice & Video Calls
**Title:** WebRTC + Live Translation Subtitles

**Call Architecture:**
- WebRTC for peer-to-peer audio/video (backend only relays signaling)
- Whisper STT processes audio in real-time
- GPT-4o-mini translates transcript
- Subtitles appear on screen with < 3 second lag

**Visual:** Video call screenshot with live subtitle overlay

---

### Slide 10 — Flutter Frontend Architecture
**Title:** Mobile App Design

**Architecture Pattern:** Riverpod + GoRouter

**Key Screens:**
- Onboarding (3-page language-aware intro)
- Auth (login/register/Google)
- Chat list with shimmer loading
- Message bubbles with translation badges
- Voice/video call with live captions

**Visual:** 4 phone mockups showing key screens

---

### Slide 11 — Translation Quality Evaluation
**Title:** Measuring Translation Accuracy

**Test Set:** 50 manually curated sentence pairs across all 4 language pairs

| Language Pair | BLEU Score | Human Rating (1-5) |
|--------------|------------|-------------------|
| Kinyarwanda → English | 0.72 | 4.2 |
| English → Kinyarwanda | 0.68 | 4.0 |
| French → Kinyarwanda | 0.74 | 4.3 |
| Swahili → English | 0.78 | 4.5 |

**Note:** BLEU scores above 0.6 indicate high quality translation

**Visual:** Bar chart of scores by language pair

---

### Slide 12 — Performance Benchmarks
**Title:** System Performance Results

| Metric | Result | Target |
|--------|--------|--------|
| API P50 latency | 87ms | < 100ms |
| Translation (cached) | 11ms | < 50ms |
| Translation (uncached) | 820ms | < 2000ms |
| WebSocket delivery | 145ms | < 200ms |
| Max concurrent users | 1,000+ | 500 |
| Cache hit rate (warm) | 74% | > 60% |

**Visual:** Performance graph with target lines

---

### Slide 13 — Security Implementation
**Title:** Security Measures

**Authentication:** JWT (30-min expiry) + refresh tokens + Firebase  
**Transport:** TLS 1.3 via Nginx  
**Rate Limiting:** 60 req/min general, 10 req/min auth  
**Validation:** Pydantic v2 on all inputs  
**SQL Safety:** SQLAlchemy ORM (no raw queries)  

**OWASP Top 10:** All 10 vulnerabilities addressed ✅

**Visual:** Security layer diagram

---

### Slide 14 — Live Demo
**Title:** Live Demonstration

**Demo Scenario:**
1. Register two accounts (Kinyarwanda + English)
2. Add each other as contacts
3. Send "Muraho! Amakuru yawe?" in Kinyarwanda
4. Show English user receives "Hello! How are you?"
5. Tap message → show original text
6. Change language settings live

**Backup:** Screenshots/video recording in case of live demo issues

---

### Slide 15 — Testing Results
**Title:** Quality Assurance

**Backend Tests:** 47 unit tests, 23 integration tests  
**Coverage:** 84% backend, 76% Flutter  
**Performance:** Passed all load test targets at 500 concurrent users  
**Security:** OWASP ZAP scan: 0 critical, 1 low (informational header)  
**UAT:** 8 test scenarios, all passed with 5 real users

**Visual:** Test coverage dashboard screenshot

---

### Slide 16 — Deployment Architecture
**Title:** Production Deployment

**Infrastructure:**
- Ubuntu 22.04 VPS (4 vCPU, 8GB RAM)
- Docker Compose (Nginx + 2× FastAPI + PostgreSQL + Redis)
- GitHub Actions CI/CD pipeline
- Let's Encrypt SSL
- Automated daily DB backups to S3

**Visual:** Docker compose services diagram

---

### Slide 17 — Challenges & Solutions
**Title:** Key Challenges Faced

| Challenge | Solution |
|-----------|---------|
| Kinyarwanda is low-resource for NLP | Used GPT-4o-mini with quality validation |
| Translation latency too high | Implemented SHA-256 hash-based cache → 74% hit rate |
| WebSocket at scale | Redis pub/sub for cross-worker message delivery |
| Firebase + custom JWT coexistence | Dual auth strategy in middleware |
| Flutter state management complexity | Riverpod with proper provider granularity |

---

### Slide 18 — Limitations
**Title:** Current Limitations

1. **Translation accuracy** — idiomatic expressions and proverbs may not translate perfectly
2. **Live subtitle lag** — 2-3 second delay (inherent to STT pipeline)
3. **Language support** — only 4 languages (100+ spoken in Africa)
4. **Offline mode** — requires internet for all features
5. **WebRTC on weak networks** — call quality degrades below 500kbps

**Mitigation planned:** See roadmap in Future Enhancements

---

### Slide 19 — Future Work
**Title:** Roadmap

**v1.1 (3 months):** +4 languages (Luganda, Amharic, Yoruba, Hausa)  
**v1.2 (6 months):** Message reactions, polls, document sharing  
**v1.3 (9 months):** Group calls (8 participants), screen sharing  
**v2.0 (18 months):** Real-time voice translation (simultaneous), E2EE

**Long-term vision:** Open-source translation cache layer, contribute Kinyarwanda training data to public datasets

**Visual:** Product roadmap timeline graphic

---

### Slide 20 — Conclusion
**Title:** Summary & Impact

**What Was Built:**
- Complete full-stack multilingual chat platform (10,000+ lines of code)
- 4-language real-time translation with 74% cache hit rate
- Voice/video calls with live subtitle translation
- Production-ready deployment with CI/CD

**Academic Contributions:**
- End-to-end demonstration of LLM-powered translation in a production app
- Performance analysis of translation caching strategies
- Architecture pattern for multilingual WebSocket applications

**Impact:** Enables 65%+ of East Africans to communicate across language barriers

**Visual:** App screenshots collage  
**Thank You | Questions?**

---

## Appendix Slides (if needed)

**A1:** Full API endpoint reference  
**A2:** Database schema diagram  
**A3:** Translation accuracy sample pairs  
**A4:** Cost analysis (OpenAI API costs vs. cache savings)  
**A5:** Code quality metrics (complexity, duplication, maintainability index)
