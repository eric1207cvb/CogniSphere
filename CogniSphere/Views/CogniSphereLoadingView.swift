import SwiftUI

struct CogniSphereLoadingView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white

                Image("LaunchBirdHero")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: min(geometry.size.width * 0.42, 170),
                        height: min(geometry.size.height * 0.28, 220)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .ignoresSafeArea()
        }
    }
}
