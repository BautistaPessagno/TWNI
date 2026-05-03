#if os(iOS)
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

struct OnboardingView: View {
    var timerManager: TimerManager
    var blockingService: AppBlockingService
    var screenTimeService: iOSScreenTimeService
    var onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var isRequestingAuth = false
    @State private var showAppPicker = false

    enum Step {
        case welcome
        case pickApps
    }

    var body: some View {
        ZStack {
            Color.monoSurface.ignoresSafeArea()

            switch step {
            case .welcome:
                welcomeContent
            case .pickApps:
                pickAppsContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear(perform: syncStep)
    }

    private func syncStep() {
        #if canImport(FamilyControls)
        blockingService.refreshAuthorization()
        if blockingService.isAuthorized {
            step = .pickApps
        } else {
            step = .welcome
        }
        #endif
    }

    // MARK: - Welcome step

    private var welcomeContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "eye.square")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.monoPrimary)

            VStack(spacing: 10) {
                Text("Protect Your Eyes")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color.monoPrimary)
                Text("Every 20 minutes of screen time, TWNI will pause your apps for a 20-second break.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.monoSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: authorize) {
                    HStack(spacing: 8) {
                        if isRequestingAuth {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.monoSurface)
                        } else {
                            Image(systemName: "hand.raised.fill")
                        }
                        Text(isRequestingAuth ? "Requesting..." : "Authorize Screen Time")
                            .font(.headline.weight(.heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(MonochromePrimaryButtonStyle())
                .disabled(isRequestingAuth)
                .padding(.horizontal, 32)

                if blockingService.authorizationStatusIsDenied {
                    VStack(spacing: 6) {
                        Text("Access denied. Enable TWNI in Settings → Screen Time.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.monoSecondary)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline.weight(.heavy))
                    }
                    .padding(.horizontal, 32)
                }

                #if targetEnvironment(simulator)
                Button("Skip (Simulator test mode — blocking is non-functional)") {
                    simulatorBypass()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.monoSecondary)
                .padding(.horizontal, 32)
                #endif
            }
            .padding(.bottom, 48)
        }
        .padding()
    }

    private func authorize() {
        isRequestingAuth = true
        Task {
            await blockingService.requestAuthorization()
            await screenTimeService.refreshAuthorization()
            isRequestingAuth = false
            if blockingService.isAuthorized {
                step = .pickApps
            }
        }
    }

    #if targetEnvironment(simulator)
    private func simulatorBypass() {
        onFinished()
    }
    #endif

    // MARK: - Pick Apps step

    private var pickAppsContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "app.badge")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Color.monoPrimary)

            VStack(spacing: 10) {
                Text("Pick Apps to Pause")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.monoPrimary)
                Text("We'll gently shield these apps during your 20-second eye break, then unshield automatically.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.monoSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text(selectionSummary)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.monoPrimary)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showAppPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                        Text(hasSelection ? "Edit Selection" : "Choose Apps")
                            .font(.headline.weight(.heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(MonochromeSecondaryButtonStyle())
                .padding(.horizontal, 32)

                Button {
                    onFinished()
                } label: {
                    Text("Start")
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(MonochromePrimaryButtonStyle())
                .disabled(!hasSelection)
                .opacity(hasSelection ? 1 : 0.6)
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 48)
        }
        .padding()
        #if canImport(FamilyControls)
        .sheet(isPresented: $showAppPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: Binding(
                    get: { blockingService.activitySelection },
                    set: { blockingService.activitySelection = $0 }
                ))
                .navigationTitle("Apps to Shield")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showAppPicker = false }
                    }
                }
            }
        }
        #endif
    }

    private var hasSelection: Bool {
        #if canImport(FamilyControls)
        let selection = blockingService.activitySelection
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        #else
        return false
        #endif
    }

    private var selectionSummary: String {
        #if canImport(FamilyControls)
        let selection = blockingService.activitySelection
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        if apps == 0 && categories == 0 {
            return "Nothing selected yet"
        }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        return parts.joined(separator: " · ")
        #else
        return ""
        #endif
    }
}

#if canImport(FamilyControls)
private extension AppBlockingService {
    var authorizationStatusIsDenied: Bool {
        AuthorizationCenter.shared.authorizationStatus == .denied
    }
}
#else
private extension AppBlockingService {
    var authorizationStatusIsDenied: Bool { false }
}
#endif
#endif
