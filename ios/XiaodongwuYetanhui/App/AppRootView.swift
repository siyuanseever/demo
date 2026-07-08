import SwiftUI

struct AppRootView: View {
    var body: some View {
#if targetEnvironment(macCatalyst)
        MacPrototypeView()
#else
        ChatView()
#endif
    }
}
