import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            GravacaoView()
                .tabItem { Label("Gravar", systemImage: "mic.fill") }
                .tag(0)

            DisciplinasListView()
                .tabItem { Label("Disciplinas", systemImage: "book.fill") }
                .tag(1)

            ChatView()
                .tabItem { Label("IA", systemImage: "sparkles") }
                .tag(2)
        }
        .tint(CoffeeTheme.Colors.coffee)
    }
}
