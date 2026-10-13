# 🎯 Ubumwe Connect Frontend - Complete User Experience Guide

## Overview
Ubumwe Connect is an **AI-powered multilingual real-time communication platform** with end-to-end messaging, voice/video calls, and automatic translation across 100+ languages.

---

## 🔄 Complete User Journey

### 1️⃣ **Splash Screen** (Initial Load)
**Route:** `/splash`  
**Duration:** 2.8 seconds with animations

**Features:**
- Animated fade-in of Ubumwe logo with scale and slide effects
- Checks for existing authentication token
- Auto-navigation based on user status

**Flow Logic:**
```
┌─ Has Auth Token? ──► Navigate to /home (Dashboard)
│
├─ No Token + Onboarding Done? ──► Navigate to /login
│
└─ First Time User? ──► Navigate to /onboarding
```

---

### 2️⃣ **Authentication Flow** (Un-authenticated Users)

#### **A. Onboarding Screen** (First Time Only)
**Route:** `/onboarding`  
**Purpose:** Welcome new users, explain app features

**UI Elements:**
- App introduction slides
- Feature showcase (Messaging, Calls, Translation)
- Language selection
- CTA: "Get Started" button

**Next Step:** → `/login`

---

#### **B. Login Screen**
**Route:** `/login`  
**Purpose:** Authenticate existing users

**Features:**
- Email/Password login form
- Real-time form validation
- Error messages with snackbar notifications
- "Show/Hide Password" toggle
- "Forgot Password?" link
- **Google Sign-In** social authentication (Firebase)
- "New to Ubumwe? Register" link

**Credentials Validation:**
```javascript
✓ Email: Valid email format
✓ Password: Not empty
✓ Submit: Enabled only when both fields valid
```

**Success Action:** 
- Stores access token + refresh token locally
- Navigates to `/home`

**Forgot Password Flow:**
```
Tap "Forgot Password?" → /forgot-password
  ↓
Enter email address
  ↓
Receive reset link (simulated)
  ↓
Return to /login → Enter new password
```

---

#### **C. Register Screen**
**Route:** `/register`  
**Purpose:** Create new account

**Form Fields:**
- Full Name (required)
- Email (required, validated)
- Password (required, 8+ chars)
- Confirm Password (must match)
- Terms & Conditions checkbox

**Success Action:**
- Creates account via `/auth/register` API
- Auto-navigates to `/login`

---

### 3️⃣ **Main Dashboard** (Authenticated Users)
**Route:** `/home` (Shell Route with 3-tab navigation)  
**Architecture:** Bottom Navigation with 3 tabs

```
┌─────────────────────────────────────┐
│         Page Content Area           │
├─────────────────────────────────────┤
│ 💬 Chats │ 👥 Contacts │ 👤 Profile │
└─────────────────────────────────────┘
```

---

## 📋 Tab 1: **CHATS** (`/home`)
**Screen:** `ChatListScreen`  
**Shows:** All conversations/discussions

### UI Features:
- **Header:**
  - Greeting: "Messages" with tagline "Stay close, across every language"
  - Search icon (toggle search mode)
  - Notifications icon
  
- **Search Mode:**
  - Auto-focus search field when activated
  - Real-time filtering of conversations
  - Clear button to reset search

- **Conversation List:**
  - Conversation item shows:
    - User avatar (circular)
    - User name
    - Last message preview (truncated)
    - Last message timestamp (relative time: "5m ago", "Today", etc.)
    - Unread message badge (count)
  
  - **Swipe Actions:** (swipe left/right)
    - Pin important conversations
    - Mark as read/unread
    - Archive/Delete

- **Floating Action Button:**
  - Green "+" button → Opens "New Conversation" modal

### Actions:
| Action | Destination | Purpose |
|--------|-------------|---------|
| Tap conversation | `/chat/{conversationId}` | Open chat window |
| Tap "+" button | `/new-conversation` | Start new chat |
| Tap search | Filters conversations | Search by name/message |
| Swipe action | Archive/Pin/Delete | Manage conversations |

---

## 💬 **Chat Screen** (Deep Dive)
**Route:** `/chat/:conversationId`  
**Screen:** `ChatScreen` - Main messaging interface

### Real-Time Features with WebSocket:
```
Connected ──► Listen for:
              ├─ new_message (incoming)
              ├─ user_typing (other person typing)
              ├─ message_read (read confirmation)
              ├─ message_edited (message updates)
              ├─ user_online_status (online/offline)
              └─ call_incoming (incoming call notification)
```

### UI Sections:

#### **Header:**
```
┌─────────────────────────────────────┐
│ ◄ | Avatar | Name | Online Status |  ☎️  📹 ⋮
└─────────────────────────────────────┘
```
- Back button (return to chat list)
- Contact avatar + name
- Real-time online/offline status
- Voice call icon → `/call/voice/{callId}`
- Video call icon → `/call/video/{callId}`
- More options menu (info, clear history, block, etc.)

#### **Message Area:**
**Message Bubble Types:**
1. **Text Message** (Sender's bubble on right, receiver's on left)
   - Message text (auto-wraps, supports emojis)
   - Timestamp
   - Read status indicator (✓ unread, ✓✓ read)
   - Message actions (reply, react, delete)

2. **Image Message**
   - Thumbnail preview
   - Tap to open in full-screen viewer
   - Download option

3. **Audio Message**
   - Waveform visualization
   - Play/Pause button
   - Duration (5s, 45s, etc.)
   - Trimmed starting text (showing first words)

4. **File Message**
   - File icon + name
   - File size
   - Download button

5. **Translated Message**
   - Original text (dimmed)
   - Translation (highlighted)
   - Language tags: "Kinyarwanda ➜ English"

6. **Typing Indicator**
   ```
   💬 Jamal is typing...
      ···  (animated dots)
   ```
   - Appears when other user types
   - Auto-hides when typing stops

#### **Message Input Area:**
```
┌──────────────────────────────────┐
│📎 🎤 │ Message text field... │ ▶️ │
└──────────────────────────────────┘
```

**Input Components:**
- **Attachment button (📎):** Opens action sheet
  - 📷 Tap to send image (from camera/gallery)
  - 📄 Send file (documents, PDFs)
  - 🎵 Send audio file
  - 📍 Share location
  
- **Voice Record button (🎤):** 
  - Tap to start recording
  - Slide down to cancel
  - Release to send audio message
  - Shows: "Tap to record voice message (60s max)"
  
- **Message Input Field:**
  - Multi-line text support (auto-expands)
  - Mention support: "@John" → Shows user suggestions
  - Emoji keyboard support
  - Draft auto-save (stored locally)
  
- **Send Button (▶️):**
  - Enabled only when text/media present
  - Shows loading spinner while uploading
  - Auto-hides when switching to voice mode

**Typing Indicator:**
- While user types, sends "typing" event every 1s
- Other user sees animated "is typing..." indicator
- Auto-clears after 3s of no activity

### Translation Feature (Real-Time):
```
Original Message (Kinyarwanda):
"Muraho! Amakuru yawe?"

↓ AI Translation (OpenAI API)

Translated (English):
"Hello! How are you?"
```
- Language auto-detection from user settings
- Manual translation button: "Tap to translate"
- Translation cache to avoid duplicate API calls
- Shows translation accuracy percentage

### Advanced Actions:

**Reply to Message:**
```
Swipe left on message ──► Shows quote preview
                         Quoted text appears in input
                         Auto-fills "@username replied:"
```

**React with Emoji:**
```
Long-press message ──► Emoji picker appears
                       Select emoji (👍, ❤️, 😂, etc.)
                       Reaction count updates
```

**Edit Message:**
```
Long-press own message ──► Edit option
                           Modify text
                           Resend with "(edited)" indicator
```

**Delete Message:**
```
Long-press own message ──► Delete option
                           Message deleted for all users
                           Shows "This message was deleted"
```

---

## ☎️ **Voice Call Screen**
**Route:** `/call/voice/:callId`  
**Screen:** `VoiceCallScreen` - Real-time voice calling

### UI Layout:
```
┌─────────────────────────────────────┐
│  Ubumwe Connect        00:45        │  ← Duration timer
├─────────────────────────────────────┤
│                                     │
│        👤                           │
│        John Smith                   │
│        (Connected - 45 seconds)     │
│                                     │
│  "Muraho! How are you today?"       │  ← Live subtitles
│  (Translated from Kinyarwanda)      │
│                                     │
├─────────────────────────────────────┤
│  🔴 Mute │ Speaker │ Subtitles │ 🔴 │ ← Call actions
└─────────────────────────────────────┘
```

### Features:

**Call Status Updates:**
- "Connecting..." → "Ringing..." → "Connected" → "Call ended"
- Duration timer increments each second
- Audio visualizer (waveform moving to audio)

**Media Controls (Bottom):**
| Icon | Function | Toggle |
|------|----------|--------|
| 🔴 | End Call | No (terminates call) |
| 🔇/🎤 | Mute/Unmute | Yes (visual feedback) |
| 📢/🔊 | Speaker/Earpiece | Yes (rotates device audio output) |
| 📝/📖 | Show/Hide Subtitles | Yes (closed captions) |

**Live Subtitles Feature (Real-Time STT + Translation):**
```
User speaks: "Muraho! How are you?"
         ↓
[Whisper API] ← Speech-to-Text conversion
         ↓
STT Output: "Muraho! How are you?"
         ↓
[OpenAI API] ← Language detection + Translation
         ↓
Display: "Muraho! How are you?"
         "(Hello! How are you?)"
```
- Updates every ~3 seconds
- Shows both original language + translation
- Useful for accessibility + understanding

**Call Quality Indicator:**
- Green dot: Excellent connection
- Yellow dot: Good connection
- Red dot: Poor connection

**WebRTC Connection:**
- P2P audio streaming (low latency)
- Fallback to relay server if P2P fails
- TURN server configuration for NAT traversal

---

## 📹 **Video Call Screen**
**Route:** `/call/video/:callId`  
**Screen:** `VideoCallScreen`

### UI Layout:
```
┌─────────────────────────────────────┐
│  ◄ | Time: 02:15                    │
├─────────────────────────────────────┤
│          🖥️                         │ ← Remote video feed (large)
│      John's Video                   │   (full screen)
│                                     │
│          📹 Your camera (small)     │ ← PiP (Picture-in-Picture)
│        (bottom-right corner)        │   Tap to swap/fullscreen
│                                     │
├─────────────────────────────────────┤
│  🔴 End│🔇 Mute│📹 Camera│Screen│ 🎥 │
│ Call   │      │Toggle │Share  │Flip│
└─────────────────────────────────────┘
```

### Features:

**Video Feeds:**
- **Remote Video:** Larger feed of the person you're calling
- **Local Camera PiP:** Your video in corner (resize/drag capable)
- **Tap to swap:** Flip which video is large

**Camera Controls:**
```
Front Camera (default) ⟷ Flip ⟷ Back Camera
```

**Lighting/Video Quality:**
- Auto-adjusts to lighting conditions
- Manual resolution selection (HD, SD, low-bandwidth mode)

**Screen Sharing:**
- Tap "Screen" button → Choose app/window to share
- Shows remote cursor movement
- Quality degrades gracefully with poor connection

**Video-Specific Media Controls:**
| Control | Function |
|---------|----------|
| 🔴 | End video call |
| 🔇/🎤 | Mute/unmute audio |
| 📹 On/Off | Toggle camera (keep audio) |
| 🖥️ Share | Screen share on/off |
| 🔄 | Flip front/back camera |

**Recording:** (User notice shown)
- Local recording option available
- Cloud backup option with encryption

---

## 📞 **Incoming Call Screen**
**Route:** `/incoming-call` OR modal overlay  
**Trigger:** WebSocket `call_incoming` event

### Appearance:
```
┌──────────────────────────────────────┐
│         🔔 Incoming Call             │
│                                      │
│           👤                         │
│        Jamal Niyibizi               │
│                                      │
│  [💬 Message] [📞 Accept] [🔴 Reject]│
└──────────────────────────────────────┘
```

### Behaviors:
- **System Notification:** OS-level notification with app badge
- **Ringtone:** Plays default system sound (or custom)
- **Vibration:** Device vibrates 3x

**Actions:**
| Button | Action |
|--------|--------|
| 💬 Message | Send quick reply (30s timeout) |
| 📞 Accept | Connects call → `/call/voice/:callId` OR `/call/video/:callId` |
| 🔴 Reject | Declines call → Returns to previous screen |

**Auto-Dismiss:**
- Rings for 30 seconds, then auto-rejects
- Caller sees "Call declined" / "No answer"
- Missed call notification added

---

## 👥 **Tab 2: CONTACTS** (`/contacts`)
**Screen:** `ContactsScreen`  
**Shows:** All users you can message

### UI Components:

**Header:**
```
Contacts                           👤➕
         ↑ Tab title              ↑ Add contact button
```

**Search Bar:**
```
┌─────────────────────────────────┐
│ 🔍 Search contacts...           │
└─────────────────────────────────┘
```
- Real-time search (filters as you type)
- Searches by: name, username, email
- Clear button appears on active search

**Contact List (Alphabetically Grouped):**
```
━ A ━━━━━━━━━━━━━━━━━
  👤 Alice Johnson     (Last active: 2m ago)
  👤 Abubakar Kim      (Online now)

━ B ━━━━━━━━━━━━━━━━━
  👤 Benson Okafor     (Last active: 1h ago)

━ J ━━━━━━━━━━━━━━━━━
  👤 Jamal Niyibizi    (Online now)
```

**Contact Item Details:**
- Avatar (first letter if no image)
- Display name
- Username (@handle)
- Real-time status:
  - ✅ "Online now"
  - ⏱️ "Last active 5m ago"
  - ⭕ "Offline" (gray dot)
- Presence indicator (green dot = online)

### Contact Actions:

**Tap Contact → User Profile:**
```
Navigate to: /user/:userId
```

**Tap "➕" Add Button:**
```
Modal: Search & Add New Contact
├─ Search field (find by name/email)
├─ User suggestions (like Google Contacts)
├─ Add confirmation
└─ "Send Friend Request" option
```

---

## 🔍 **User Profile Screen**
**Route:** `/user/:userId`  
**Screen:** `UserProfileScreen`

### Profile Card:
```
┌──────────────────────────────────────┐
│  ◄ More options (⋮)                  │
├──────────────────────────────────────┤
│           👤                         │
│        Jamal Niyibizi                │
│      @jamal_niyibizi                 │
│     📍 Kigali, Rwanda                │
│                                      │
│  💬 "Building bridges across        │
│   languages, one message at a time" │
│                                      │
│      ✅ Online (Active 2m ago)       │
├──────────────────────────────────────┤
│  [💬 Message]  [☎️ Call]  [📹 Video] │
├──────────────────────────────────────┤
│  Shared Groups     5                 │
│  Shared Contacts   12                │
│  Conversation Since  Oct 2024        │
└──────────────────────────────────────┘
```

### Profile Information:
- Avatar (tap to zoom/view gallery)
- Name + Username
- Bio/Status
- Location
- Verification badge (if verified)
- Online status + last active time
- Mutual connections count

### Action Buttons:
| Button | Action |
|--------|--------|
| 💬 Message | Open chat → `/chat/conversationId` |
| ☎️ Call | Initiate voice call → `/call/voice/:callId` |
| 📹 Video | Initiate video call → `/call/video/:callId` |
| ⋮ Menu | Block, Report, View shared media, etc. |

---

## 👤 **Tab 3: PROFILE** (`/profile`)
**Screen:** `ProfileScreen`  
**Shows:** Your account information & settings

### My Profile Card:
```
┌──────────────────────────────────────┐
│      👤 (tap to change photo)        │
│                                      │
│      Your Display Name               │
│        @username                     │
│                                      │
│      ✏️ [Edit Profile]   ⚙️ [Settings] │
└──────────────────────────────────────┘
```

### Dashboard Sections:

**Stats Row:**
```
┌──────────┬──────────┬──────────┐
│ 10       │ 25       │ 142      │
│ Contacts │ Chats    │ Messages │
└──────────┴──────────┴──────────┘
```

**Quick Actions:**
```
[📋 Blocked Users]  [🔐 Privacy]  [🔔 Notifications]
[💾 Storage]        [📊 Stats]    [📱 Devices]
```

**Account Menu:**
```
⚙️ Settings
📝 Edit Profile
🔑 Change Password
🌐 Language Preferences
📱 Connected Devices
🔐 Two-Factor Auth
📋 Blocked List
❓ Help & Support
📜 Terms & Privacy
🚪 Logout
```

### Button: **Edit Profile**
Route: `/edit-profile`  
Opens form to edit:
- Display name
- Bio
- Avatar (upload/camera/gallery)
- Username (if not yet set)
- Status (online, away, busy, offline)
- Location (optional)

---

## ⚙️ **Settings Screen**
**Route:** `/settings`  
**Screen:** `SettingsScreen`

### Sections:

**1. Notifications**
```
☐ Push Notifications (toggle)
☐ Email Notifications (toggle)
☐ Message Sound (toggle)
☐ Call Ringtone (toggle)
☐ Vibration (toggle)
  └─ Intensity: Off / Light / Medium / Strong

   Notify me for:
   ☑ Messages
   ☑ Calls
   ☑ Group Invites
   ☑ State Changes (online, offline)
```

**2. Privacy & Security**
```
👁️ Who can see my profile?
   └─ Everyone / Contacts Only / Nobody

👂 Who can message me?
   └─ Everyone / Contacts Only

📞 Who can call me?
   └─ Everyone / Contacts Only / No one

🔒 Two-Factor Authentication
   └─ [Enable/Disable]

🔐 Privacy Mode
   └─ Hide "last seen" status
   └─ Hide "typing" indicator
   └─ Hide "read receipts"
```

**3. Language & Translation**
```
Language: [English ▼]
  └─ English, Français, Kinyarwanda, Español, etc.

Auto-Translate Messages: [ON ▼]
  └─ ON: Translate incoming messages immediately
  └─ OFF: Manual translation per message
  └─ ASK: Prompt before translating

Preferred Languages:
  [+ Add Language]
  Kinyarwanda (Primary)
  English (Secondary)
  Français (Tertiary)
```

**4. Storage & Cache**
```
📊 App Storage: 245 MB
  ├─ Cache: 145 MB [Clear Cache]
  ├─ Downloaded Files: 85 MB
  └─ Database: 15 MB

Auto-clear Cache: [ON ▼]
  └─ Never / Weekly / Monthly
```

**5. Account & Session**
```
🔐 Change Password
📱 Connected Devices
   ├─ This Phone (Windows Desktop)
   ├─ iPhone Pro (2 weeks ago)
   └─ [Remove] buttons for each
```

**6. Help & Support**
```
❓ FAQ
📧 Contact Support
🐛 Report Bug
💡 Feature Request
📞 Customer Service Number
```

**7. Legal & Policies**
```
📜 Terms of Service
🔒 Privacy Policy
📋 Cookie Policy
⚖️ Community Guidelines
```

**8. Account**
```
🚪 [Logout Button] - Red
   (Confirms: "Sure? You'll need to login again")

🗑️ [Delete Account] - Dark Red
   (Shows warning: "This action is permanent!")
```

---

## 🌐 **Language Settings Screen**
**Route:** `/settings/language`  
**Screen:** `LanguageSettingsScreen`

### Interface:
```
┌──────────────────────────────────┐
│  ◄ Language Settings             │
├──────────────────────────────────┤
│                                  │
│  App Language: [English ▼]       │
│  └─ Changes UI language          │
│                                  │
│  [English, 中文, العربية, ...]   │
│                                  │
│  Auto-Translate: [ON/OFF]        │
│  ├─ Text Messages                │
│ │ ├─ Voice Messages              │
│  └─ Call Subtitles               │
│                                  │
│  My Languages (Preferences):     │
│  ┌─────────────────────────────┐ │
│  │ 🥇 Kinyarwanda (Native)    │X│ │
│  │ 🥈 English                 │X│ │
│  │ 🥉 French                  │X│ │
│  │ + Add Language...             │ │
│  └─────────────────────────────┘ │
│                                  │
│  Drag to reorder languages       │
└──────────────────────────────────┘
```

### Features:
- **Drag & Drop:** Reorder language preferences
- **Remove:** Delete non-primary languages
- **Add:** Search + select new language
- **Real-time:** Changes apply immediately

---

## ➕ **New Conversation Screen**
**Route:** `/new-conversation`  
**Sheet/Modal:** Bottom sheet that slides up

### UI:
```
┌──────────────────────────────┐
│  ◄ New Conversation          │
├──────────────────────────────┤
│  🔍 Search users...          │
├──────────────────────────────┤
│  Recently Active             │
│  👤 John Smith               │
│  👤 Amara Otoom              │
│                              │
│  Suggestions                 │
│  👤 Benson Okafor            │
│  👤 Zainab Ahmed             │
│                              │
│  [Search Results]            │
│  👤 Jamal Niyibizi           │
│     @jamal_niyibizi          │
│     Kigali, Rwanda ✅         │
└──────────────────────────────┘
```

### Actions:
- **Type name/email** → Filters matching users
- **Tap user** → Opens `/chat/conversationId` (creates if new)
- **Add to existing chat** → Select conversation to add user

---

## 🎨 **Visual Design System**

### Color Palette:
```
Primary:      #FF6B6B (Coral red)
Secondary:    #4ECDC4 (Teal)
Accent:       #FFE66D (Gold)
Success:      #2ECC71 (Green)
Error:        #E74C3C (Red)
Warning:      #F39C12 (Orange)
Background:   #F5F5F5 (Light gray)
Text Primary: #2C3E50 (Dark blue-gray)
Text Secondary: #7F8C8D (Medium gray)
Text Hint:    #BDC3C7 (Light gray)
```

### Typography:
```
Font Family: Poppins (primary), Inter (secondary)
Headings: 24px (700 weight)
Body: 14px (400 weight)
Captions: 12px (400 weight)
```

### Components:
```
Buttons:        Rounded (12px radius)
Text Fields:    Rounded (8px radius)
Cards:          Rounded (16px radius)
Avatars:        Circular 48px-96px
BottomNav:      Fixed, blur background
```

---

## 🔄 **Key State Flows (Riverpod Providers)**

### Authentication State:
```dart
authNotifierProvider → Current user session
  ├─ null: Not authenticated
  └─ User model: Authenticated
  
loginFlow:
  login(email, password)
    → Validates credentials
    → Stores tokens (secure storage)
    → Updates authNotifierProvider
    → Router redirects to /home
```

### Chat State:
```dart
conversationsProvider → All conversations (paginated)
  ├─ Loaded from API: /conversations/list
  ├─ Real-time WebSocket updates
  └─ Local cache with offline support

messagesProvider(conversationId) → Messages in a conversation
  ├─ Paginated: Latest 50 first
  ├─ loadMore() → Fetch older messages
  ├─ prependMessage() → Add new message
  └─ WebSocket bindings for real-time
```

### Call State:
```dart
callProvider(callId) → Active call state
  ├─ callStatus: Connecting → Connected → Ended
  ├─ callDuration: Timer incrementing
  ├─ participants: [caller_id, callee_id]
  └─ WebRTC connection details
```

---

## 🔗 **API Integration Points**

### Key Endpoints Used:
```
POST   /auth/login                 ← Login
POST   /auth/register               ← Register
POST   /auth/refresh-token          ← Refresh token
POST   /auth/firebase-login         ← Firebase auth
GET    /users/me                    ← Current user
GET    /users/contacts/list         ← Contact list
GET    /users/:userId               ← User profile
PUT    /users/me                    ← Update profile
GET    /conversations/list          ← Chat list
POST   /conversations/              ← Create chat
GET    /conversations/:id/messages  ← Messages
POST   /messages/                   ← Send message
POST   /calls/                      ← Create call
GET    /calls/:id                   ← Call details
POST   /translations/               ← Translate text
GET    /translations/:id/           ← Get translation
```

### WebSocket Events:
```
SEND:
  "join_conversation" → Subscribe to real-time updates
  "leave_conversation"
  "send_message"
  "user_typing"
  "call_initiate"

RECEIVE:
  "new_message"
  "message_edited"
  "message_deleted"
  "user_typing"
  "user_online"
  "user_offline"
  "call_incoming"
  "call_connected"
  "call_ended"
```

---

## 📱 **Responsive Design**

### Breakpoints:
```
Mobile:  < 600dp   (phones)
Tablet:  600-1200dp
Desktop: > 1200dp
```

**Adaptations:**
- Chat list: Sidebar on tablet/desktop (split view)
- Navigation: Bottom nav on mobile → Drawer on desktop
- Dialogs: Full-screen on mobile → Centered modal on desktop

---

## 🔐 **Security Features**

✅ SSL/TLS encryption in transit  
✅ Token-based auth (JWT)  
✅ Automatic token refresh  
✅ Secure local storage (platform-specific)  
✅ Permission handling (camera, microphone, file access)  
✅ Abuse prevention (rate limiting, block users)  

---

## 📊 **Performance Optimizations**

🚀 **Lazy Loading:** Conversations/Messages paginated  
🚀 **Image Caching:** Network images cached locally  
🚀 **WebSocket Connection Pooling:** Single connection reused  
🚀 **Offline Support:** Messages queued, synced when online  
🚀 **Code Splitting:** Features loaded on-demand  

---

## 🧪 **Testing Scenarios**

### Manual Test Cases:
1. ✓ Fresh install → Onboarding → Register → Login → Home
2. ✓ Open existing conversation → Send message → Receive reply
3. ✓ Start voice call → End call after 1min
4. ✓ Search contacts → Send first message → Archive
5. ✓ Edit profile → Change avatar → Update bio
6. ✓ Language settings → Change app language → Auto-translate
7. ✓ Logout → Login with Google → Navigate to home
8. ✓ Incoming call notification → Accept → Connect

---

## 🚀 **Getting Started for Developers**

### Run Frontend:
```bash
cd frontend
flutter pub get
flutter run -d chrome  # Web
flutter run -d windows # Desktop
flutter run -d android # Android
```

### Key Files:
- `lib/app/router.dart` - Navigation routes
- `lib/features/` - Feature modules
- `lib/shared/` - Shared services (API, WebSocket, Storage)
- `pubspec.yaml` - Dependencies

---

**Build Date:** Oct 2024  
**Platform:** Flutter (Web, Windows, Android, iOS)  
**State Management:** Riverpod  
**Routing:** GoRouter  
**Backend Communication:** REST APIs + WebSocket
