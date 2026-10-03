# PRD — Wspólniak for iOS & iPadOS

> Status: approved for planning (`/carve`). Companion backend work (Push Hub, well-known
> files, install banner) is tracked in the main `wspolniak` repo. Android counterpart:
> separate PRD in `wspolniak-android`.

## Problem Statement

Wspólniak exists only as a web PWA. For family members on iPhone and iPad this means: no
real app icon on the home screen, push notifications that only work when the PWA is
installed to the home screen, browser-embedded feel instead of native fluidity, and
iOS PWA limitations around sharing and media. The family's primary devices are iPhones,
so the service deserves a first-class native application that lives permanently on the
home screen.

## Solution

A fully native iOS/iPadOS application built in SwiftUI — **one universal project**
covering iPhone and iPad with an adaptive layout. Feature parity with the web app,
**excluding** the admin panel and the documentation feature (web-only). Distributed via
**Unlisted App Store distribution**: the app is invisible in App Store search and
installable only through the owner's direct invitation link; once installed it behaves
like any normal app and updates automatically — permanently, with no maintenance by the
owner.

## User Stories

### Install & authentication

1. As a family member, I want to install the app from the owner's invitation link, so that I get the app without ever searching the App Store.
2. As a family member, I want the app to stay installed and update automatically, so that I never have to reinstall or think about updates.
3. As a family member, I want to log in with the same magic-link e-mail flow as the web, so that there are no passwords to remember.
4. As a family member, I want the magic link from my e-mail to open straight into the app (universal link), so that login completes in the app, not the browser.
5. As a family member, I want my session to persist until I log out or the admin revokes access, so that I log in once and stay logged in.
6. As a family member, I want to log out from inside the app, so that I can hand my device to someone else or leave.
7. As a family member, I want to use the same account in the app and in the web PWA at the same time, so that both stay in sync.
8. As a visitor without the app, I want the website to suggest installing it, so that I discover the native app exists.
9. As a family member, I want every message and label in the app in Polish, so that the app feels like the web version.

### Feed & posts

10. As a family member, I want to scroll an infinite feed of posts with pull-to-refresh, so that I can browse everything the family shared.
11. As a family member, I want to open a post and see its full content with markdown and @mentions rendered, so that I read it exactly like on the web.
12. As a family member, I want to add and toggle my reactions on a post, so that I can react without duplicating.
13. As a family member, I want to read and write comments on a post, so that I can take part in the conversation.
14. As a family member, I want to open a photo in a lightbox and zoom up to 10×, so that I can see the details.
15. As a family member, I want to watch YouTube videos embedded in posts, so that I don't leave the app to play them.
16. As a family member, I want polished loading states everywhere, so that the app feels as smooth as the web version.

### Uploading

17. As a family member, I want to pick multiple photos (including HEIC) from my library, so that I can share them in one go.
18. As a family member, I want oversized photos flagged before publishing (red preview with an exclamation mark) and a shrink option in the error dialog that really reduces the file, so that I can still share big photos.
19. As a family member, I want per-file upload progress and a slow-connection warning, so that I know what is happening with my upload.
20. As a family member, I want to attach a YouTube link as a video, so that family videos live on YouTube like on the web.

### Albums

21. As a family member, I want to browse albums and open an album as a gallery, so that I can view memories by occasion.
22. As a family member, I want to create and edit albums, so that I can organize the family's photos.

### Chat

23. As a family member, I want the chat to update live without refreshing, so that conversations feel instant.
24. As a family member, I want to @mention family members and see reply highlights, so that conversations stay readable.

### Calendar & library

25. As a family member, I want to browse the family calendar, so that I never miss an event.
26. As a family member, I want to browse the media library, so that I can find any photo ever shared.

### AL (AI assistance)

27. As a family member, I want to generate an AI description for a photo and use it in a post, so that describing photos is effortless.
28. As a family member, I want AI-suggested album names, so that albums get sensible titles without brainstorming.

### Push notifications

29. As a family member, I want push notifications for the same events as the web push, so that I never miss anything even with the app closed.
30. As a family member, I want notification copy in Polish, so that notifications feel native to the family.
31. As a family member, I want tapping a notification to open the relevant content (post, comment, chat message), so that I land where the action is.

### Instance configuration

32. As a family member, I want the app to respect the instance's feature on/off toggles, so that I only see features the admin enabled.

### iPad

33. As a family member on iPad, I want an adaptive layout (sidebar navigation, two-column content), so that the large screen is fully used.

### Owner / developer

34. As the owner, I want a dev app variant pointing at the dev instance, so that I can test releases without touching family data.
35. As the owner, I want the production variant to talk only to the production instance, so that the family never sees test data.

## Implementation Decisions

- **Native SwiftUI**, one universal target for iPhone + iPad; iOS 17+ baseline; adaptive
  layout (navigation split view / sidebar on iPad).
- **Identity**: bundle id `com.crystal.wspolniak`, display name „Wspólniak", app icon from
  the existing Wspólniak logo; two build configurations — dev (dev instance) and prod.
- **Distribution**: Unlisted App Store distribution — request submitted by the owner;
  installs only via the direct link; App Review applies like a regular app.
- **Architecture — three deep modules** behind which the rest of the app is built:
  - **API Client**: single gateway to the existing Hono backend (REST + WebSocket);
    hides endpoints, auth headers, retries and decoding behind one narrow interface.
  - **AuthStore**: secure (Keychain) session storage; handles the magic-link universal
    link handshake; persistent session, logout, revocation awareness.
  - **PushManager**: APNs token registration with the backend, notification presentation
    and routing (deep link into the relevant screen).
- **Backend stays the single source of truth**: no duplicated business logic; the web API
  gains device-token registration and well-known deep-link files in the main repo.
- **Auth flow**: magic link e-mail → universal link opens app → session exchanged and
  stored in Keychain; works alongside (not instead of) the web session.
- **Media**: photo picking via the system photo picker (HEIC supported); client-side
  oversize guard mirroring web rules (>19 MB flagged, shrink offered in the dialog);
  upload endpoints unchanged; videos are YouTube links rendered in an embedded web view.
- **Design**: Wspólniak web identity (colors, logo, typography) mapped to SwiftUI design
  tokens; native navigation and gesture patterns; Polish UI strings throughout.
- **Offline**: last-loaded feed cached locally and shown when offline.
- **Feature flags**: the app queries instance configuration and hides disabled features
  (calendar, library, …).
- **Deep linking**: universal links on the `wspolniak.com` domain, backed by the
  apple-app-site-association file served by the web app; when the app is absent the web
  shows its own install banner (web-side work, main repo).

## Assumptions

- The Apple Developer Program account is active before the release phase (required for
  the unlisted request and the APNs key).
- Apple approves unlisted distribution for a private family app (the app is fully
  functional, so review requirements are met).
- Family iPhones and iPads run iOS 17 or newer.
- The web API remains backward compatible; new capabilities (device tokens) are additive
  endpoints in the main repo.
- The backend Push Hub (APNs sender + token registry) lands before the chat/push phase.
- One family = one instance; no multi-tenant concerns.
- The notification event set mirrors current web push triggers (defined by the backend).

## Tradeoffs Considered

- **React Native / Expo** — rejected: stakeholder explicitly chose fully native Swift for maximum platform feel and fluidity.
- **Capacitor / PWA wrapper** — rejected: not truly native; stakeholder wants a real SwiftUI app.
- **TestFlight as primary distribution** — rejected: builds expire after 90 days and need quarterly rebuilds; the app must persist unattended.
- **Ad Hoc distribution** — rejected: provisioning expires after 12 months and requires manual reinstallation.
- **Smart App Banner** — rejected: unreliable for unlisted apps; a custom in-web install banner (main repo) is deterministic.
- **OneSignal** — rejected: adds a third party into family data flow; direct APNs keeps the self-hosted spirit.
- **Kotlin Multiplatform shared core** — rejected: stakeholder accepts two idiomatic codebases (SwiftUI + Compose) for best per-platform results.
- **UIKit** — rejected in favor of SwiftUI: modern, adaptive iPad layout with less code.

## Validation Strategy

Every story is verified by a **manual HITL scenario** on real hardware (iPhone + iPad)
against the dev instance; step-by-step scripts in Polish are produced with each
implementation slice. Automated layer:

- **Unit tests** (XCTest, run with `xcodebuild test`): API Client decoding, oversize
  guard logic, deep-link parsing, session persistence.
- **Build gates**: `xcodebuild build` green for dev and prod configurations.
- **Acceptance thresholds**: cold start < 2 s (iPhone 12-class device); feed scrolling
  stays at 60 fps; WebSocket reconnect < 3 s after drop; lightbox zoom reaches 10×
  smoothly; upload progress updates at ≤ 500 ms intervals; notification tap opens target
  content in < 2 s.
- **Done for distribution**: unlisted invitation link installs the app on a family
  device; the app keeps working beyond 90 days without any rebuild.

## Out of Scope

- Admin panel and instance settings (web only).
- Documentation feature (web only).
- Android application (separate PRD in `wspolniak-android`).
- Public App Store listing; watchOS, widgets, visionOS.
- Changes to the web PWA itself beyond items owned by the main repo (install banner,
  well-known deep-link files, Push Hub).

## Further Notes

- Delivery is phased: **M0** foundation (project, design system, API Client, auth) →
  **M1** feed + post + media viewer + comments + reactions → **M2** upload + albums →
  **M3** chat + push → **M4** calendar + library + AL + videos + offline + iPad polish →
  **M5** unlisted release. The implementation plan (phases, slices, issues) is produced
  by `/carve` from this PRD.
- iOS is built first; Android follows after iOS completion (stakeholder decision).
- Backend support items are tracked in the main `wspolniak` repository.
