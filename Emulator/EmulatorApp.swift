//
//  EmulatorApp.swift
//  Emulator
//
//  Created by Ahmed Gaafar on 27/03/2026.
//

import SwiftUI

@main
struct EmulatorApp: App {
    @StateObject private var viewModel = EmulatorViewModel()
    var body: some Scene {
        WindowGroup {
                  ContentView()
                      .environmentObject(viewModel)
                      .frame(minWidth: 800, minHeight: 600)
              }
              .windowStyle(.hiddenTitleBar)
    }
}
