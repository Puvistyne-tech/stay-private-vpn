import SwiftUI

@main
struct StayVPNApp: App {
    @StateObject private var model = VPNModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // The label is created at launch, so polling starts before the menu is first opened.
            Image(nsImage: MenuBarIcon.image(iconStyle))
                .task { model.start() }
                .accessibilityLabel("Stay Private")
        }
        .menuBarExtraStyle(.window)
    }

    private var iconStyle: MenuBarIcon.Style {
        switch model.phase {
        case .connected: return .connected
        case .waiting, .connecting, .disconnecting: return .busy
        case .disconnected: return .disconnected
        }
    }
}
