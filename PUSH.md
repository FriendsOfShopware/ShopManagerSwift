# Push notifications (FCM → APNs on Apple)

The Apple app **reuses the existing FCM path**. On iOS, FCM delivers through **APNs** under the
hood, so the app + Firebase project handle the client side, and the existing `push-gateway`
Cloudflare Worker keeps sending via FCM — with **one change** to the message shape.

## How it works

1. The app registers for remote notifications → gets an **APNs device token**.
2. `FirebaseMessaging` swizzles that token and mints an **FCM registration token**
   (`PushManager` → `MessagingDelegate.didReceiveRegistrationToken`).
3. The app upserts `{id: installId, token, deviceName}` into each connected shop's **`ce_fcn`**
   entity via `/_action/sync` (`AppRepository.registerPushToken` → `ShopApi.registerFcmToken`),
   exactly like the Android app.
4. On `checkout.order.placed`, the gateway reads the shop's `ce_fcn` rows and sends an FCM
   message; FCM routes it to APNs; the device shows it. Tapping it deep-links to the order
   (`NotificationDelegate` matches the shop by `shopUrl`, opens `orderId`).

## ✅ Already done in the app

- `FirebaseMessaging` (SwiftPM, firebase-ios-sdk 12.15) linked into the app target.
- `GoogleService-Info.plist` (Firebase project **shopware-shop-manager**, bundle
  **de.shyim.shopware**) bundled.
- `aps-environment` entitlement + `remote-notification` background mode.
- App Group `group.de.shyim.shopware` (shared cache) on app + widget.
- Push registration, per-shop status UI (Shop settings → **Order push**), connect-flow
  reregistration, and remote-push deep-linking.

## 🔧 What YOU still need to do

### 1. Upload the APNs key to Firebase (required)
Firebase → Project **shopware-shop-manager** → Project Settings → **Cloud Messaging** → *Apple app
configuration* → upload your **APNs Authentication Key (.p8)** (Key ID + Team ID `3NS24VW6GA`).
Without this, FCM cannot deliver to iOS.

### 2. Gateway: add an `apns` block to the FCM message (required)
The current gateway message is tuned for Android (data-only or a bare `notification`). iOS needs an
**`apns.payload.aps`** block to display an alert. Using the FCM HTTP v1 API, the message should be:

```jsonc
{
  "message": {
    "token": "<ce_fcn.token>",
    "notification": { "title": "New order", "body": "#12345 · Jane Doe" },
    "data": {
      // the app reads these on tap for deep-linking — keep them:
      "shopUrl": "https://the-shop.example.com",
      "orderId": "<order uuid>",
      "orderNumber": "12345"
    },
    "apns": {
      "headers": { "apns-priority": "10", "apns-push-type": "alert" },
      "payload": {
        "aps": {
          "alert": { "title": "New order", "body": "#12345 · Jane Doe" },
          "sound": "default"
        }
      }
    },
    "android": {
      "priority": "high",
      "notification": { "channel_id": "orders" }
    }
  }
}
```

Notes:
- Keep the **`data`** fields (`shopUrl`, `orderId`, `orderNumber`) — the Apple app deep-links from
  them. `shopUrl` must be the shop's public URL; the app matches the connected shop by normalized URL.
- The `apns` block is additive; Android delivery is unchanged.
- If the gateway currently sends **data-only** messages, add `apns.payload.aps.alert` (or
  `content-available: 1` for silent) so iOS surfaces something.
- FCM registration tokens are the same token type for both platforms — no per-platform token
  storage needed. The `ce_fcn` row is keyed by the app's stable `installId`.

### 3. iOS `BGTaskSchedulerPermittedIdentifiers` (for background refresh, unrelated to push)
The local background-refresh task id is `de.shyim.shopware.refresh`. This must be listed under
`BGTaskSchedulerPermittedIdentifiers` in the iOS Info.plist — there's no build-setting form for the
array, so add it in Xcode (target → Info) once.

## Verifying

- On a **real iOS device** (push doesn't work on the Simulator), enable *Order push* in Shop
  settings, confirm the `ce_fcn` row appears in the shop, then place a test order and check the
  gateway logs + the device notification.
