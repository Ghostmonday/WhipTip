# WhipTip

## Secrets & Verification

This project injects the DeepSeek API key into the generated Info.plist via build settings and xcconfig. Runtime still prefers a UserDefaults override if present.

- Configure your local secret in `Configs/Secrets.xcconfig` (git-ignored):

```
// Configs/Secrets.xcconfig
DEEPSEEK_API_KEY = sk-deepseek-xxxxxxxxxxxxxxxx
```

- The target Debug/Release are wired to use this xcconfig as Base Configuration. The generated Info.plist contains:

```
INFOPLIST_KEY_DEEPSEEK_API_KEY = $(DEEPSEEK_API_KEY)
```

- Example file (committed): `Configs/Secrets.example.xcconfig`.

### Verify the key is in the built app

You can verify that your built app contains the key using the helper script:

```
# Default: Debug, simulator, iPhone 15
./scripts/verify-deepseek-key.sh

# Or specify configuration and SDK
./scripts/verify-deepseek-key.sh --configuration Release --sdk iphonesimulator
./scripts/verify-deepseek-key.sh --sdk iphoneos --configuration Release
```

The script builds to a temporary DerivedData folder and checks `WhipTip.app/Info.plist` for `DEEPSEEK_API_KEY`. Output masks the value.

Note: At runtime, if the user has set a key via `UserDefaults` (e.g., in-app settings), that value takes precedence over the Info.plist value.

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
