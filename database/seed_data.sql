-- ============================================================
-- Ubumwe Connect - Sample Seed Data
-- ============================================================

-- Disable triggers during seed
SET session_replication_role = 'replica';

-- ============================================================
-- USERS
-- ============================================================

INSERT INTO users (id, email, username, display_name, hashed_password, preferred_language, role, is_active, is_verified, is_online, bio, created_at) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'amara@ubumweconnect.rw',
    'amara_gasana',
    'Amara Gasana',
    '$2b$12$X7qXrdEXGzjjOwL/hx9Cl.SQShO5WdytyN9U4daWjHpghtMbFykbG',  -- password: Test@1234
    'kinyarwanda',
    'user',
    TRUE, TRUE, TRUE,
    'Ndakunda gukoresha ururimi rw''Ikinyarwanda. Ndishimiye gutunga inshuti z''amahanga!',
    NOW() - INTERVAL '30 days'
),
(
    '22222222-2222-2222-2222-222222222222',
    'james@ubumweconnect.rw',
    'james_smith',
    'James Smith',
    '$2b$12$X7qXrdEXGzjjOwL/hx9Cl.SQShO5WdytyN9U4daWjHpghtMbFykbG',
    'english',
    'user',
    TRUE, TRUE, FALSE,
    'Software engineer who loves connecting with people across cultures. Learning Kinyarwanda!',
    NOW() - INTERVAL '25 days'
),
(
    '33333333-3333-3333-3333-333333333333',
    'marie@ubumweconnect.rw',
    'marie_dubois',
    'Marie Dubois',
    '$2b$12$X7qXrdEXGzjjOwL/hx9Cl.SQShO5WdytyN9U4daWjHpghtMbFykbG',
    'french',
    'user',
    TRUE, TRUE, TRUE,
    'Bonjour! Je suis Marie, étudiante en langues africaines à Paris.',
    NOW() - INTERVAL '20 days'
),
(
    '44444444-4444-4444-4444-444444444444',
    'aisha@ubumweconnect.rw',
    'aisha_omar',
    'Aisha Omar',
    '$2b$12$X7qXrdEXGzjjOwL/hx9Cl.SQShO5WdytyN9U4daWjHpghtMbFykbG',
    'swahili',
    'user',
    TRUE, TRUE, FALSE,
    'Habari! Ninapenda kujifunza lugha mbalimbali na kukutana na watu wapya.',
    NOW() - INTERVAL '15 days'
),
(
    '55555555-5555-5555-5555-555555555555',
    'admin@ubumweconnect.rw',
    'admin',
    'Ubumwe Admin',
    '$2b$12$X7qXrdEXGzjjOwL/hx9Cl.SQShO5WdytyN9U4daWjHpghtMbFykbG',
    'english',
    'admin',
    TRUE, TRUE, FALSE,
    'Platform administrator for Ubumwe Connect.',
    NOW() - INTERVAL '60 days'
);

-- ============================================================
-- USER CONTACTS
-- ============================================================

INSERT INTO user_contacts (user_id, contact_id) VALUES
('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111'),
('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444'),
('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111'),
('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333'),
('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222'),
('22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444'),
('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222');

-- ============================================================
-- CONVERSATIONS
-- ============================================================

INSERT INTO conversations (id, type, name, created_by, last_message_at, created_at) VALUES
(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'direct',
    NULL,
    '11111111-1111-1111-1111-111111111111',
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '20 days'
),
(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'direct',
    NULL,
    '11111111-1111-1111-1111-111111111111',
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '15 days'
),
(
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'group',
    'Language Exchange Group',
    '11111111-1111-1111-1111-111111111111',
    NOW() - INTERVAL '3 hours',
    NOW() - INTERVAL '10 days'
);

-- ============================================================
-- CONVERSATION PARTICIPANTS
-- ============================================================

INSERT INTO conversation_participants (conversation_id, user_id, is_admin, joined_at) VALUES
-- Direct: Amara <-> James
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', FALSE, NOW() - INTERVAL '20 days'),
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', FALSE, NOW() - INTERVAL '20 days'),
-- Direct: Amara <-> Marie
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', FALSE, NOW() - INTERVAL '15 days'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', FALSE, NOW() - INTERVAL '15 days'),
-- Group: Language Exchange
('cccccccc-cccc-cccc-cccc-cccccccccccc', '11111111-1111-1111-1111-111111111111', TRUE, NOW() - INTERVAL '10 days'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222', FALSE, NOW() - INTERVAL '10 days'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333', FALSE, NOW() - INTERVAL '10 days'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', '44444444-4444-4444-4444-444444444444', FALSE, NOW() - INTERVAL '9 days');

-- ============================================================
-- MESSAGES
-- ============================================================

-- Direct conversation: Amara (kinyarwanda) <-> James (english)
INSERT INTO messages (id, conversation_id, sender_id, type, content, original_language, translated_contents, created_at) VALUES
(
    'msg00001-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'text',
    'Muraho James! Amakuru yawe?',
    'kinyarwanda',
    '{"kinyarwanda": "Muraho James! Amakuru yawe?", "english": "Hello James! How are you?", "french": "Bonjour James! Comment allez-vous?", "swahili": "Habari James! Habari gani?"}',
    NOW() - INTERVAL '2 hours 30 minutes'
),
(
    'msg00001-0000-0000-0000-000000000002',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '22222222-2222-2222-2222-222222222222',
    'text',
    'Hi Amara! I''m doing great, thanks for asking! How about you?',
    'english',
    '{"english": "Hi Amara! I''m doing great, thanks for asking! How about you?", "kinyarwanda": "Muraho Amara! Ndi mwiza, urakoze kubaza! Nawe?", "french": "Salut Amara! Je vais très bien, merci de demander! Et toi?", "swahili": "Habari Amara! Niko sawa, asante kwa kuuliza! Wewe je?"}',
    NOW() - INTERVAL '2 hours 15 minutes'
),
(
    'msg00001-0000-0000-0000-000000000003',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'text',
    'Nanjye ndi mwiza cyane! Ndishimiye gutunga inshuti nka wewe.',
    'kinyarwanda',
    '{"kinyarwanda": "Nanjye ndi mwiza cyane! Ndishimiye gutunga inshuti nka wewe.", "english": "I am also doing very well! I am happy to have a friend like you.", "french": "Je vais aussi très bien! Je suis heureux d''avoir un ami comme toi.", "swahili": "Mimi pia niko vizuri sana! Ninafurahi kuwa na rafiki kama wewe."}',
    NOW() - INTERVAL '2 hours'
),
(
    'msg00001-0000-0000-0000-000000000004',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '22222222-2222-2222-2222-222222222222',
    'text',
    'That means a lot to me! I love how this app translates our messages automatically. It''s amazing!',
    'english',
    '{"english": "That means a lot to me! I love how this app translates our messages automatically. It''s amazing!", "kinyarwanda": "Ibyo bimfasha cyane! Ndakunda uburyo application iduhuza amagambo yacu by''ikirenga. Ni itangaza!", "french": "Cela me touche beaucoup! J''adore comment cette application traduit nos messages automatiquement. C''est incroyable!", "swahili": "Hiyo inanigusa sana! Napenda jinsi programu hii inavyotafsiri ujumbe wetu kiotomatiki. Ni ya ajabu!"}',
    NOW() - INTERVAL '1 hour 45 minutes'
);

-- Group conversation: Multi-language exchange
INSERT INTO messages (id, conversation_id, sender_id, type, content, original_language, translated_contents, created_at) VALUES
(
    'msg00002-0000-0000-0000-000000000001',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '11111111-1111-1111-1111-111111111111',
    'system',
    'Amara Gasana created the group "Language Exchange Group"',
    'english',
    '{"english": "Amara Gasana created the group \"Language Exchange Group\"", "kinyarwanda": "Amara Gasana yaremye itsinda \"Language Exchange Group\"", "french": "Amara Gasana a créé le groupe \"Language Exchange Group\"", "swahili": "Amara Gasana aliunda kikundi \"Language Exchange Group\""}',
    NOW() - INTERVAL '10 days'
),
(
    'msg00002-0000-0000-0000-000000000002',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '11111111-1111-1111-1111-111111111111',
    'text',
    'Murakaza neza muri iri tsinda! Tuziga ururimi hamwe.',
    'kinyarwanda',
    '{"kinyarwanda": "Murakaza neza muri iri tsinda! Tuziga ururimi hamwe.", "english": "Welcome to this group! We will learn languages together.", "french": "Bienvenue dans ce groupe! Nous allons apprendre les langues ensemble.", "swahili": "Karibu katika kikundi hiki! Tutajifunza lugha pamoja."}',
    NOW() - INTERVAL '10 days'
),
(
    'msg00002-0000-0000-0000-000000000003',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '22222222-2222-2222-2222-222222222222',
    'text',
    'This is so cool! Excited to learn from everyone here.',
    'english',
    '{"english": "This is so cool! Excited to learn from everyone here.", "kinyarwanda": "Ibi ni byiza cyane! Nishimiye kwiga kumuntu wese hano.", "french": "C''est tellement cool! Excité d''apprendre de tout le monde ici.", "swahili": "Hii ni ya ajabu sana! Nasisimka kujifunza kutoka kwa kila mtu hapa."}',
    NOW() - INTERVAL '9 days 22 hours'
),
(
    'msg00002-0000-0000-0000-000000000004',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '33333333-3333-3333-3333-333333333333',
    'text',
    'Bonjour tout le monde! Je suis tellement heureuse de rejoindre ce groupe.',
    'french',
    '{"french": "Bonjour tout le monde! Je suis tellement heureuse de rejoindre ce groupe.", "english": "Hello everyone! I am so happy to join this group.", "kinyarwanda": "Muraho mwese! Nishimiye cyane kwinjira muri iri tsinda.", "swahili": "Habari wote! Nimefurahi sana kujiunga na kikundi hiki."}',
    NOW() - INTERVAL '9 days 20 hours'
),
(
    'msg00002-0000-0000-0000-000000000005',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '44444444-4444-4444-4444-444444444444',
    'text',
    'Habari za asubuhi! Nimefurahi kuwepo hapa. Tutasaidiana.',
    'swahili',
    '{"swahili": "Habari za asubuhi! Nimefurahi kuwepo hapa. Tutasaidiana.", "english": "Good morning! I am glad to be here. We will help each other.", "kinyarwanda": "Amakuru y''igitondo! Nishimiye kuba hano. Tuzufashanya.", "french": "Bonjour! Je suis heureux d''être ici. Nous allons nous entraider."}',
    NOW() - INTERVAL '3 hours'
);

-- ============================================================
-- TRANSLATION CACHE (sample entries)
-- ============================================================

INSERT INTO translation_cache (text_hash, source_text, source_language, target_language, translated_text, hit_count) VALUES
(
    md5('Muraho! Amakuru yawe?'),
    'Muraho! Amakuru yawe?',
    'kinyarwanda',
    'english',
    'Hello! How are you?',
    47
),
(
    md5('Muraho! Amakuru yawe?') || '_fr',
    'Muraho! Amakuru yawe?',
    'kinyarwanda',
    'french',
    'Bonjour! Comment allez-vous?',
    23
),
(
    md5('Hello! How are you?'),
    'Hello! How are you?',
    'english',
    'kinyarwanda',
    'Muraho! Amakuru yawe?',
    31
),
(
    md5('Bonjour! Comment ça va?'),
    'Bonjour! Comment ça va?',
    'french',
    'english',
    'Hello! How are you?',
    19
),
(
    md5('Habari! Habari gani?'),
    'Habari! Habari gani?',
    'swahili',
    'english',
    'Hello! How are you?',
    12
);

-- Re-enable triggers
SET session_replication_role = 'origin';

-- ============================================================
-- STATS CHECK
-- ============================================================

SELECT 'Users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'Conversations', COUNT(*) FROM conversations
UNION ALL SELECT 'Messages', COUNT(*) FROM messages
UNION ALL SELECT 'Translation Cache', COUNT(*) FROM translation_cache;
