# StreamFlix IPTV (Apple & Samsung Smart TV)

A Netflix-style IPTV player built for **Xtream Codes API** (`host`, `username`, `password`), featuring **two completely independent apps** in one organized repository:

1. **Apple App (`StreamFlixXcode /` + `StreamFlixIPTV/`)** — Native SwiftUI app for **iPhone, iPad, Mac, and Apple TV** powered by `VLCKitSPM`.
2. **Samsung Smart TV App (`StreamFlixSamsungTV/`)** — Tizen Web App for **Samsung Smart TVs** with full D-Pad spatial navigation and `webapis.avplay`.

> **Note:** No personal IPTV credentials, server URLs, or private database keys are included in this repository. Enter your own Xtream Codes account inside the app.

---

## Repository Structure

```text
├── StreamFlixXcode /          # Xcode project (iOS, iPadOS, macOS, tvOS)
├── StreamFlixIPTV/            # Shared Swift package (StreamFlixCore: API, Models, Sync, Progress)
├── StreamFlixSamsungTV/       # Samsung Smart TV Tizen Web App
└── PROJECT_GUIDE.md           # Detailed architecture & developer notes
```

> Keep `StreamFlixXcode /` and `StreamFlixIPTV/` in the same parent folder so Xcode can resolve the local `StreamFlixCore` package.

---

## Features

### Apple App (`iOS` / `iPadOS` / `macOS` / `tvOS`)
- **Home Dashboard**: Resume Watching card, live library stats (`Movies`, `Series`, `Live TV`, `My List`), `Pick for Me` shuffle, deduplicated `Continue Watching`, and Trending rows.
- **Universal Search & Filters**: Fast Arabic & English normalized search across Movies, Series, and Live TV, plus server-ordered category dropdowns.
- **Dish-Style Live TV**: Split-view channel guide + `16:9` live preview on iPad/Mac, `CH+` / `CH-` zapping, and slide-out channel drawer.
- **Smart Video Player (`VLCKitSPM`)**:
  - Exact-second **Resume Watching** & **Next Episode** auto-countdown.
  - **Skip Intro (`+85s`)** button during the first 3 minutes of episodes.
  - Slide-out **Episodes** drawer with season selector, double-tap `-10s` / `+10s` seek, `HD` stream switcher, and **Sleep Guard**.
  - Responsive portrait & landscape controls on iPhone.
- **Multi-Account & Live Refresh**: Save/switch multiple Xtream accounts, pull-to-refresh on Home, or tap **Refresh Library** in Account.
- **Free Cloud Sync (iPad / iPhone / Mac)**: Optional Firebase Realtime Database REST sync in **Account > Cloud Sync** to sync `Continue Watching` and `My List` across devices without a paid Apple Developer account.

### Samsung Smart TV App (`Tizen`)
- **1080p TV Interface**: Netflix-inspired dark UI with high-contrast D-Pad focus rings.
- **TV Remote & Keyboard Handling**: Custom D-Pad spatial navigation + `readOnly` input mode so the on-screen keyboard only opens on `OK`.
- **Dish Receiver Live TV**: 3-zone channel guide, `CH+` / `CH-` zapping, and fullscreen slide-out channel drawer.
- **Playback**: `webapis.avplay` (`.ts` with `.m3u8` fallback) and instant Left/Right `-10s` / `+10s` VOD seek.

---

## Quick Start

### 1. Apple App (Xcode)
1. Open `StreamFlixXcode /StreamFlixIPTV/StreamFlixIPTV.xcodeproj` in **Xcode** (requires `StreamFlixIPTV/` next to it).
2. Wait for Swift Package Manager to resolve **`VLCKitSPM` (`3.6.0`)**.
3. Select your target (**Mac**, **iPhone**, or **iPad**) under **Signing & Capabilities** with your Apple ID and press **Run (`Cmd + R`)**.
4. *(Optional)* To sync `Continue Watching` & `My List` across your Apple devices, create a free **Firebase Realtime Database** and paste its URL into **Account > Cloud Sync**.

### 2. Samsung Smart TV App (Tizen Studio)
1. Open **Tizen Studio** and import the `StreamFlixSamsungTV/` folder.
2. Enable **Developer Mode** on your Samsung TV (`Apps > App Settings > 12345`) and connect it in **Device Manager**.
3. Configure a **Samsung Certificate** in Certificate Manager, then right-click the project and select **Run As > Tizen Web Application**.

---

## Contributing

Contributions, bug fixes, and feature improvements are welcome! Please keep the **Apple** (`StreamFlixXcode /` + `StreamFlixIPTV/`) and **Samsung TV** (`StreamFlixSamsungTV/`) codebases cleanly separated in any pull requests.
