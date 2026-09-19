# 🚀 Quick Start Guide - Autom8ed Vault v1.0

## 1. Install

**Windows (from a GitHub release):** download `autom8ed-vault-*-setup.zip`, extract, double-click `Install.cmd`. Pick Chrome / Edge / Brave. If the browser is already open, close it yourself and open it again — the installer will not kill it.

**Chrome Web Store upload:** use `autom8ed-vault-*-chrome-web-store.zip` from the same release (or run `.\Pack-Autom8edVault.ps1`).

**Load unpacked:** `chrome://extensions/` → Developer mode → Load unpacked → this folder.

Pin the vault icon from the puzzle piece.

---

## 2. Test with Your First Account

1. Click the extension icon (🔐) in your toolbar.
2. Click the **"⚙️ Manage Profiles"** link at the bottom.
3. In the manager page, paste the following into the **Secret** field:
   ```text
   otpauth://totp/Twitter:@2happyCSGO?secret=ABCDEFGHJKLMNOPQRSTUVWZ&issuer=Twitter
   ```
4. Notice how the **Label auto-fills** to `@2happyCSGO`.
5. Click **"💾 Save Profile"**.
6. The profile will appear in the list below.
7. Close the manager and click the extension icon again.
8. You should now see the **"@2happyCSGO"** button in your popup!

---

## 3. Generate Your First Code

1. Click the **"@2happyCSGO"** button in the popup.
2. The code is instantly **copied to your clipboard**.
3. A status message will show: `✅ XXXXXX copied to clipboard!`
4. Paste it wherever you need it.

---

## 4. Next Steps

### Configure Auto-Injection
1. Open the manager (`⚙️ Manage Profiles`).
2. Click **"Edit"** on a profile.
3. Add a **CSS Selector**: e.g., `#tokencode` (or whatever the site uses).
4. Enable **"Auto-submit form after injection"** if desired.
5. Click **"💾 Save Profile"**.
6. Now, when you navigate to the login page and click the profile button, it auto-fills the field!

### Import Bulk Accounts
1. Export from Google Authenticator (Transfer accounts → QR code).
2. Scan the QR code with your phone to get the `otpauth-migration://` URI.
3. Paste the URI directly into the manager secret field.
4. All accounts import at once!

### Export Secure Backup
1. Click **"📤 Export Vault"** in the manager.
2. Save the generated JSON file somewhere safe.
3. You can restore your profiles anytime using **"📥 Import Vault"**.

---

## 🔧 Troubleshooting

### Extension not showing in toolbar
- **Fix**: Click the puzzle piece icon in Chrome → Pin "Autom8ed Vault".

### "No profiles configured" message
- **Fix**: Click "⚙️ Manage Profiles" and add some!

### Injection not working
- **Fix**: Add a custom CSS selector in the manager for that specific website. If all else fails, use the clipboard copy feature (manual paste).

---

**Enjoy your new secure TOTP manager! 🔐**

*For more technical details, check the `README.md` file.*
