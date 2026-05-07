// Reference snippet — not compiled by the package.
//
// Drop this into your own app target. Replace `UserSession` with whatever
// your app uses for the logged-in user.

import SwiftUI
import Hoist

@main
struct SampleApp: App {
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady { RootView() } else { LoadingView() }
            }
            .task { await configureHoist() }
        }
    }

    private func configureHoist() async {
        do {
            try await Hoist.configure(
                source: .bundled(filename: "flags.json"),
                context: UserContext(
                    userID: UserSession.current.id,
                    attributes: [
                        "country":     .string(Locale.current.region?.identifier ?? "??"),
                        "plan":        .string(UserSession.current.plan),
                        "isInternal":  .bool(UserSession.current.isStaff),
                        "appBuild":    .int(Bundle.main.appBuild),
                    ]
                )
            )
        } catch {
            // Hoist returns the per-call default for every read on failure;
            // the app keeps working with safe defaults.
            assertionFailure("Hoist configure failed: \(error)")
        }
        isReady = true
    }
}

struct RootView: View {
    @State private var showFlags = false

    var body: some View {
        NavigationStack {
            CheckoutView()
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Flags") { showFlags = true }
                    }
                }
                .sheet(isPresented: $showFlags) { HoistDebugView() }
                #endif
        }
    }
}

struct CheckoutView: View {
    @FeatureFlag("new_checkout")              var useNewCheckout
    @FeatureFlag("max_upload_mb", default: 10) var uploadLimitMB
    @FeatureFlag("home_layout", default: "grid") var layout

    var body: some View {
        VStack(spacing: 16) {
            if useNewCheckout {
                Text("New checkout (limit \(uploadLimitMB) MB)")
            } else {
                Text("Legacy checkout")
            }
            Text("Layout variant: \(layout)")
        }
        .padding()
    }
}

// MARK: - Stand-ins so this snippet reads cleanly in isolation.

struct LoadingView: View {
    var body: some View { ProgressView() }
}

enum UserSession {
    struct User { var id: String; var plan: String; var isStaff: Bool }
    static var current = User(id: "anon", plan: "free", isStaff: false)
}

extension Bundle {
    var appBuild: Int {
        Int(infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }
}
