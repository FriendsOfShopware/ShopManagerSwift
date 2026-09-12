import SwiftUI
import ShopwareAdminAPI

struct ReviewDate: View {
    let date: Date?
    var body: some View {
        if let date { Text(date, format: .dateTime.day().month().year()) }
        else { Text("—") }
    }
}
