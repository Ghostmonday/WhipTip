# WhipTip

Monolithic SwiftUI iOS app with **DeepSeek AI integration**.  
A production-grade **tip splitting engine** with financial accuracy and AI-assisted onboarding.

## Features
- ✅ Offline-first calculation engine (cents-based for accuracy)
- ✅ DeepSeek-powered onboarding assistant
- ✅ Financial-grade rounding + penny distribution
- ✅ Export to CSV / text
- ✅ Subscription manager (StoreKit 2 ready)

## Setup
1. Clone repo:
   ```bash
   git clone https://github.com/<YOUR_USERNAME>/WhipTip.git
   cd WhipTip
   ```
2. Open in Xcode:
   ```bash
   open WhipTip.xcodeproj
   ```
3. Add your DeepSeek API key to **Info.plist**:
   ```xml
   <key>DEEPSEEK_API_KEY</key>
   <string>[YOUR_KEY]</string>
   ```

## Development
- Architecture: Single-file monolith (`WhipTipApp.swift`).
- Dependency: None beyond Swift + iOS 16 SDK.
- License: MIT (optional).

## Smoke Test
After setting your API key, run in simulator and test onboarding flow:
- Default model: `deepseek-chat`
- Reasoning model: `deepseek-reasoner`

## Streaming Notes
The `APIService` supports SSE streaming with `streaming: true` to accumulate tokens.

## Security
`DEEPSEEK_API_KEY` is stored in `Info.plist` for development; consider moving to an encrypted configuration or server-mediated token exchange before production release.

---

_Replace `<YOUR_USERNAME>` above with your GitHub username._
