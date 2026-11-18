import AppKit
import SwiftUI

/// In-app reminder of how to get a Proton VPN config file into the app.
/// Labels in bold are the ones Proton's own instructions use.
struct GuideView: View {
    let onImport: () -> Void
    let onClose: () -> Void

    static let protonURL = URL(string: "https://account.protonvpn.com/downloads")!

    private let steps: [LocalizedStringKey] = [
        "Sign in at **account.protonvpn.com** with your free Proton account.",
        "Go to **Downloads**, then **WireGuard configuration**.",
        "Type a name for the config. For **Platform**, pick macOS.",
        "Leave the **VPN options** as they are. On the Free plan only VPN Accelerator is available.",
        "Under **Server**, pick a free server in the country you want, then click **Create**.",
        "Wait a few seconds, then click **Download** to save the **.conf** file.",
        "Rename the file to something short, such as **canada.conf**. The profile takes its name from the first 12 characters.",
        "Back here, click **Import config…** and choose the file. Then click Connect.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Get a Proton VPN config").font(.headline)
                Spacer()
                Button("Done", action: onClose)
            }
            Text("Each config file is one server in one country. Repeat these steps for every country you want.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(step)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("The file contains your private key. Once it is imported you can delete the download; the app keeps its own protected copy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open Proton site") { NSWorkspace.shared.open(Self.protonURL) }
                    .buttonStyle(.borderedProminent)
                Button("Import config…", action: onImport)
            }
        }
    }
}
