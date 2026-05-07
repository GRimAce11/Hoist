// Reference snippet — not compiled by the package.
//
// Hoist is SwiftUI-native, but the core API is plain Swift, so it works fine
// from UIKit. The debug overlay is a SwiftUI View — wrap it in a
// `UIHostingController` to present it from a `UIViewController`.

#if canImport(UIKit)
import UIKit
import SwiftUI
import Hoist

final class CheckoutViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if Hoist.bool("new_checkout") {
            installNewCheckoutFlow()
        } else {
            installLegacyFlow()
        }

        let limit = Hoist.int("max_upload_mb", default: 10)
        configureUploads(maxMB: limit)

        #if DEBUG
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Flags",
            style: .plain,
            target: self,
            action: #selector(presentDebugOverlay)
        )
        #endif
    }

    @objc private func presentDebugOverlay() {
        let host = UIHostingController(rootView: HoistDebugView())
        present(host, animated: true)
    }

    // Stand-in helpers so the snippet reads cleanly.
    private func installNewCheckoutFlow() {}
    private func installLegacyFlow() {}
    private func configureUploads(maxMB: Int) {}
}
#endif
