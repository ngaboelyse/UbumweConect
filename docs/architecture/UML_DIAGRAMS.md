# Ubumwe Connect — UML Diagrams

All diagrams are written in [Mermaid](https://mermaid.js.org/) syntax. Render them at [mermaid.live](https://mermaid.live) or in any Markdown viewer with Mermaid support.

---

## 1. Use Case Diagram

```mermaid
graph TB
    subgraph Actors
        U[👤 User]
        A[🔑 Admin]
        AI[🤖 AI Services]
    end

    subgraph Authentication
        UC1[Register Account]
        UC2[Login / Logout]
        UC3[Google Sign-In]
        UC4[Reset Password]
    end

    subgraph Messaging
        UC5[Send Text Message]
        UC6[Send Voice Message]
        UC7[Send Image/File]
        UC8[Reply to Message]
        UC9[View Translated Message]
        UC10[See Original Message]
        UC11[Create Group Chat]
    end

    subgraph Translation
        UC12[Auto-Translate Message]
        UC13[Set Preferred Language]
        UC14[Detect Language]
    end

    subgraph Calls
        UC15[Make Voice Call]
        UC16[Make Video Call]
        UC17[View Live Subtitles]
        UC18[Accept/Decline Call]
    end

    subgraph Profile
        UC19[Edit Profile]
        UC20[Upload Avatar]
        UC21[Manage Contacts]
        UC22[Block/Unblock User]
    end

    subgraph Admin
        UC23[View Analytics Dashboard]
        UC24[Manage Users]
        UC25[Monitor Translation Stats]
    end

    U --> UC1 & UC2 & UC3 & UC4
    U --> UC5 & UC6 & UC7 & UC8 & UC9 & UC10 & UC11
    U --> UC13 & UC15 & UC16 & UC17 & UC18
    U --> UC19 & UC20 & UC21 & UC22
    A --> UC23 & UC24 & UC25

    UC5 -.->|includes| UC12
    UC6 -.->|includes| UC14
    UC12 -.->|uses| AI
    UC14 -.->|uses| AI
    UC17 -.->|uses| AI
```

---

## 2. Class Diagram

```mermaid
classDiagram
    class User {
        +UUID id
        +String email
        +String username
        +String displayName
        +String? avatarUrl
        +String? bio
        +LanguageCode preferredLanguage
        +UserRole role
        +Boolean isOnline
        +DateTime? lastSeen
        +login(email, password) Token
        +register(data) User
        +updateProfile(data) User
        +logout() void
    }

    class Conversation {
        +UUID id
        +ConversationType type
        +String? name
        +DateTime? lastMessageAt
        +List~Participant~ participants
        +addParticipant(userId) void
        +removeParticipant(userId) void
        +getUnreadCount(userId) int
    }

    class Message {
        +UUID id
        +UUID conversationId
        +UUID senderId
        +MessageType type
        +String content
        +LanguageCode originalLanguage
        +Map translatedContents
        +Boolean isDeleted
        +Message? replyTo
        +getContentForLanguage(lang) String
        +hasTranslation(lang) Boolean
    }

    class TranslationCache {
        +UUID id
        +String textHash
        +String sourceText
        +LanguageCode sourceLanguage
        +LanguageCode targetLanguage
        +String translatedText
        +int hitCount
        +DateTime lastUsedAt
    }

    class Call {
        +UUID id
        +UUID conversationId
        +CallType type
        +CallStatus status
        +DateTime? startedAt
        +int? durationSeconds
        +initiate() Call
        +accept() void
        +reject() void
        +end() void
    }

    class TranslationService {
        +translateText(text, from, to) String
        +detectLanguage(text) LanguageCode
        +translateForAllLanguages(text, sourceLang) Map
        +batchTranslate(texts, from, to) List~String~
    }

    class VoiceService {
        +transcribeAudio(file) String
        +synthesizeSpeech(text, lang) bytes
        +processVoiceMessage(audioFile, lang) VoiceResult
    }

    class WebSocketManager {
        +Dict activeConnections
        +connect(userId, ws) void
        +disconnect(userId) void
        +sendToUser(userId, message) void
        +broadcastToConversation(convId, message) void
        +sendTypingIndicator(convId, userId) void
    }

    User "1" --> "N" Conversation : participates in
    User "1" --> "N" Message : sends
    Conversation "1" --> "N" Message : contains
    Message "1" --> "0..1" Message : replies to
    Message "N" --> "1" TranslationCache : references
    Conversation "1" --> "N" Call : has
    TranslationService ..> TranslationCache : uses
    WebSocketManager ..> Message : broadcasts
```

---

## 3. Sequence Diagram — Send & Translate Message

```mermaid
sequenceDiagram
    actor Alice as Alice (Kinyarwanda)
    participant App as Flutter App
    participant API as FastAPI Backend
    participant DB as PostgreSQL
    participant Cache as Redis/TransCache
    participant OpenAI
    participant WS as WebSocket
    actor Bob as Bob (English)

    Alice->>App: Type "Muraho!" and send
    App->>API: POST /api/v1/conversations/{id}/messages
    note over App,API: {content: "Muraho!", type: "text"}

    API->>DB: Save message (content, sender_id, conv_id)
    DB-->>API: message_id returned

    API->>Cache: Check cache(hash("Muraho!"), rw→en)
    Cache-->>API: MISS

    API->>OpenAI: translate("Muraho!", kinyarwanda→english)
    OpenAI-->>API: "Hello!"

    API->>Cache: Store translation in cache
    API->>DB: Update message.translated_contents["english"] = "Hello!"

    API->>WS: broadcast_to_conversation(conv_id, new_message)
    WS->>App: new_message event {content: "Muraho!", translations: {en: "Hello!"}}
    WS->>Bob: new_message event {content: "Hello!"}

    note over Bob: Bob sees "Hello!" (his preferred language)
    note over Alice: Alice sees "Muraho!" (her own message)
```

---

## 4. Sequence Diagram — WebRTC Video Call Setup

```mermaid
sequenceDiagram
    actor Caller
    participant CallerApp as Caller Flutter
    participant Backend
    participant CalleeApp as Callee Flutter
    actor Callee

    Caller->>CallerApp: Tap "Video Call" button
    CallerApp->>Backend: POST /api/v1/calls/initiate
    note over CallerApp,Backend: {conversation_id, type: "video"}
    Backend-->>CallerApp: {call_id, status: "initiated"}

    Backend->>CalleeApp: WS event: incoming_call
    note over Backend,CalleeApp: {call_id, caller_info, type: "video"}
    CalleeApp->>Callee: Show incoming call screen

    Callee->>CalleeApp: Tap "Accept"
    CalleeApp->>Backend: POST /api/v1/calls/{id}/accept
    Backend->>CallerApp: WS event: call_accepted

    CallerApp->>CallerApp: Create RTCPeerConnection + offer
    CallerApp->>Backend: WS: webrtc_signal {type: "offer", sdp: "..."}
    Backend->>CalleeApp: WS: webrtc_signal {type: "offer", sdp: "..."}

    CalleeApp->>CalleeApp: Create RTCPeerConnection + answer
    CalleeApp->>Backend: WS: webrtc_signal {type: "answer", sdp: "..."}
    Backend->>CallerApp: WS: webrtc_signal {type: "answer", sdp: "..."}

    loop ICE Candidate Exchange
        CallerApp->>Backend: WS: ice_candidate {...}
        Backend->>CalleeApp: WS: ice_candidate {...}
        CalleeApp->>Backend: WS: ice_candidate {...}
        Backend->>CallerApp: WS: ice_candidate {...}
    end

    note over CallerApp,CalleeApp: Direct P2P WebRTC connection established
    CallerApp<-->CalleeApp: Audio/Video stream (P2P)

    note over CallerApp: Whisper STT → GPT-4o-mini → live subtitles
```

---

## 5. State Machine — Message Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Composing : User types

    Composing --> Sending : User taps Send
    Composing --> [*] : User clears

    Sending --> Sent : API returns 200
    Sending --> Failed : Network error / API error

    Failed --> Sending : Retry
    Failed --> [*] : Discard

    Sent --> Translating : Backend triggers translation
    Translating --> Translated : All languages populated

    Translated --> Delivered : Recipient's WebSocket receives
    Translated --> Delivered : Push notification sent (if offline)

    Delivered --> Read : Recipient opens conversation
    Read --> [*] : Terminal state

    Sent --> Deleted : User deletes
    Delivered --> Deleted : User deletes
    Read --> Deleted : User deletes
    Deleted --> [*]
```

---

## 6. Entity-Relationship Diagram

```mermaid
erDiagram
    USERS {
        uuid id PK
        varchar email UK
        varchar username UK
        varchar display_name
        text avatar_url
        varchar preferred_language
        varchar role
        boolean is_online
        timestamptz last_seen
        timestamptz created_at
    }

    USER_CONTACTS {
        uuid id PK
        uuid user_id FK
        uuid contact_id FK
        boolean is_blocked
    }

    CONVERSATIONS {
        uuid id PK
        varchar type
        varchar name
        uuid created_by FK
        timestamptz last_message_at
    }

    CONVERSATION_PARTICIPANTS {
        uuid id PK
        uuid conversation_id FK
        uuid user_id FK
        boolean is_admin
        timestamptz last_read_at
        timestamptz joined_at
    }

    MESSAGES {
        uuid id PK
        uuid conversation_id FK
        uuid sender_id FK
        varchar type
        text content
        varchar original_language
        jsonb translated_contents
        text media_url
        uuid reply_to_id FK
        boolean is_deleted
        timestamptz created_at
    }

    MESSAGE_STATUSES {
        uuid id PK
        uuid message_id FK
        uuid user_id FK
        varchar status
    }

    TRANSLATION_CACHE {
        uuid id PK
        varchar text_hash
        text source_text
        varchar source_language
        varchar target_language
        text translated_text
        integer hit_count
        timestamptz last_used_at
    }

    CALLS {
        uuid id PK
        uuid conversation_id FK
        uuid initiated_by FK
        varchar type
        varchar status
        timestamptz started_at
        integer duration_seconds
    }

    USERS ||--o{ USER_CONTACTS : "has contacts"
    USERS ||--o{ CONVERSATION_PARTICIPANTS : "joins"
    CONVERSATIONS ||--o{ CONVERSATION_PARTICIPANTS : "has"
    CONVERSATIONS ||--o{ MESSAGES : "contains"
    USERS ||--o{ MESSAGES : "sends"
    MESSAGES ||--o{ MESSAGE_STATUSES : "has status"
    MESSAGES ||--o{ MESSAGES : "reply_to"
    CONVERSATIONS ||--o{ CALLS : "has calls"
```

---

## 7. Deployment Diagram

```mermaid
graph TB
    subgraph Internet
        User[📱 Mobile Users]
        CDN[☁️ AWS CloudFront]
    end

    subgraph VPS["Production VPS (Ubuntu 22.04)"]
        Nginx[Nginx\nReverse Proxy\n:80/:443]

        subgraph Docker["Docker Network"]
            Backend1[FastAPI\nWorker 1\n:8000]
            Backend2[FastAPI\nWorker 2\n:8001]
            Redis[(Redis\n:6379)]
            PG[(PostgreSQL\n:5432)]
        end
    end

    subgraph AWS
        S3[(S3 Bucket\nMedia Files)]
    end

    subgraph Firebase
        Auth[Firebase Auth]
        FCM[FCM\nPush Notifications]
    end

    subgraph OpenAI
        GPT[GPT-4o-mini\nTranslation]
        Whisper[Whisper\nSTT]
        TTS[TTS API]
    end

    User -->|HTTPS| CDN
    User -->|HTTPS/WSS| Nginx
    CDN --> S3
    Nginx --> Backend1
    Nginx --> Backend2
    Backend1 & Backend2 --> Redis
    Backend1 & Backend2 --> PG
    Backend1 & Backend2 --> S3
    Backend1 & Backend2 --> GPT & Whisper & TTS
    Backend1 & Backend2 --> Auth
    Backend1 & Backend2 --> FCM
```
