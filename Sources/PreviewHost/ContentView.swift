import SwiftUI

struct Fruit: Identifiable {
    let name: String
    let icon: String
    var id: String { name }
}

struct ContentView: View {
    @State private var nickname = ""
    @State private var notifications = true
    @State private var compact = false

    let fruits = [
        Fruit(name: "Apple", icon: "star"),
        Fruit(name: "Banana", icon: "sun.max"),
        Fruit(name: "Cherry", icon: "heart"),
        Fruit(name: "Grape", icon: "moon"),
        Fruit(name: "Lemon", icon: "bolt"),
        Fruit(name: "Peach", icon: "cloud"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    TextField("Nickname", text: $nickname)
                    Toggle("Notifications", isOn: $notifications)
                    Toggle("Compact Mode", isOn: $compact)
                }
                Section("Fruits") {
                    ForEach(fruits) { fruit in
                        NavigationLink(destination: FruitDetail(fruit: fruit)) {
                            Label(fruit.name, systemImage: fruit.icon)
                        }
                    }
                }
                Section {
                    Button("Reset") {
                        nickname = ""
                        notifications = true
                        compact = false
                    }
                } header: {
                    Text("Other")
                } footer: {
                    Text("Rendered on Windows from unmodified SwiftUI code.")
                }
            }
            .navigationTitle(nickname.isEmpty ? "Settings" : "Hi, \(nickname)")
        }
    }
}

struct FruitDetail: View {
    let fruit: Fruit
    @State private var count = 0

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: fruit.icon)
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(fruit.name)
                .font(.largeTitle)
                .bold()
            Text("In basket: \(count)")
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("Remove") { if count > 0 { count -= 1 } }
                Button("Add") { count += 1 }
            }
        }
        .navigationTitle(fruit.name)
    }
}

@ViewBuilder func __preview_0() -> some View {
    ContentView()
}
