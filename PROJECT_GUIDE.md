# StreamFlix IPTV — Complete Project & Architecture Guide

This folder (`/Users/hamodyz/Desktop/Iptv gemni`) contains **two completely independent IPTV apps** modeled after Netflix for Xtream Codes API (`host`, `username`, `password`). Keep them strictly separated when editing.

---

## 1. Apple App (`StreamFlixIPTV` — Mac, iPhone, iPad, Apple TV)
- **Xcode Project**: `StreamFlixXcode /StreamFlixIPTV/StreamFlixIPTV.xcodeproj`
- **Local Swift Package**: `StreamFlixIPTV/StreamFlixCore/`
- **Stable Backup**: `StreamFlix_Stable_v1.zip`
- **Tech Stack**: Native **Swift / SwiftUI** + **`VLCKitSPM` (v3.6.0)** (`https://github.com/tylerjonesio/vlckit-spm.git`) for single-connection playback across macOS, iOS, iPadOS, and tvOS.
- **Key Features**:
  - Xtream Codes login with multi-profile save/delete and `Info.plist` ATS (`NSAllowsArbitraryLoads = true`) for `http://` IPTV servers.
  - Home screen with Hero Banner, Continue Watching (exact-second save/resume), Favorite Series ("My List"), and Trending Movies/Series.
  - Separate Movies, Series, and Live TV tabs with top-left Category Dropdowns preserving server order + 150-item pagination.
  - Arabic/English normalized search inside each tab.
  - Sleep Guard ("Are you still watching?" after 2 consecutive episodes).
  - Player controls: 1-tap Play/Pause with center `PAUSED` badge, double-tap `-10s`/`+10s` + horizontal swipe on iOS/iPadOS, `HD` Quality/Tracks menu, Live TV `CH+`/`CH-` zapping + slide-out channel drawer, macOS Full Screen toggle.
- **How to Build & Run**: Open `StreamFlixXcode /StreamFlixIPTV/StreamFlixIPTV.xcodeproj` in **Xcode**, select target (Mac / iPhone / iPad), and press **Run (`Cmd + R`)**.

---

## 2. Samsung Smart TV App (`StreamFlixSamsungTV` — Tizen Web App)
- **Project Folder**: `StreamFlixSamsungTV/`
  - `config.xml`: Tizen TV manifest (`tv-samsung` profile, `internet`, `tv.inputdevice`, `avplay` privileges, `<access origin="*" subdomains="true"/>`).
  - `index.html`: 1080p TV UI (Login, Top Nav + Search + Exit, 2-Pane Catalogs, Dish Receiver Live TV Guide, Series Modal, Category Modal, Fullscreen Player, Slide-out Channel Drawer, Zap Banner, Sleep Modal).
  - `css/style.css`: Netflix dark theme (`#000`, `#e50914`), 1920x1080 layout, high-contrast D-Pad focus rings.
  - `js/app.js`: Xtream Codes client, auto-login from saved profile (`localStorage`), Arabic/English normalized search, **custom D-Pad spatial navigation engine** + `readOnly` TV IME keyboard handling, **`webapis.avplay`** playback (`.ts` with `.m3u8` fallback) + HTML5 fallback, instant Left/Right `-10s`/`+10s` VOD seek, Dish Receiver Live TV mode (`CH+`/`CH-` zapping + `OK`/Left slide-out channel drawer).
  - `icon.png`: Custom `512x512` PNG app icon.
- **How to Build & Run**: Open **Tizen Studio** -> import `StreamFlixSamsungTV` -> connect Samsung TV via **Device Manager** (TV in Developer Mode: `Apps > App Settings > 12345`) -> ensure a **Samsung Certificate** is active in Certificate Manager -> right-click project -> **Run As > Tizen Web Application**.

---

## Notes for Any AI Assistant (Claude, ChatGPT, Cursor, etc.) or Developer
1. **Always ask or verify** whether the requested change is for **Apple (`StreamFlixXcode `)** or **Samsung TV (`StreamFlixSamsungTV`)** before editing.
2. **Do not replace `VLCKitSPM`** in the Apple app or remove the **`D-Pad` spatial navigation / `readOnly` IME input handling** in `StreamFlixSamsungTV/js/app.js`—both solve critical platform constraints.
