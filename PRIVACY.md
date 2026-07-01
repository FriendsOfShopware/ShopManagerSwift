# Privacy Policy — Shopware Shop Manager

_Last updated: 2026-07-01_

Shopware Shop Manager ("the app") is a client for the Shopware 6 Admin API. It
connects directly to the Shopware store(s) **you** configure. The developer does
not operate any server that sits between the app and your store, and does not
receive, collect, or store your data.

## What the app stores, and where

All data stays on your device (and, on Apple platforms, in your private iCloud
Keychain / app container):

- **Shop connection details** — the store URL, a display name, your chosen color,
  currency, language, and daily target.
- **Credentials** — your admin username and a rotating OAuth refresh token are
  stored **encrypted** (AES-GCM), with the encryption key held in the system
  **Keychain**. Your password, when you opt to keep it for automatic re-login, is
  likewise stored encrypted in the Keychain. Credentials are used only to obtain
  access tokens from your own Shopware store.
- **Cached store data** — snapshots of your dashboard, orders, products, etc., are
  cached locally so the app and its widgets work offline. This cache lives in the
  app's container (shared with the app's widget via an App Group) and can be
  removed by deleting the app or disconnecting the shop.

The app talks **only** to the Shopware instance(s) you enter. It does not send your
data to the developer or any third party.

## Push notifications (optional)

If you enable order push notifications, a device token is registered with your
Shopware store (via its notification gateway) so the store can notify you about new
orders. Delivery uses Apple Push Notification service. No notification content is
sent to the developer.

## Analytics & tracking

The app contains **no** third-party analytics or advertising SDKs and does **no**
user tracking. (The bundled Firebase component is used solely to obtain a push
token for delivery via APNs; it is not used for analytics or ads.)

## Your control

- Disconnect a shop at any time to clear its stored credentials and cache.
- Delete the app to remove all locally stored data.

## Contact

Questions: s.sayakci@gmail.com
