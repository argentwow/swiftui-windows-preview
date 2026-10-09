import SwiftUI

@main
struct CounterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0
    @State private var liked = false

    var body: some View {
        VStack(spacing: 16) {
            Text("SwiftUI on Windows")
                .font(.largeTitle)
                .bold()
            Text("Count: \(count)")
                .font(.title)
                .foregroundColor(count >= 0 ? .blue : .red)
            HStack(spacing: 12) {
                Button("−") { count -= 1 }
                Button("Reset") { count = 0 }
                Button("+") { count += 1 }
            }
            Button(liked ? "Liked ♥" : "Like ♡") {
                liked.toggle()
            }
            if count >= 5 {
                Text("Past five!")
                    .foregroundColor(.green)
            }
        }
        .padding(40)
    }
}
