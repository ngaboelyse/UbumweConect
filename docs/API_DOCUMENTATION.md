# Ubumwe Connect — API Documentation

**Version:** 1.0.0  
**Base URL:** `https://api.ubumweconnect.rw/api/v1`  
**WebSocket URL:** `wss://api.ubumweconnect.rw/ws`  
**Last Updated:** June 2026

---

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Rate Limiting](#rate-limiting)
- [Error Handling](#error-handling)
- [Endpoints — Authentication](#endpoints--authentication)
- [Endpoints — Users](#endpoints--users)
- [Endpoints — Conversations](#endpoints--conversations)
- [Endpoints — Messages](#endpoints--messages)
- [Endpoints — Calls](#endpoints--calls)
- [Endpoints — Translation](#endpoints--translation)
- [Endpoints — AI Assistant](#endpoints--ai-assistant)
- [Endpoints — Admin](#endpoints--admin)
- [WebSocket Events](#websocket-events)
- [Code Examples](#code-examples)

---

## Overview

The Ubumwe Connect API is a RESTful HTTP API that powers the Ubumwe Connect mobile application. It follows standard REST conventions, uses JSON for request and response bodies, and requires authentication via JWT Bearer tokens for all protected endpoints.

### Response Envelope

All API responses are wrapped in a consistent envelope:

```json
{
  "success": true,
  "data": { ... },
  "message": "Operation completed successfully",
  "meta": {
    "timestamp": "2026-06-15T10:30:00Z",
    "request_id": "req_abc123xyz"
  }
}
```

Error responses:

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request body contains invalid data",
    "details": [
      {
        "field": "email",
        "message": "Invalid email format"
      }
    ]
  },
  "meta": {
    "timestamp": "2026-06-15T10:30:00Z",
    "request_id": "req_abc123xyz"
  }
}
```

### Pagination

List endpoints return paginated results:

```json
{
  "success": true,
  "data": {
    "items": [ ... ],
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total_items": 156,
      "total_pages": 8,
      "has_next": true,
      "has_prev": false
    }
  }
}
```

Query parameters: `?page=1&per_page=20`

---

## Authentication

The API uses two-factor authentication: Firebase Authentication (for social login / email verification) and JWT tokens (for API access).

### Authentication Flow

1. Client authenticates with Firebase (email/password or Google OAuth)
2. Client obtains Firebase ID token
3. Client sends Firebase ID token to `/auth/firebase-login`
4. Server validates Firebase token and issues API JWT access token + refresh token
5. Client includes JWT access token in `Authorization: Bearer <token>` header for all subsequent requests

### Token Details

| Token Type | TTL | Storage Recommendation |
|------------|-----|----------------------|
| Access Token | 24 hours | Memory (not persisted) |
| Refresh Token | 30 days | Secure storage (Keychain/Keystore) |

### Authorization Header

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## Rate Limiting

| Endpoint Group | Limit | Window |
|---------------|-------|--------|
| Authentication endpoints | 10 requests | per 15 minutes per IP |
| General API | 1,000 requests | per hour per user |
| Translation endpoint | 200 requests | per hour per user |
| File upload | 50 uploads | per hour per user |
| WebSocket connections | 5 connections | per user |

Rate limit headers returned on all responses:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1718445600
```

When rate limit is exceeded, HTTP 429 is returned:

```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please retry after 847 seconds.",
    "retry_after": 847
  }
}
```

---

## Error Handling

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (successful DELETE) |
| 400 | Bad Request — invalid input |
| 401 | Unauthorized — missing or invalid token |
| 403 | Forbidden — insufficient permissions |
| 404 | Not Found |
| 409 | Conflict — resource already exists |
| 422 | Unprocessable Entity — validation error |
| 429 | Too Many Requests |
| 500 | Internal Server Error |
| 503 | Service Unavailable |

### Application Error Codes

| Code | Description |
|------|-------------|
| `AUTH_INVALID_CREDENTIALS` | Email or password incorrect |
| `AUTH_EMAIL_NOT_VERIFIED` | Account email not verified |
| `AUTH_TOKEN_EXPIRED` | JWT access token has expired |
| `AUTH_TOKEN_INVALID` | JWT token is malformed or tampered |
| `AUTH_ACCOUNT_SUSPENDED` | User account has been suspended |
| `USER_NOT_FOUND` | User with given ID does not exist |
| `USER_ALREADY_EXISTS` | Email already registered |
| `CONVERSATION_NOT_FOUND` | Conversation does not exist |
| `CONVERSATION_ACCESS_DENIED` | User is not a member of this conversation |
| `MESSAGE_NOT_FOUND` | Message does not exist |
| `TRANSLATION_FAILED` | Translation service unavailable |
| `MEDIA_UPLOAD_FAILED` | File upload to storage failed |
| `MEDIA_TYPE_NOT_ALLOWED` | File type not permitted |
| `CALL_USER_BUSY` | Called user is already in a call |
| `CALL_USER_OFFLINE` | Called user is offline |
| `VALIDATION_ERROR` | Request body validation failed |
| `RATE_LIMIT_EXCEEDED` | Rate limit hit |
| `INTERNAL_ERROR` | Unexpected server error |

---

## Endpoints — Authentication

### POST /auth/register

Register a new user account with email and password.

**Authentication Required:** No

**Request Body:**

```json
{
  "email": "user@example.com",
  "password": "SecureP@ssw0rd",
  "full_name": "Uwimana Alice",
  "preferred_language": "kinyarwanda"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | Yes | Valid email address |
| `password` | string | Yes | Min 8 chars, at least one uppercase, one number |
| `full_name` | string | Yes | Display name (2–100 characters) |
| `preferred_language` | string | Yes | One of: `kinyarwanda`, `english`, `french`, `swahili` |

**Success Response (201):**

```json
{
  "success": true,
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "full_name": "Uwimana Alice",
    "verification_email_sent": true
  },
  "message": "Account created. Please check your email to verify your account."
}
```

**Error Responses:**

```json
// 409 - Email already exists
{
  "success": false,
  "error": {
    "code": "USER_ALREADY_EXISTS",
    "message": "An account with this email address already exists."
  }
}
```

---

### POST /auth/login

Authenticate with email and password, receive JWT tokens.

**Authentication Required:** No

**Request Body:**

```json
{
  "email": "user@example.com",
  "password": "SecureP@ssw0rd"
}
```

**Success Response (200):**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 86400,
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@example.com",
      "full_name": "Uwimana Alice",
      "avatar_url": null,
      "preferred_language": "kinyarwanda",
      "is_admin": false
    }
  }
}
```

---

### POST /auth/firebase-login

Exchange a Firebase ID token for Ubumwe Connect JWT tokens.

**Authentication Required:** No

**Request Body:**

```json
{
  "firebase_token": "eyJhbGciOiJSUzI1NiIsImtpZCI...",
  "preferred_language": "english"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `firebase_token` | string | Yes | Valid Firebase ID token |
| `preferred_language` | string | No | Required only for first-time registration |

**Success Response (200):**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 86400,
    "is_new_user": true,
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user@gmail.com",
      "full_name": "Alice Uwimana",
      "avatar_url": "https://lh3.googleusercontent.com/...",
      "preferred_language": "english",
      "is_admin": false
    }
  }
}
```

---

### POST /auth/refresh

Refresh an expired access token.

**Authentication Required:** No (refresh token required)

**Request Body:**

```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response (200):**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 86400
  }
}
```

---

### POST /auth/logout

Invalidate the current refresh token.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response (204):** No content.

---

### POST /auth/forgot-password

Request a password reset email.

**Authentication Required:** No

**Request Body:**

```json
{
  "email": "user@example.com"
}
```

**Success Response (200):**

```json
{
  "success": true,
  "message": "If this email is registered, a password reset link has been sent."
}
```

---

### POST /auth/reset-password

Reset password using the token from the reset email.

**Authentication Required:** No

**Request Body:**

```json
{
  "token": "reset_token_from_email",
  "new_password": "NewSecureP@ssw0rd"
}
```

**Success Response (200):**

```json
{
  "success": true,
  "message": "Password has been reset successfully."
}
```

---

## Endpoints — Users

### GET /users/me

Get the currently authenticated user's profile.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "full_name": "Uwimana Alice",
    "avatar_url": "https://s3.amazonaws.com/ubumwe/avatars/alice.jpg",
    "bio": "Murikumwe | Let's talk",
    "preferred_language": "kinyarwanda",
    "phone_number": "+250788123456",
    "is_verified": true,
    "is_active": true,
    "last_seen_at": "2026-06-15T09:45:00Z",
    "created_at": "2026-01-15T08:00:00Z"
  }
}
```

---

### PATCH /users/me

Update the current user's profile.

**Authentication Required:** Yes

**Request Body (all fields optional):**

```json
{
  "full_name": "Alice Uwimana",
  "bio": "Language bridges hearts",
  "preferred_language": "english",
  "phone_number": "+250788654321"
}
```

**Response (200):** Returns updated user object (same schema as GET /users/me).

---

### POST /users/me/avatar

Upload a profile avatar image.

**Authentication Required:** Yes  
**Content-Type:** `multipart/form-data`

**Request:**

```
POST /users/me/avatar
Content-Type: multipart/form-data; boundary=----FormBoundary

------FormBoundary
Content-Disposition: form-data; name="avatar"; filename="photo.jpg"
Content-Type: image/jpeg

[binary image data]
------FormBoundary--
```

**Response (200):**

```json
{
  "success": true,
  "data": {
    "avatar_url": "https://s3.amazonaws.com/ubumwe/avatars/550e8400-avatar.jpg"
  }
}
```

---

### DELETE /users/me

Delete the current user's account and all associated data.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "password": "CurrentP@ssw0rd",
  "confirmation": "DELETE MY ACCOUNT"
}
```

**Response (204):** No content. Account and all data permanently deleted.

---

### GET /users/search

Search for users by name, email, or phone number.

**Authentication Required:** Yes

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | Yes | Search query (min 2 characters) |
| `page` | integer | No | Page number (default: 1) |
| `per_page` | integer | No | Results per page (default: 20, max: 50) |

**Example:** `GET /users/search?q=alice&page=1&per_page=10`

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "full_name": "Alice Uwimana",
        "avatar_url": "https://s3.amazonaws.com/ubumwe/avatars/alice.jpg",
        "preferred_language": "kinyarwanda",
        "is_contact": false
      }
    ],
    "pagination": {
      "page": 1,
      "per_page": 10,
      "total_items": 1,
      "total_pages": 1,
      "has_next": false,
      "has_prev": false
    }
  }
}
```

---

### GET /users/{user_id}

Get a specific user's public profile.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "full_name": "Alice Uwimana",
    "avatar_url": "https://s3.amazonaws.com/ubumwe/avatars/alice.jpg",
    "bio": "Language bridges hearts",
    "preferred_language": "kinyarwanda",
    "is_contact": true,
    "is_blocked": false,
    "last_seen_at": "2026-06-15T09:45:00Z"
  }
}
```

---

### GET /users/me/contacts

Get the current user's contact list.

**Authentication Required:** Yes

**Query Parameters:** `page`, `per_page`

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "contact-uuid-here",
        "full_name": "Bob Habimana",
        "avatar_url": null,
        "preferred_language": "french",
        "is_online": true,
        "last_seen_at": "2026-06-15T10:28:00Z",
        "contact_status": "accepted"
      }
    ],
    "pagination": { ... }
  }
}
```

---

### POST /users/me/contacts

Add a contact.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "user_id": "target-user-uuid"
}
```

**Response (201):**

```json
{
  "success": true,
  "data": {
    "contact_id": "target-user-uuid",
    "status": "accepted"
  },
  "message": "Contact added successfully."
}
```

---

### DELETE /users/me/contacts/{contact_id}

Remove a contact.

**Authentication Required:** Yes

**Response (204):** No content.

---

### POST /users/me/block/{user_id}

Block a user.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "message": "User has been blocked."
}
```

---

### DELETE /users/me/block/{user_id}

Unblock a user.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "message": "User has been unblocked."
}
```

---

### POST /users/me/push-token

Register a push notification token.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "fcm_token": "dGhpcyBpcyBhIHRlc3QgZmNtIHRva2Vu...",
  "device_id": "device-unique-id",
  "platform": "android"
}
```

**Response (200):**

```json
{
  "success": true,
  "message": "Push token registered."
}
```

---

## Endpoints — Conversations

### GET /conversations

Get the current user's conversation list.

**Authentication Required:** Yes

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | integer | 1 | Page number |
| `per_page` | integer | 20 | Results per page |
| `type` | string | null | Filter by `direct` or `group` |

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "conv-uuid",
        "type": "direct",
        "name": null,
        "avatar_url": null,
        "other_user": {
          "id": "other-user-uuid",
          "full_name": "Bob Habimana",
          "avatar_url": null,
          "is_online": false,
          "preferred_language": "french"
        },
        "last_message": {
          "id": "msg-uuid",
          "content": "Bonjour, comment ça va?",
          "original_content": "Muraho, amakuru?",
          "sender_id": "other-user-uuid",
          "content_type": "text",
          "created_at": "2026-06-15T10:20:00Z"
        },
        "unread_count": 3,
        "updated_at": "2026-06-15T10:20:00Z"
      }
    ],
    "pagination": { ... }
  }
}
```

---

### POST /conversations

Create a new conversation (direct or group).

**Authentication Required:** Yes

**Request Body — Direct:**

```json
{
  "type": "direct",
  "participant_id": "other-user-uuid"
}
```

**Request Body — Group:**

```json
{
  "type": "group",
  "name": "Kigali Tech Community",
  "description": "Discussing technology in Rwanda",
  "participant_ids": [
    "user-uuid-1",
    "user-uuid-2",
    "user-uuid-3"
  ]
}
```

**Response (201):**

```json
{
  "success": true,
  "data": {
    "id": "new-conv-uuid",
    "type": "group",
    "name": "Kigali Tech Community",
    "description": "Discussing technology in Rwanda",
    "avatar_url": null,
    "member_count": 4,
    "created_by": "current-user-uuid",
    "created_at": "2026-06-15T10:30:00Z"
  }
}
```

---

### GET /conversations/{conversation_id}

Get conversation details.

**Authentication Required:** Yes  
**Note:** Returns 403 if user is not a member.

**Response (200):**

```json
{
  "success": true,
  "data": {
    "id": "conv-uuid",
    "type": "group",
    "name": "Kigali Tech Community",
    "description": "Discussing technology in Rwanda",
    "avatar_url": "https://s3.amazonaws.com/ubumwe/group-avatars/conv-uuid.jpg",
    "member_count": 12,
    "members": [
      {
        "user_id": "user-uuid-1",
        "full_name": "Alice Uwimana",
        "avatar_url": null,
        "preferred_language": "kinyarwanda",
        "is_admin": true,
        "joined_at": "2026-06-01T08:00:00Z"
      }
    ],
    "created_by": "user-uuid-1",
    "created_at": "2026-06-01T08:00:00Z",
    "updated_at": "2026-06-15T10:20:00Z"
  }
}
```

---

### PATCH /conversations/{conversation_id}

Update group conversation details (group admin only).

**Authentication Required:** Yes

**Request Body:**

```json
{
  "name": "Updated Group Name",
  "description": "Updated description"
}
```

**Response (200):** Returns updated conversation object.

---

### DELETE /conversations/{conversation_id}

Leave (or delete) a conversation.

**Authentication Required:** Yes

**Response (204):** No content.

---

### POST /conversations/{conversation_id}/members

Add members to a group conversation.

**Authentication Required:** Yes (must be group admin)

**Request Body:**

```json
{
  "user_ids": ["new-member-uuid-1", "new-member-uuid-2"]
}
```

**Response (200):**

```json
{
  "success": true,
  "data": {
    "added_count": 2
  },
  "message": "2 member(s) added to the group."
}
```

---

### DELETE /conversations/{conversation_id}/members/{user_id}

Remove a member from a group conversation.

**Authentication Required:** Yes (must be group admin)

**Response (204):** No content.

---

### POST /conversations/{conversation_id}/read

Mark all messages in a conversation as read.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "message": "Conversation marked as read."
}
```

---

## Endpoints — Messages

### GET /conversations/{conversation_id}/messages

Get messages in a conversation (paginated, most recent first).

**Authentication Required:** Yes

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | integer | 1 | Page number |
| `per_page` | integer | 30 | Messages per page (max: 100) |
| `before_id` | string | null | Cursor-based pagination: get messages before this ID |
| `include_deleted` | boolean | false | Include soft-deleted messages |

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "msg-uuid-1",
        "conversation_id": "conv-uuid",
        "sender": {
          "id": "sender-uuid",
          "full_name": "Alice Uwimana",
          "avatar_url": null
        },
        "content_type": "text",
        "original_content": "Muraho! Amakuru?",
        "original_language": "kinyarwanda",
        "translated_content": "Hello! How are you?",
        "was_translated": true,
        "media_url": null,
        "reply_to": null,
        "is_deleted": false,
        "read_by": ["other-user-uuid"],
        "created_at": "2026-06-15T10:20:00Z"
      },
      {
        "id": "msg-uuid-2",
        "conversation_id": "conv-uuid",
        "sender": {
          "id": "sender-uuid",
          "full_name": "Alice Uwimana",
          "avatar_url": null
        },
        "content_type": "audio",
        "original_content": "[Voice Message Transcription]: Mwiriwe neza bose, ubu turabajije ibibazo...",
        "original_language": "kinyarwanda",
        "translated_content": "[Voice Message]: Good evening everyone, now let me ask some questions...",
        "was_translated": true,
        "media_url": "https://s3.amazonaws.com/ubumwe/voice/msg-uuid-2.m4a",
        "media_size_bytes": 245760,
        "media_mime_type": "audio/m4a",
        "reply_to": null,
        "is_deleted": false,
        "created_at": "2026-06-15T10:21:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "per_page": 30,
      "total_items": 147,
      "total_pages": 5,
      "has_next": true,
      "has_prev": false
    }
  }
}
```

---

### POST /conversations/{conversation_id}/messages

Send a text message.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "content": "Muraho! Amakuru?",
  "content_type": "text",
  "reply_to_id": null
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `content` | string | Yes (for text) | Message text content |
| `content_type` | string | Yes | One of: `text`, `image`, `audio`, `video`, `document` |
| `reply_to_id` | string | No | UUID of message being replied to |

**Response (201):**

```json
{
  "success": true,
  "data": {
    "id": "new-msg-uuid",
    "conversation_id": "conv-uuid",
    "sender_id": "current-user-uuid",
    "content_type": "text",
    "original_content": "Muraho! Amakuru?",
    "original_language": "kinyarwanda",
    "created_at": "2026-06-15T10:25:00Z",
    "status": "sent"
  }
}
```

---

### POST /conversations/{conversation_id}/messages/media-upload

Request a pre-signed S3 URL for media upload.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "filename": "voice_message.m4a",
  "content_type": "audio/m4a",
  "file_size_bytes": 245760
}
```

**Response (200):**

```json
{
  "success": true,
  "data": {
    "upload_url": "https://ubumwe-media.s3.amazonaws.com/voice/...",
    "upload_fields": {
      "key": "voice/2026/06/15/msg-uuid.m4a",
      "policy": "base64-encoded-policy",
      "x-amz-signature": "signature"
    },
    "media_url": "https://s3.amazonaws.com/ubumwe/voice/msg-uuid.m4a",
    "expires_in": 300
  }
}
```

**Usage:** POST the file directly to `upload_url` using `multipart/form-data` with the `upload_fields`, then send the `media_url` as the message.

---

### POST /conversations/{conversation_id}/messages/media

Send a message with a media attachment (after uploading to S3).

**Authentication Required:** Yes

**Request Body:**

```json
{
  "content_type": "audio",
  "media_url": "https://s3.amazonaws.com/ubumwe/voice/msg-uuid.m4a",
  "media_size_bytes": 245760,
  "media_mime_type": "audio/m4a",
  "reply_to_id": null
}
```

**Response (201):** Message object (same as text message response).

---

### GET /messages/{message_id}/translation/{language}

Get or trigger a translation for a specific message in a target language.

**Authentication Required:** Yes

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `message_id` | string | Message UUID |
| `language` | string | Target language: `kinyarwanda`, `english`, `french`, `swahili` |

**Response (200):**

```json
{
  "success": true,
  "data": {
    "message_id": "msg-uuid",
    "original_content": "Muraho! Amakuru?",
    "original_language": "kinyarwanda",
    "target_language": "french",
    "translated_content": "Bonjour ! Comment allez-vous ?",
    "translation_model": "gpt-4",
    "cached": true
  }
}
```

---

### DELETE /messages/{message_id}

Delete (soft-delete) a message.

**Authentication Required:** Yes (sender only, or admin)

**Response (200):**

```json
{
  "success": true,
  "message": "Message deleted."
}
```

---

### POST /messages/{message_id}/report

Report a message for policy violation.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "reason": "harassment",
  "details": "This message contains threatening language"
}
```

| Field | Allowed Values |
|-------|---------------|
| `reason` | `spam`, `harassment`, `hate_speech`, `violence`, `misinformation`, `other` |

**Response (201):**

```json
{
  "success": true,
  "message": "Report submitted. Our moderation team will review it."
}
```

---

## Endpoints — Calls

### POST /calls/initiate

Initiate a voice or video call. Creates a call record and sends notification to recipient.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "callee_id": "target-user-uuid",
  "call_type": "voice",
  "conversation_id": "conv-uuid"
}
```

| Field | Values |
|-------|--------|
| `call_type` | `voice` or `video` |

**Response (201):**

```json
{
  "success": true,
  "data": {
    "call_id": "call-uuid",
    "callee_id": "target-user-uuid",
    "call_type": "voice",
    "status": "initiated",
    "signaling_channel": "ws://...",
    "ice_servers": [
      {
        "urls": ["stun:stun.ubumweconnect.rw:3478"]
      },
      {
        "urls": ["turn:turn.ubumweconnect.rw:3478"],
        "username": "generated-username",
        "credential": "generated-credential"
      }
    ],
    "created_at": "2026-06-15T10:30:00Z"
  }
}
```

---

### POST /calls/{call_id}/answer

Answer an incoming call.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "data": {
    "call_id": "call-uuid",
    "status": "answered",
    "ice_servers": [ ... ]
  }
}
```

---

### POST /calls/{call_id}/reject

Reject an incoming call.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "data": {
    "call_id": "call-uuid",
    "status": "rejected"
  }
}
```

---

### POST /calls/{call_id}/end

End an active call.

**Authentication Required:** Yes

**Response (200):**

```json
{
  "success": true,
  "data": {
    "call_id": "call-uuid",
    "status": "ended",
    "duration_seconds": 183
  }
}
```

---

### GET /calls/history

Get call history for the current user.

**Authentication Required:** Yes

**Query Parameters:** `page`, `per_page`, `type` (voice/video), `status` (missed/answered/all)

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "call_id": "call-uuid",
        "call_type": "voice",
        "status": "ended",
        "caller": {
          "id": "caller-uuid",
          "full_name": "Alice Uwimana",
          "avatar_url": null
        },
        "callee": {
          "id": "callee-uuid",
          "full_name": "Bob Habimana",
          "avatar_url": null
        },
        "duration_seconds": 183,
        "started_at": "2026-06-15T08:00:00Z",
        "ended_at": "2026-06-15T08:03:03Z"
      }
    ],
    "pagination": { ... }
  }
}
```

---

## Endpoints — Translation

### POST /translate/text

Translate text between supported languages.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "text": "Muraho, amakuru?",
  "source_language": "kinyarwanda",
  "target_language": "english"
}
```

| Field | Values |
|-------|--------|
| `source_language` | `kinyarwanda`, `english`, `french`, `swahili`, `auto` |
| `target_language` | `kinyarwanda`, `english`, `french`, `swahili` |

**Response (200):**

```json
{
  "success": true,
  "data": {
    "original_text": "Muraho, amakuru?",
    "detected_language": "kinyarwanda",
    "target_language": "english",
    "translated_text": "Hello, how are you?",
    "translation_model": "gpt-4",
    "processing_time_ms": 387,
    "cached": false
  }
}
```

---

### POST /translate/audio

Transcribe and translate an audio file.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "audio_url": "https://s3.amazonaws.com/ubumwe/voice/audio-uuid.m4a",
  "source_language": "auto",
  "target_language": "english"
}
```

**Response (200):**

```json
{
  "success": true,
  "data": {
    "audio_url": "https://s3.amazonaws.com/ubumwe/voice/audio-uuid.m4a",
    "detected_language": "kinyarwanda",
    "transcription": "Mwiriwe neza bose, ubu turabajije...",
    "translation": "Good evening everyone, now let me ask...",
    "target_language": "english",
    "processing_time_ms": 4230
  }
}
```

---

### GET /translate/languages

Get list of supported languages.

**Authentication Required:** No

**Response (200):**

```json
{
  "success": true,
  "data": {
    "languages": [
      {
        "code": "kinyarwanda",
        "name": "Kinyarwanda",
        "native_name": "Ikinyarwanda",
        "flag_emoji": "🇷🇼"
      },
      {
        "code": "english",
        "name": "English",
        "native_name": "English",
        "flag_emoji": "🇬🇧"
      },
      {
        "code": "french",
        "name": "French",
        "native_name": "Français",
        "flag_emoji": "🇫🇷"
      },
      {
        "code": "swahili",
        "name": "Swahili",
        "native_name": "Kiswahili",
        "flag_emoji": "🌍"
      }
    ]
  }
}
```

---

## Endpoints — AI Assistant

### POST /conversations/{conversation_id}/ai/chat

Send a message to the AI assistant within a conversation context.

**Authentication Required:** Yes

**Request Body:**

```json
{
  "message": "What does 'ubumwe' mean in Kinyarwanda?",
  "include_conversation_context": true
}
```

**Response (200):**

```json
{
  "success": true,
  "data": {
    "response": "The word 'ubumwe' in Kinyarwanda means 'unity' or 'togetherness'. It comes from the root '-mwe' meaning 'one', with the prefix 'ubu-' forming an abstract noun. The concept is central to Rwandan social philosophy, often expressed in the phrase 'Ubumwe n'amahoro' (Unity and Peace). The platform is named Ubumwe Connect to reflect its mission of bringing people together across language barriers.",
    "message_id": "ai-msg-uuid",
    "tokens_used": 94,
    "created_at": "2026-06-15T10:35:00Z"
  }
}
```

---

### GET /conversations/{conversation_id}/ai/history

Get AI assistant conversation history.

**Authentication Required:** Yes

**Response (200):** Paginated list of AI messages (same pagination schema as messages).

---

### DELETE /conversations/{conversation_id}/ai/history

Clear AI assistant conversation history for this conversation.

**Authentication Required:** Yes

**Response (204):** No content.

---

## Endpoints — Admin

All admin endpoints require an administrator account (`is_admin: true`).

### GET /admin/stats

Get system-wide usage statistics.

**Authentication Required:** Yes (Admin only)

**Response (200):**

```json
{
  "success": true,
  "data": {
    "users": {
      "total": 1247,
      "active_today": 342,
      "active_this_week": 891,
      "new_this_month": 156,
      "by_language": {
        "kinyarwanda": 624,
        "english": 312,
        "french": 187,
        "swahili": 124
      }
    },
    "messages": {
      "total_sent": 45621,
      "sent_today": 2341,
      "translations_performed_today": 1893,
      "voice_messages_today": 456
    },
    "calls": {
      "total": 3421,
      "today": 187,
      "average_duration_seconds": 234
    },
    "system": {
      "api_response_time_avg_ms": 87,
      "translation_latency_avg_ms": 412,
      "websocket_connections_active": 234,
      "storage_used_gb": 12.4
    }
  }
}
```

---

### GET /admin/users

List all users with search and filter options.

**Authentication Required:** Yes (Admin)

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Search by name or email |
| `status` | string | `active`, `suspended`, `all` |
| `language` | string | Filter by preferred language |
| `page` | integer | Page number |
| `per_page` | integer | Results per page (max: 100) |

**Response (200):** Paginated list of full user objects.

---

### GET /admin/users/{user_id}

Get full user details (admin view includes additional fields).

**Authentication Required:** Yes (Admin)

**Response (200):** Full user object with admin-only fields: `total_messages_sent`, `total_calls_made`, `report_count`, `is_suspended`, `suspension_reason`, `suspension_ends_at`.

---

### PATCH /admin/users/{user_id}

Update user status (suspend, restore, promote/demote admin).

**Authentication Required:** Yes (Admin)

**Request Body:**

```json
{
  "action": "suspend",
  "reason": "Repeated policy violations",
  "duration_days": 7
}
```

| Action | Description |
|--------|-------------|
| `suspend` | Suspend user account |
| `restore` | Restore suspended account |
| `make_admin` | Grant admin privileges |
| `revoke_admin` | Remove admin privileges |
| `delete` | Permanently delete account |

**Response (200):**

```json
{
  "success": true,
  "message": "User account suspended for 7 days.",
  "data": {
    "user_id": "user-uuid",
    "action": "suspend",
    "suspension_ends_at": "2026-06-22T10:30:00Z"
  }
}
```

---

### GET /admin/reports

Get list of user-submitted reports.

**Authentication Required:** Yes (Admin)

**Query Parameters:** `status` (pending/resolved/all), `reason`, `page`, `per_page`

**Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "report_id": "report-uuid",
        "reported_user": { "id": "...", "full_name": "..." },
        "reporter": { "id": "...", "full_name": "..." },
        "reported_message": { "id": "...", "content": "..." },
        "reason": "harassment",
        "details": "This message contains threatening language",
        "status": "pending",
        "created_at": "2026-06-15T08:00:00Z"
      }
    ],
    "pagination": { ... }
  }
}
```

---

### PATCH /admin/reports/{report_id}

Resolve a report.

**Authentication Required:** Yes (Admin)

**Request Body:**

```json
{
  "action": "warn_user",
  "resolution_notes": "First-time offence, warning issued."
}
```

| Action | Description |
|--------|-------------|
| `dismiss` | No action taken, report dismissed |
| `warn_user` | Issue formal warning to reported user |
| `suspend_user` | Suspend reported user |
| `delete_message` | Delete the reported message |
| `ban_user` | Permanently ban reported user |

**Response (200):** Resolved report object.

---

### GET /admin/audit-log

Get the audit log of administrative actions.

**Authentication Required:** Yes (Admin)

**Query Parameters:** `admin_id`, `action_type`, `from_date`, `to_date`, `page`, `per_page`

**Response (200):** Paginated list of audit log entries.

---

## WebSocket Events

### Connection

Connect to the WebSocket with the JWT access token:

```
wss://api.ubumweconnect.rw/ws/{user_id}?token=<access_token>
```

On successful connection, the server sends:

```json
{
  "event": "CONNECTED",
  "data": {
    "user_id": "current-user-uuid",
    "server_time": "2026-06-15T10:30:00Z"
  }
}
```

### Heartbeat / Keepalive

The client must send a ping every 30 seconds:

```json
{
  "event": "PING",
  "data": {}
}
```

Server responds:

```json
{
  "event": "PONG",
  "data": {
    "server_time": "2026-06-15T10:30:30Z"
  }
}
```

### Outbound Events (Client → Server)

#### TYPING_START

```json
{
  "event": "TYPING_START",
  "data": {
    "conversation_id": "conv-uuid"
  }
}
```

#### TYPING_STOP

```json
{
  "event": "TYPING_STOP",
  "data": {
    "conversation_id": "conv-uuid"
  }
}
```

#### CALL_OFFER (WebRTC signalling)

```json
{
  "event": "CALL_OFFER",
  "data": {
    "call_id": "call-uuid",
    "callee_id": "target-user-uuid",
    "sdp": {
      "type": "offer",
      "sdp": "v=0\r\no=- 123456789 2 IN IP4 127.0.0.1\r\n..."
    }
  }
}
```

#### CALL_ANSWER

```json
{
  "event": "CALL_ANSWER",
  "data": {
    "call_id": "call-uuid",
    "sdp": {
      "type": "answer",
      "sdp": "v=0\r\no=- 987654321 2 IN IP4 127.0.0.1\r\n..."
    }
  }
}
```

#### ICE_CANDIDATE

```json
{
  "event": "ICE_CANDIDATE",
  "data": {
    "call_id": "call-uuid",
    "target_user_id": "other-party-uuid",
    "candidate": {
      "candidate": "candidate:1 1 UDP 2130706431 192.168.1.100 54321 typ host",
      "sdpMid": "0",
      "sdpMLineIndex": 0
    }
  }
}
```

#### CALL_SUBTITLE_CHUNK (Audio for live subtitle generation)

```json
{
  "event": "CALL_SUBTITLE_CHUNK",
  "data": {
    "call_id": "call-uuid",
    "audio_chunk_base64": "base64-encoded-3-second-audio-chunk",
    "chunk_index": 5,
    "source_language": "kinyarwanda"
  }
}
```

### Inbound Events (Server → Client)

#### NEW_MESSAGE

```json
{
  "event": "NEW_MESSAGE",
  "data": {
    "id": "msg-uuid",
    "conversation_id": "conv-uuid",
    "sender": {
      "id": "sender-uuid",
      "full_name": "Alice Uwimana",
      "avatar_url": null
    },
    "content_type": "text",
    "original_content": "Muraho! Amakuru?",
    "original_language": "kinyarwanda",
    "translated_content": "Hello! How are you?",
    "was_translated": true,
    "reply_to": null,
    "created_at": "2026-06-15T10:20:00Z"
  }
}
```

#### MESSAGE_DELIVERED

```json
{
  "event": "MESSAGE_DELIVERED",
  "data": {
    "message_id": "msg-uuid",
    "conversation_id": "conv-uuid",
    "delivered_at": "2026-06-15T10:20:01Z"
  }
}
```

#### MESSAGE_READ

```json
{
  "event": "MESSAGE_READ",
  "data": {
    "message_id": "msg-uuid",
    "conversation_id": "conv-uuid",
    "read_by_user_id": "other-user-uuid",
    "read_at": "2026-06-15T10:21:00Z"
  }
}
```

#### MESSAGE_DELETED

```json
{
  "event": "MESSAGE_DELETED",
  "data": {
    "message_id": "msg-uuid",
    "conversation_id": "conv-uuid",
    "deleted_at": "2026-06-15T10:25:00Z"
  }
}
```

#### TYPING_INDICATOR

```json
{
  "event": "TYPING_INDICATOR",
  "data": {
    "conversation_id": "conv-uuid",
    "user_id": "typing-user-uuid",
    "user_name": "Alice Uwimana",
    "is_typing": true
  }
}
```

#### USER_ONLINE_STATUS

```json
{
  "event": "USER_ONLINE_STATUS",
  "data": {
    "user_id": "user-uuid",
    "is_online": true,
    "last_seen_at": null
  }
}
```

#### INCOMING_CALL

```json
{
  "event": "INCOMING_CALL",
  "data": {
    "call_id": "call-uuid",
    "caller": {
      "id": "caller-uuid",
      "full_name": "Alice Uwimana",
      "avatar_url": null,
      "preferred_language": "kinyarwanda"
    },
    "call_type": "voice",
    "conversation_id": "conv-uuid"
  }
}
```

#### CALL_OFFER_RELAY / CALL_ANSWER_RELAY / ICE_CANDIDATE_RELAY

Server relays WebRTC signalling messages between peers with the same payload structure as the outbound events.

#### CALL_SUBTITLE

```json
{
  "event": "CALL_SUBTITLE",
  "data": {
    "call_id": "call-uuid",
    "chunk_index": 5,
    "transcription": "Mwiriwe neza bose",
    "translation": "Good evening everyone",
    "source_language": "kinyarwanda",
    "target_language": "english",
    "is_final": false
  }
}
```

#### CALL_STATUS_UPDATE

```json
{
  "event": "CALL_STATUS_UPDATE",
  "data": {
    "call_id": "call-uuid",
    "status": "ended",
    "reason": "normal_hangup",
    "duration_seconds": 183
  }
}
```

---

## Code Examples

### cURL — Register and Login

```bash
# Register
curl -X POST https://api.ubumweconnect.rw/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "SecureP@ssw0rd",
    "full_name": "Uwimana Alice",
    "preferred_language": "kinyarwanda"
  }'

# Login
curl -X POST https://api.ubumweconnect.rw/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "SecureP@ssw0rd"
  }'
```

### cURL — Send a Message

```bash
ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
CONV_ID="conv-uuid-here"

curl -X POST https://api.ubumweconnect.rw/api/v1/conversations/$CONV_ID/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Muraho! Amakuru?",
    "content_type": "text"
  }'
```

### Python — Complete Example

```python
import httpx
import asyncio
import websockets
import json

BASE_URL = "https://api.ubumweconnect.rw/api/v1"
WS_URL = "wss://api.ubumweconnect.rw/ws"

class UbumweConnectClient:
    def __init__(self):
        self.access_token = None
        self.user_id = None
        self.client = httpx.AsyncClient()
    
    async def login(self, email: str, password: str):
        response = await self.client.post(
            f"{BASE_URL}/auth/login",
            json={"email": email, "password": password}
        )
        data = response.json()
        if data["success"]:
            self.access_token = data["data"]["access_token"]
            self.user_id = data["data"]["user"]["id"]
            return True
        return False
    
    @property
    def headers(self):
        return {"Authorization": f"Bearer {self.access_token}"}
    
    async def send_message(self, conversation_id: str, content: str):
        response = await self.client.post(
            f"{BASE_URL}/conversations/{conversation_id}/messages",
            headers=self.headers,
            json={"content": content, "content_type": "text"}
        )
        return response.json()
    
    async def translate(self, text: str, source: str, target: str):
        response = await self.client.post(
            f"{BASE_URL}/translate/text",
            headers=self.headers,
            json={
                "text": text,
                "source_language": source,
                "target_language": target
            }
        )
        return response.json()["data"]["translated_text"]
    
    async def listen_for_messages(self, conversation_id: str):
        ws_uri = f"{WS_URL}/{self.user_id}?token={self.access_token}"
        async with websockets.connect(ws_uri) as ws:
            print("Connected to WebSocket")
            # Send ping every 30 seconds
            async def keepalive():
                while True:
                    await ws.send(json.dumps({"event": "PING", "data": {}}))
                    await asyncio.sleep(30)
            
            asyncio.create_task(keepalive())
            
            async for message in ws:
                event = json.loads(message)
                if event["event"] == "NEW_MESSAGE":
                    msg = event["data"]
                    if msg["conversation_id"] == conversation_id:
                        print(f"New message: {msg.get('translated_content', msg['original_content'])}")

async def main():
    client = UbumweConnectClient()
    
    if await client.login("alice@example.com", "SecureP@ssw0rd"):
        print("Logged in successfully")
        
        # Translate some text
        translation = await client.translate(
            "Muraho, amakuru?", 
            "kinyarwanda", 
            "english"
        )
        print(f"Translation: {translation}")
        
        # Listen for messages
        await client.listen_for_messages("conv-uuid-here")

asyncio.run(main())
```

### Dart/Flutter — API Client

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class UbumweConnectApi {
  static const String baseUrl = 'https://api.ubumweconnect.rw/api/v1';
  static const String wsUrl = 'wss://api.ubumweconnect.rw/ws';
  
  String? _accessToken;
  String? _userId;
  WebSocketChannel? _wsChannel;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_accessToken',
  };

  /// Login with email and password
  Future<Map<String, dynamic>?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _accessToken = data['data']['access_token'];
      _userId = data['data']['user']['id'];
      return data['data']['user'];
    }
    return null;
  }

  /// Send a text message
  Future<Map<String, dynamic>?> sendMessage(
    String conversationId, 
    String content
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages'),
      headers: _headers,
      body: jsonEncode({
        'content': content,
        'content_type': 'text',
      }),
    );
    
    if (response.statusCode == 201) {
      return jsonDecode(response.body)['data'];
    }
    return null;
  }

  /// Get conversations list
  Future<List<dynamic>> getConversations({int page = 1}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations?page=$page&per_page=20'),
      headers: _headers,
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['items'];
    }
    return [];
  }

  /// Get messages for a conversation
  Future<List<dynamic>> getMessages(
    String conversationId, {
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/$conversationId/messages?page=$page'),
      headers: _headers,
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['items'];
    }
    return [];
  }

  /// Translate text
  Future<String?> translateText(
    String text, 
    String sourceLanguage, 
    String targetLanguage,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/translate/text'),
      headers: _headers,
      body: jsonEncode({
        'text': text,
        'source_language': sourceLanguage,
        'target_language': targetLanguage,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['translated_text'];
    }
    return null;
  }

  /// Connect to WebSocket
  void connectWebSocket(Function(Map<String, dynamic>) onEvent) {
    final wsUri = Uri.parse('$wsUrl/$_userId?token=$_accessToken');
    _wsChannel = WebSocketChannel.connect(wsUri);
    
    _wsChannel!.stream.listen(
      (message) {
        final event = jsonDecode(message as String);
        onEvent(event);
      },
      onError: (error) => print('WebSocket error: $error'),
      onDone: () => print('WebSocket connection closed'),
    );
    
    // Send typing indicator
  }

  void sendTypingStart(String conversationId) {
    _wsChannel?.sink.add(jsonEncode({
      'event': 'TYPING_START',
      'data': {'conversation_id': conversationId},
    }));
  }

  void sendPing() {
    _wsChannel?.sink.add(jsonEncode({
      'event': 'PING',
      'data': {},
    }));
  }

  void disconnect() {
    _wsChannel?.sink.close();
    _wsChannel = null;
  }
}
```
