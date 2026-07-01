import Foundation
import ShopwareAdminAPI

/// This device's registration in a shop's `ce_fcn` entity. `Present` carries the stored deviceName
/// (may be blank); `Absent` means no row for this install.
enum FcmRegistration: Equatable, Sendable {
    case present(deviceName: String?)
    case absent
}

extension ShopApi {
    /// Register (upsert) this device's FCM token into the shop's `ce_fcn` entity. The external
    /// Shopware app server reads these rows and fans order pushes out. `installId` is a stable
    /// per-installation id used as the row id. Goes through the `/_action/sync` upsert (POST is
    /// insert-only, so a repeat call on the same id would fail). Requires the FroshMobilePush app
    /// (the `ce_fcn` entity + ACL); a missing entity surfaces as `ApiError.notFound`.
    func registerFcmToken(installId: String, token: String, deviceName: String) async throws {
        try await repository("ce-fcn").upsert(.object([
            "id": .string(installId),
            "token": .string(token),
            "deviceName": .string(deviceName),
        ]))
    }

    /// Look up this device's `ce_fcn` row. `.present` when it exists, `.absent` when it doesn't.
    /// Throws `ApiError.notFound` when the entity itself is missing (FroshMobilePush not installed).
    func fetchFcmRegistration(installId: String) async throws -> FcmRegistration {
        if let row = try await repository("ce-fcn").get(installId) {
            return .present(deviceName: row.string("deviceName"))
        }
        return .absent
    }

    /// Remove this device's token from the shop (e.g. on disconnect). Ignores a 404.
    func unregisterFcmToken(installId: String) async {
        _ = try? await repository("ce-fcn").delete(installId)
    }
}
