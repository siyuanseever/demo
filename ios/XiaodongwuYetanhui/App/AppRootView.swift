import SwiftUI

struct AppRootView: View {
    var body: some View {
#if targetEnvironment(macCatalyst)
        MacPrototypeView()
            .preferredColorScheme(.light)
#else
        ChatView()
            .preferredColorScheme(.light)
#endif
    }
}
