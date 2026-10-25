# 🎉 Autom8ed Vault - Release Notes

## VERSION 1.0.1 - WINDOWS INSTALLER REPAIR
**Date**: October 25, 2026

- Native browser setup with explicit confirmation before enabling Developer mode.
- Installation verifies the extension name, version, source directory and enabled state.
- Running browsers and DevTools no longer trigger a manual-only fallback.
- Setup waits for its helper, not for the browser to exit.
- The setup ZIP extracts into one `autom8ed-mfa` directory.
- The original `Autom8edVault\1.0.0` install directory remains stable across updates to preserve path-derived extension IDs.
- Chrome and Brave have isolated live coverage; Edge remains an unverified Chromium target.

## 🌟 VERSION 1.0.0 - STABLE RELEASE
**Date**: May 6, 2026  
**Status**: ✅ PRODUCTION READY  

This marks the first official stable release of Autom8ed Vault. All previous iterations and beta versions have been consolidated into this milestone.

### 📦 Release Highlights
- **Complete Rebranding & Refactor**: Fully transitioned to the **Autom8ed Vault v1.0** standard.
- **Auto-Injection Engine**: Flawless, retry-capable auto-injection for OTPs with smart field detection.
- **Vault Management**: Comprehensive UI for adding, editing, exporting, and importing TOTP profiles securely.
- **Enhanced Security**: 100% offline local storage with complete isolation.

---

## 🔄 VERSION 0.4.6 - FINAL BETA (Previously "v4.6")
**Date**: February 20, 2026  

*Note: This was the final major beta version before 1.0.0, originally labeled "v4.6 Opus Edition".*

### 🎯 Key Improvements Implemented
1. **Auto-extract label from otpauth:// URIs**
   - Parses `otpauth://totp/Twitter:@user` → extracts `@user`
   - Falls back to issuer parameter if no colon separator
   - Auto-fills label field on paste

2. **Base32 secret validation**
   - Validates characters (A-Z, 2-7 only)
   - Prevents invalid secrets from being saved
   - Shows specific error: "Invalid Base32 secret. Check for invalid characters"

3. **Auto-add to profileMap when saving new entry**
   - Checks if profileMap has room (<4 slots)
   - Auto-adds new profiles to popup favorites
   - Seeds profileMap if empty

4. **Import validation**
   - Validates vault structure exists
   - Checks each entry for required fields
   - Validates Base32 secrets before importing
   - Shows count of valid vs invalid entries
   - Skips bad entries with console warnings

5. **Export with timestamp**
   - Filename format: `autom8ed_totp_vault_2026-02-20T15-30-45.json`
   - ISO 8601 timestamp with sanitized colons
   - Easy to sort chronologically

6. **Duplicate detection on migration import**
   - Prompts "Profile X already exists. Overwrite?"
   - Tracks imported, overwritten, skipped counts
   - Shows summary: "Imported 5 entries, overwritten 2, skipped 1"

7. **Edit mode visual indicator**
   - Orange banner shows "Editing: ProfileName"
   - Highlights edited row in list with orange border
   - Clears when form is cleared or new profile saved

8. **Better error messages**
   - "Invalid Base32 secret. Check for invalid characters" vs "Invalid secret"
   - "Missing 'vault' object" vs "Invalid file"
   - "Migration parse error: {specific error}" vs "Invalid URI"
   - All errors now specify what went wrong

9. **Use issuer parameter from URIs**
   - Extracts from path first: `Twitter:@user` → `@user`
   - Falls back to `?issuer=Twitter` if no path label
   - Used in auto-fill and migration imports

### 🎁 Bonus Features
- **Live countdown timers** - Shows seconds remaining for current TOTP period.
- **Clipboard auto-copy** - Codes copy to clipboard when clicked.
- **Auto-paste detection** - Manager auto-fills form when pasting `otpauth://` URI.
- **Clear form button** - Quick reset of manager form.
- **Dark theme** - Modern gradient dark UI throughout.
- **Emoji indicators** - 🔄 badge for auto-submit profiles.

---

## 🛠️ Integrations Completed in 0.4.6

### From Working Base (0.3.0)
- TOTP generation algorithm (RFC 6238 compliant)
- Auto-injection logic with retry mechanism
- Field detection selectors (15+ patterns)
- Auto-submit functionality

### From Full Manager (0.3.1)
- Vault storage schema
- ProfileMap management
- Import/export functionality
- `otpauth://` URI parsing
- Google Auth migration decoder
- Base32 encoding/decoding

---

## 💝 Dedication & Credits

Built with attention to detail, implementing every requested feature with proper error handling, validation, and user experience enhancements.

**Created by**: Autom8ed  
**Enhanced by**: AntiGravity  
**Status**: ✅ PRODUCTION READY  

**Happy Authenticating!** 🔐✨
