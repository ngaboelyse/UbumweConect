-- ============================================================
-- Ubumwe Connect - PostgreSQL Database Schema
-- Version: 1.0.0
-- Description: Complete schema for multilingual chat platform
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- For fast text search
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- For accent-insensitive search

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE language_code AS ENUM (
    'kinyarwanda',
    'english',
    'french',
    'swahili'
);

CREATE TYPE conversation_type AS ENUM (
    'direct',
    'group'
);

CREATE TYPE message_type AS ENUM (
    'text',
    'image',
    'audio',
    'video',
    'file',
    'system'
);

CREATE TYPE message_status AS ENUM (
    'sent',
    'delivered',
    'read'
);

CREATE TYPE call_type AS ENUM (
    'voice',
    'video'
);

CREATE TYPE call_status AS ENUM (
    'initiated',
    'ringing',
    'connected',
    'ended',
    'missed',
    'rejected',
    'failed'
);

CREATE TYPE call_participant_status AS ENUM (
    'invited',
    'joined',
    'left',
    'declined',
    'missed'
);

CREATE TYPE user_role AS ENUM (
    'user',
    'moderator',
    'admin'
);

-- ============================================================
-- USERS TABLE
-- ============================================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firebase_uid        VARCHAR(128) UNIQUE,
    email               VARCHAR(255) NOT NULL UNIQUE,
    username            VARCHAR(50) NOT NULL UNIQUE,
    display_name        VARCHAR(100) NOT NULL,
    hashed_password     VARCHAR(255),
    avatar_url          TEXT,
    bio                 VARCHAR(500),
    preferred_language  language_code NOT NULL DEFAULT 'english',
    role                user_role NOT NULL DEFAULT 'user',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified         BOOLEAN NOT NULL DEFAULT FALSE,
    is_online           BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen           TIMESTAMPTZ,
    push_token          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for users
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid) WHERE firebase_uid IS NOT NULL;
CREATE INDEX idx_users_preferred_language ON users(preferred_language);
CREATE INDEX idx_users_is_online ON users(is_online) WHERE is_online = TRUE;
-- Full-text search index
CREATE INDEX idx_users_search ON users USING gin(
    (to_tsvector('simple', coalesce(display_name, '') || ' ' || coalesce(username, '') || ' ' || coalesce(email, '')))
);

-- ============================================================
-- USER SESSIONS TABLE
-- ============================================================

CREATE TABLE user_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token   TEXT NOT NULL UNIQUE,
    device_info     JSONB DEFAULT '{}',
    ip_address      INET,
    is_valid        BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_refresh_token ON user_sessions(refresh_token);
CREATE INDEX idx_user_sessions_expires_at ON user_sessions(expires_at);

-- ============================================================
-- USER CONTACTS TABLE
-- ============================================================

CREATE TABLE user_contacts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_blocked      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, contact_id),
    CHECK (user_id != contact_id)
);

CREATE INDEX idx_user_contacts_user_id ON user_contacts(user_id);
CREATE INDEX idx_user_contacts_contact_id ON user_contacts(contact_id);

-- ============================================================
-- CONVERSATIONS TABLE
-- ============================================================

CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type            conversation_type NOT NULL DEFAULT 'direct',
    name            VARCHAR(100),
    description     VARCHAR(500),
    avatar_url      TEXT,
    created_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_message_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_created_by ON conversations(created_by);
CREATE INDEX idx_conversations_type ON conversations(type);
CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at DESC);

-- ============================================================
-- CONVERSATION PARTICIPANTS TABLE
-- ============================================================

CREATE TABLE conversation_participants (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_admin        BOOLEAN NOT NULL DEFAULT FALSE,
    is_muted        BOOLEAN NOT NULL DEFAULT FALSE,
    last_read_at    TIMESTAMPTZ,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at         TIMESTAMPTZ,
    UNIQUE(conversation_id, user_id)
);

CREATE INDEX idx_conv_participants_conv_id ON conversation_participants(conversation_id);
CREATE INDEX idx_conv_participants_user_id ON conversation_participants(user_id);
CREATE INDEX idx_conv_participants_active ON conversation_participants(user_id) WHERE left_at IS NULL;

-- ============================================================
-- MESSAGES TABLE
-- ============================================================

CREATE TABLE messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id           UUID REFERENCES users(id) ON DELETE SET NULL,
    type                message_type NOT NULL DEFAULT 'text',
    content             TEXT,
    original_language   language_code,
    -- JSONB dict: {"english": "...", "french": "...", "kinyarwanda": "...", "swahili": "..."}
    translated_contents JSONB DEFAULT '{}',
    media_url           TEXT,
    media_type          VARCHAR(100),
    media_size          BIGINT,
    duration_seconds    INTEGER,              -- For audio/video messages
    reply_to_id         UUID REFERENCES messages(id) ON DELETE SET NULL,
    is_edited           BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ,
    metadata            JSONB DEFAULT '{}',  -- Extra data (voice transcript, etc.)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation_id ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_reply_to_id ON messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_messages_not_deleted ON messages(conversation_id) WHERE is_deleted = FALSE;
-- GIN index for searching translated_contents JSONB
CREATE INDEX idx_messages_translated_contents ON messages USING gin(translated_contents);

-- ============================================================
-- MESSAGE STATUS TABLE
-- ============================================================

CREATE TABLE message_statuses (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id  UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      message_status NOT NULL DEFAULT 'delivered',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

CREATE INDEX idx_message_statuses_message_id ON message_statuses(message_id);
CREATE INDEX idx_message_statuses_user_id ON message_statuses(user_id);

-- ============================================================
-- MESSAGE REACTIONS TABLE
-- ============================================================

CREATE TABLE message_reactions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id  UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji       VARCHAR(16) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_message_reactions_message_id ON message_reactions(message_id);
CREATE INDEX idx_message_reactions_user_id ON message_reactions(user_id);

-- ============================================================
-- CALLS TABLE
-- ============================================================

CREATE TABLE calls (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    initiated_by    UUID REFERENCES users(id) ON DELETE SET NULL,
    type            call_type NOT NULL DEFAULT 'voice',
    status          call_status NOT NULL DEFAULT 'initiated',
    started_at      TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    duration_seconds INTEGER,
    recording_url   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_calls_conversation_id ON calls(conversation_id);
CREATE INDEX idx_calls_initiated_by ON calls(initiated_by);
CREATE INDEX idx_calls_status ON calls(status);
CREATE INDEX idx_calls_created_at ON calls(created_at DESC);

-- ============================================================
-- CALL PARTICIPANTS TABLE
-- ============================================================

CREATE TABLE call_participants (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    call_id     UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      call_participant_status NOT NULL DEFAULT 'invited',
    joined_at   TIMESTAMPTZ,
    left_at     TIMESTAMPTZ,
    UNIQUE(call_id, user_id)
);

CREATE INDEX idx_call_participants_call_id ON call_participants(call_id);
CREATE INDEX idx_call_participants_user_id ON call_participants(user_id);

-- ============================================================
-- TRANSLATION CACHE TABLE
-- ============================================================

CREATE TABLE translation_cache (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    text_hash       VARCHAR(64) NOT NULL,  -- SHA-256 of source_text
    source_text     TEXT NOT NULL,
    source_language language_code NOT NULL,
    target_language language_code NOT NULL,
    translated_text TEXT NOT NULL,
    model_used      VARCHAR(50) DEFAULT 'gpt-4o-mini',
    hit_count       INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(text_hash, source_language, target_language)
);

CREATE INDEX idx_translation_cache_hash ON translation_cache(text_hash);
CREATE INDEX idx_translation_cache_languages ON translation_cache(source_language, target_language);
CREATE INDEX idx_translation_cache_last_used ON translation_cache(last_used_at DESC);

-- ============================================================
-- TRANSLATIONS TABLE (per-message translation log)
-- ============================================================

CREATE TABLE translations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id      UUID REFERENCES messages(id) ON DELETE CASCADE,
    source_language language_code NOT NULL,
    target_language language_code NOT NULL,
    source_text     TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    cache_hit       BOOLEAN NOT NULL DEFAULT FALSE,
    tokens_used     INTEGER,
    latency_ms      INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_translations_message_id ON translations(message_id);
CREATE INDEX idx_translations_languages ON translations(source_language, target_language);

-- ============================================================
-- NOTIFICATIONS TABLE
-- ============================================================

CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        VARCHAR(50) NOT NULL,  -- 'message', 'call', 'contact_request', etc.
    title       VARCHAR(255) NOT NULL,
    body        TEXT,
    data        JSONB DEFAULT '{}',
    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at     TIMESTAMPTZ,
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id) WHERE is_read = FALSE;

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_messages_updated_at
    BEFORE UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-update conversation.last_message_at when a message is inserted
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET last_message_at = NEW.created_at, updated_at = NOW()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_message_updates_conversation
    AFTER INSERT ON messages
    FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();

-- Auto-update translation_cache hit_count and last_used_at
CREATE OR REPLACE FUNCTION update_translation_cache_hit()
RETURNS TRIGGER AS $$
BEGIN
    NEW.hit_count = OLD.hit_count + 1;
    NEW.last_used_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_translation_cache_hit
    BEFORE UPDATE ON translation_cache
    FOR EACH ROW EXECUTE FUNCTION update_translation_cache_hit();

-- Function to get unread message count per conversation for a user
CREATE OR REPLACE FUNCTION get_unread_count(p_user_id UUID, p_conversation_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_last_read TIMESTAMPTZ;
    v_count INTEGER;
BEGIN
    SELECT last_read_at INTO v_last_read
    FROM conversation_participants
    WHERE user_id = p_user_id AND conversation_id = p_conversation_id;

    IF v_last_read IS NULL THEN
        SELECT COUNT(*) INTO v_count
        FROM messages
        WHERE conversation_id = p_conversation_id
          AND sender_id != p_user_id
          AND is_deleted = FALSE;
    ELSE
        SELECT COUNT(*) INTO v_count
        FROM messages
        WHERE conversation_id = p_conversation_id
          AND sender_id != p_user_id
          AND created_at > v_last_read
          AND is_deleted = FALSE;
    END IF;

    RETURN COALESCE(v_count, 0);
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- VIEWS
-- ============================================================

-- Conversations with participant info and unread counts
CREATE VIEW v_conversation_summary AS
SELECT
    c.id,
    c.type,
    c.name,
    c.avatar_url,
    c.last_message_at,
    c.created_at,
    cp.user_id,
    cp.is_muted,
    cp.last_read_at,
    get_unread_count(cp.user_id, c.id) AS unread_count,
    m.content AS last_message_content,
    m.type AS last_message_type,
    m.sender_id AS last_message_sender_id,
    m.original_language AS last_message_language,
    m.translated_contents AS last_message_translations
FROM conversations c
JOIN conversation_participants cp ON c.id = cp.conversation_id AND cp.left_at IS NULL
LEFT JOIN LATERAL (
    SELECT * FROM messages
    WHERE conversation_id = c.id AND is_deleted = FALSE
    ORDER BY created_at DESC
    LIMIT 1
) m ON TRUE;

-- Translation cache statistics
CREATE VIEW v_translation_stats AS
SELECT
    source_language,
    target_language,
    COUNT(*) AS total_translations,
    SUM(hit_count) AS total_hits,
    AVG(hit_count) AS avg_hits_per_entry,
    MAX(last_used_at) AS last_activity
FROM translation_cache
GROUP BY source_language, target_language;

-- User activity summary
CREATE VIEW v_user_stats AS
SELECT
    u.id,
    u.display_name,
    u.username,
    u.preferred_language,
    u.is_online,
    u.last_seen,
    COUNT(DISTINCT cp.conversation_id) AS conversation_count,
    COUNT(DISTINCT m.id) AS message_count,
    COUNT(DISTINCT uc.contact_id) AS contact_count
FROM users u
LEFT JOIN conversation_participants cp ON u.id = cp.user_id AND cp.left_at IS NULL
LEFT JOIN messages m ON u.id = m.sender_id AND m.is_deleted = FALSE
LEFT JOIN user_contacts uc ON u.id = uc.user_id AND uc.is_blocked = FALSE
GROUP BY u.id, u.display_name, u.username, u.preferred_language, u.is_online, u.last_seen;

-- ============================================================
-- INITIAL GRANTS (adjust for your DB user)
-- ============================================================

-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ubumwe_app;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ubumwe_app;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ubumwe_app;
