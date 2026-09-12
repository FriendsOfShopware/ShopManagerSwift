import Foundation

struct CustomerOption: Equatable, Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var isEnabled = true
}
