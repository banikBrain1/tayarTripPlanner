//
//  ContentView.swift
//  tayarTripPlanner
//
//  Created by Shovan Banik on 22.11.26.
//

import SwiftUI

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ArrivalsBoardView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut(duration: 0.5)) {
                showSplash = false
            }
        }
    }
}

#Preview {
    ContentView()
}
