//
//  playdayApp.swift
//  playday
//
//  Created by Christian Riehl on 23.03.26.
//

import SwiftUI

@main
struct playdayApp: App {
    @State private var incomingURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(incomingURL: incomingURL)
                .onOpenURL { url in
                    incomingURL = url
                }
        }
    }
}
