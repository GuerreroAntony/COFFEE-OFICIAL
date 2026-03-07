import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(CoffeeTheme.Colors.coffee)
                .scaleEffect(1.4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
