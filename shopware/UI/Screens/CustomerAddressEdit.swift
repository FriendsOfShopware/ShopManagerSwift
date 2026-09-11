import Foundation

struct CustomerAddressEdit: Identifiable {
    let id = UUID()
    let address: EditableAddress
    let isNew: Bool
}
