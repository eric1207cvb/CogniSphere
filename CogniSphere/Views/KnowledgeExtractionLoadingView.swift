import SwiftUI

struct KnowledgeExtractionLoadingView: View {
    @EnvironmentObject private var regionUI: RegionUIStore
    @State private var pulse = false
    @State private var orbit = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.83, green: 0.89, blue: 1.0).opacity(0.22))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.08 : 0.88)

                    Circle()
                        .stroke(Color(red: 0.64, green: 0.78, blue: 1.0).opacity(0.42), lineWidth: 1.4)
                        .frame(width: 108, height: 108)

                    Circle()
                        .fill(Color(red: 0.14, green: 0.43, blue: 0.93))
                        .frame(width: 18, height: 18)
                        .offset(x: 0, y: -54)
                        .rotationEffect(.degrees(orbit ? 360 : 0))

                    Circle()
                        .fill(Color(red: 0.96, green: 0.74, blue: 0.24))
                        .frame(width: 12, height: 12)
                        .offset(x: 0, y: -38)
                        .rotationEffect(.degrees(orbit ? -360 : 0))

                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .white.opacity(0.32), radius: 10)
                }
                .frame(width: 128, height: 128)

                VStack(spacing: 6) {
                    Text(regionUI.copy.loadingKnowledgeTitle)
                        .font(.headline)
                    Text(regionUI.copy.loadingKnowledgeSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }

            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                orbit = true
            }
        }
    }
}

#Preview {
    KnowledgeExtractionLoadingView()
}
