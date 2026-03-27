import SwiftUI

struct ContentView: View {
    var body: some View {
        // Ersetze 'https://deine-pwa-url.com' durch deine echte Adresse
        WebView(url: URL(string: "https://playday.christianriehl1.workers.dev")!)
            .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
