import Foundation
import ShopwareAdminAPI

/// This device's registration in a shop's `ce_fcn` entity. `Present` carries the stored deviceName
/// (may be blank); `Absent` means no row for this install.
enum PushRegistration: Equatable, Sendable {
    case present(deviceName: String?)
    case absent
}

extension ShopApi {
    /// Register (upsert) this device's push token into the shop's `ce_fcn` entity. The push gateway
    /// reads these rows and fans order pushes out — `platform` (`apns` on Apple) tells it whether to
    /// send via APNs or FCM. `installId` is a stable per-installation id used as the row id. Goes
    /// through the `/_action/sync` upsert (POST is insert-only, so a repeat on the same id would
    /// fail). Requires the FroshMobilePush app (the `ce_fcn` entity + ACL); a missing entity surfaces
    /// as `ApiError.notFound`.
    func registerPushToken(installId: String, token: String, platform: String, deviceName: String) async throws {
        try await repository("ce-fcn").upsert(.object([
            "id": .string(installId),
            "token": .string(token),
            "platform": .string(platform),
            "deviceName": .string(deviceName),
        ]))
    }

    /// Look up this device's `ce_fcn` row. `.present` when it exists, `.absent` when it doesn't.
    /// Throws `ApiError.notFound` when the entity itself is missing (FroshMobilePush not installed).
    func fetchPushRegistration(installId: String) async throws -> PushRegistration {
        if let row = try await repository("ce-fcn").get(installId) {
            return .present(deviceName: row.string("deviceName"))
        }
        return .absent
    }

    /// Remove this device's token from the shop (e.g. on disconnect). Ignores a 404.
    func unregisterPushToken(installId: String) async {
        _ = try? await repository("ce-fcn").delete(installId)
    }
}
