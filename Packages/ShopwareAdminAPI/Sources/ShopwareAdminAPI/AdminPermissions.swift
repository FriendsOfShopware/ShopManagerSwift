import Foundation

public struct AdminPermissions: Equatable, Sendable {
    public let isAdmin: Bool
    public let privileges: Set<String>
    public let userId: String?

    public init(isAdmin: Bool = false, privileges: Set<String> = [], userId: String? = nil) {
        self.isAdmin = isAdmin
        self.privileges = privileges
        self.userId = userId
    }

    public init(user: SwEntity) {
        userId = user.id
        isAdmin = user.boolean("admin") ?? false
        privileges = Set(user.entities("aclRoles").flatMap {
            $0.json["privileges"]?.arrayValue?.compactMap(\.stringValue) ?? []
        })
    }

    public func allows(_ privilege: String) -> Bool { isAdmin || privileges.contains(privilege) }
}
