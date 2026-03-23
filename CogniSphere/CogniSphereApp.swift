import SwiftUI
import SwiftData

@main
struct CogniSphereApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLaunchSplash = true
    @StateObject private var libraryStore = KnowledgeLibraryStore()
    @StateObject private var regionUIStore = RegionUIStore()
    @StateObject private var subscriptionAccessStore = SubscriptionAccessController()
    @StateObject private var persistenceDiagnosticsStore: PersistenceDiagnosticsStore
    private static let minimumSplashDuration: Duration = .milliseconds(650)

    private let sharedModelContainer: ModelContainer

    @MainActor
    init() {
        let persistenceDiagnosticsStore = PersistenceDiagnosticsStore()
        _persistenceDiagnosticsStore = StateObject(wrappedValue: persistenceDiagnosticsStore)
        sharedModelContainer = Self.makeSharedModelContainer(
            persistenceDiagnosticsStore: persistenceDiagnosticsStore
        )
    }

    @MainActor
    private static func makeSharedModelContainer(
        persistenceDiagnosticsStore: PersistenceDiagnosticsStore
    ) -> ModelContainer {
        let schema = Schema([
            KnowledgeLibrary.self,
            KnowledgeNode.self,
            KnowledgeReference.self
        ])
        do {
            let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL.applicationSupportDirectory
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            let persistentConfiguration = ModelConfiguration(
                "default",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )

            return try ModelContainer(for: schema, configurations: [persistentConfiguration])
        } catch {
            persistenceDiagnosticsStore.presentPersistentStoreFailure(underlyingError: error)
            do {
                let inMemoryConfiguration = ModelConfiguration(
                    "recovery",
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            } catch {
                fatalError("❌ 無法建立 SwiftData 容器：\(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(libraryStore)
                    .environmentObject(regionUIStore)
                    .environmentObject(subscriptionAccessStore)
                    .environmentObject(persistenceDiagnosticsStore)
                    .opacity(showLaunchSplash ? 0 : 1)

                if showLaunchSplash {
                    CogniSphereLoadingView()
                        .transition(.opacity.animation(.easeInOut(duration: 0.45)))
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.light)
            .environment(\.locale, regionUIStore.locale)
            .tint(regionUIStore.theme.accent)
            .sheet(item: $subscriptionAccessStore.presentedPaywall) { presentation in
                SubscriptionPaywallView(presentation: presentation)
                    .environmentObject(regionUIStore)
                    .environmentObject(subscriptionAccessStore)
            }
            .alert(startupAlertTitle, isPresented: Binding(
                get: { persistenceDiagnosticsStore.startupAlert != nil },
                set: { if !$0 { persistenceDiagnosticsStore.startupAlert = nil } }
            )) {
                Button(regionUIStore.copy.ok, role: .cancel) {}
            } message: {
                Text(persistenceDiagnosticsStore.startupAlert?.message ?? "")
            }
            .task {
                subscriptionAccessStore.prepare()
                AttachmentSyncBackfillService.backfillMissingAttachmentDataIfNeeded(
                    modelContext: sharedModelContainer.mainContext
                )
                guard showLaunchSplash else { return }
                try? await Task.sleep(for: Self.minimumSplashDuration)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLaunchSplash = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await subscriptionAccessStore.refreshSubscriptionState()
                }
            }
        }
        .modelContainer(sharedModelContainer) // 掛載我們寫好的最強容器
    }

    private var startupAlertTitle: String {
        switch regionUIStore.region {
        case .taiwan:
            return "本機資料暫時無法使用"
        case .unitedStates:
            return "Local Data Unavailable"
        case .japan:
            return "ローカルデータを利用できません"
        }
    }
}
