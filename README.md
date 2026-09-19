# 🔐 Autom8ed Vault v1.0

**Professional Chrome extension for offline TOTP (Time-based One-Time Password) management with intelligent auto-injection capabilities.**

---

## ✨ Features

### Manager Capabilities
- **Auto-extract labels** - Parses `otpauth://` URIs and extracts account labels automatically.
- **Base32 secret validation** - Validates secrets before saving to prevent runtime errors.
- **Smart profile management** - Automatically adds new profiles to the popup for quick access.
- **Import validation** - Detailed error messages for invalid entries; skips bad secrets.
- **Export with timestamp** - Securely back up your vault to timestamped JSON files.
- **Duplicate detection** - Warns when imports would overwrite existing profiles.
- **Visual feedback** - Clear edit mode indicators and specific error messages.
- **Issuer support** - Extracts and utilizes issuer parameters from URIs.

### Popup Enhancements
- **Live countdown timers** - Shows real-time seconds remaining for the current TOTP period.
- **Auto-clipboard copy** - Copies codes to clipboard instantly upon click.
- **Visual status feedback** - Success and error messages displayed within the popup.
- **Auto-submit indicator** - Shows a 🔄 badge for profiles with auto-submit enabled.

### Injection Engine
- **Smart field detection** - Evaluates common MFA input selectors automatically.
- **Retry logic** - Defeats field resets with automatic re-injection.
- **Auto-submit** - Configurable per-profile auto-submit after injection.
- **Custom selectors** - Support for per-profile CSS selectors for site-specific targeting.

---

## 📁 File Structure

```text
Autom8ed-Vault/
├── manifest.json           # Extension manifest
├── background.js           # Background service worker
├── popup.html              # Popup interface
├── popup.js                # TOTP generation & injection logic
├── manager.html            # Full vault management UI
├── manager.js              # Enhanced vault manager
├── injector.js             # Content script for auto-injection
├── crypto-helper.js        # Cryptographic operations
├── styles.css              # Shared stylesheets
├── README.md               # Documentation
├── PRIVACY_POLICY.md       # Privacy policy
├── QUICKSTART.md           # Quick start guide
├── VERSION_NOTES.md        # Release notes
├── Install-Icons.ps1       # Icon installation helper script
├── icon16.png              # 16x16 Extension icon
├── icon32.png              # 32x32 Extension icon
├── icon48.png              # 48x48 Extension icon
├── icon64.png              # 64x64 Extension icon
└── icon128.png             # 128x128 Extension icon
```

---

## 🚀 Installation

Chrome will not 1-click-install a `.crx` downloaded from GitHub (it only allows
that from the Chrome Web Store). The GitHub path is a setup zip: extract and
double-click `Install.cmd`. Pick Chrome / Edge / Brave. The installer does
**not** kill a running browser — if one is open, close it yourself and start it
again so the vault appears.

### Option 1: GitHub release (1-click on Windows)

1. Open the latest release: https://github.com/usrname1git/Chrome-MFA-extension/releases/latest
2. Download `autom8ed-vault-*-setup.zip`
3. Extract it and double-click **Install.cmd**
4. Choose browsers, or run:
   ```powershell
   .\Install-Autom8edVault.ps1 -Browser Chrome,Edge
   ```
5. From a machine with no zip yet:
   ```powershell
   irm https://raw.githubusercontent.com/usrname1git/Chrome-MFA-extension/main/Install-Autom8edVault.ps1 | iex
   ```
   That script downloads the latest setup zip when it has no local `manifest.json`.

### Option 2: Chrome Web Store upload

1. Run `.\Pack-Autom8edVault.ps1` (or use the `*-chrome-web-store.zip` on the GitHub release)
2. Developer Dashboard → **Upload new item** → that zip
3. Privacy policy URL: this repo's `PRIVACY_POLICY.md` on GitHub
4. Do not upload the setup zip or `.crx` to the Store — only `*-chrome-web-store.zip`

### Option 3: Load unpacked (development)

1. Open `chrome://extensions/`
2. Enable **Developer mode**
3. **Load unpacked** → this folder

---

## 📖 Usage Guide

### Adding Your First Profile
1. **Click extension icon** → **"⚙️ Manage Profiles"**
2. **Paste your secret** (supports 3 formats):
   - **Base32 secret**: `ABCDEFGHJKLMNOPQRSTUVWZ`
   - **otpauth:// URI**: `otpauth://totp/Twitter:@user?secret=ABCDEF...`
   - **Google Auth migration**: `otpauth-migration://offline?data=...`
3. **Label auto-fills** from the URI (or enter it manually)
4. **Adjust settings** (digits, period, algorithm) if needed
5. **(Optional)** Add a custom CSS selector for auto-injection (e.g., `#tokencode`)
6. **(Optional)** Enable auto-submit to automatically log in after injection
7. **Click "💾 Save Profile"**

### Using TOTP Codes
#### Method 1: Auto-Injection
1. Navigate to your MFA login page
2. Click the profile in the extension popup
3. The code auto-fills and optionally submits
4. *Note: Works automatically if the selector matches.*

#### Method 2: Manual Copy
1. Click the extension icon in your toolbar
2. Click the desired profile button
3. The code is **copied to your clipboard**
4. Paste it manually into the MFA field

### Importing / Exporting
- **Import from Google Authenticator**: Export via QR code, scan to get the `otpauth-migration://` URI, and paste into the manager. All accounts will import automatically.
- **Import from JSON**: Click "📥 Import Vault" in the manager and select your backup file.
- **Export Vault**: Click "📤 Export Vault" to download a secure JSON backup.

---

## 🔧 Technical Configuration

### Storage Schema
**Chrome Local Storage:**
```json
{
  "vault": {
    "Twitter": {
      "secret": "ABCDEFGHJKLMNOPQRSTUVWZ",
      "digits": 6,
      "period": 30,
      "algo": "SHA1",
      "label": "@user",
      "selector": "#tokencode",
      "autoSubmit": false
    }
  },
  "profileMap": ["Twitter", "GitHub"]
}
```

### Supported Standards
- **Algorithms**: SHA1 (default), SHA256, SHA512
- **Formats**: 6-digit (standard), 7-digit, 8-digit codes
- **Periods**: 15 to 60-second intervals (30s default)
- **Cryptography**: RFC 6238 compliant using the Web Crypto API (SubtleCrypto)

### Security Considerations
- **Local storage only** - Secrets never leave your browser
- **No cloud sync** - Manual export/import required for backups
- **Content script isolation** - Runs in a sandboxed context
- **No network requests** - 100% offline operation after installation

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| **"No MFA input field found"** | Add a custom CSS selector in the manager. Right-click the input field → Inspect → Copy selector. |
| **"Invalid Base32 secret"** | Ensure the secret only contains characters A-Z and 2-7. |
| **Auto-submit not working** | Site may have anti-automation protections. Disable auto-submit and click manually. |
| **Code not injecting** | Click the popup button to copy the code, then paste it manually. Check DevTools (F12) console for errors. |

---

## 📝 Version History

### v1.0.0 - May 6, 2026
- ✨ Initial stable release.
- 🚀 Features full auto-injection, smart vault management, and an optimized user experience.
- *(Note: All previous beta versions and iterations are now considered 0.X.X and have been consolidated into this stable 1.0 release.)*

---

## 🙏 Credits

**Created by**: Autom8ed  
**Enhanced by**: AntiGravity  
**Version**: 1.0  
**Date**: May 6, 2026  

---

## 📄 License

Personal use project. No license restrictions.
