import SwiftUI

/// First-run flow: hook, two quick questions, a personal "mirror" number, one
/// sourced fact, the plan, how it works on this device, permissions, and a
/// first break. Every claim here must match ScienceView's sources.
struct OnboardingView: View {
    @Bindable var timerManager: TimerManager

    @State private var step: Step = .hook
    @State private var symptoms: Set<Symptom> = []
    @State private var blinkCount = 0
    @State private var showingSources = false

    enum Step: CaseIterable {
        case hook
        case hours
        case symptoms
        case mirror
        case research
        case plan
        case howItWorks
        case reminders
        case ready

        /// The steps shown on this device (macOS needs no notification permission).
        static var flow: [Step] {
            #if os(iOS)
            return allCases
            #else
            return allCases.filter { $0 != .reminders }
            #endif
        }
    }

    private var stepIndex: Int { Step.flow.firstIndex(of: step) ?? 0 }

    enum Symptom: String, CaseIterable, Identifiable {
        case tired = "Tired or heavy eyes"
        case dry = "Dry or itchy eyes"
        case blurry = "Blurry vision"
        case headaches = "Headaches"
        case none = "Not really"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                content
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .background(Color.monoSurface)
        .animation(.easeInOut(duration: 0.3), value: step)
        .sheet(isPresented: $showingSources) {
            NavigationStack {
                ScienceView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSources = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 520)
            #endif
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(step == .hook ? 0 : 1)
            .disabled(step == .hook)
            .accessibilityLabel("Back")

            ProgressView(value: Double(stepIndex + 1), total: Double(Step.flow.count))
                .tint(Color.monoProgressFill)
                .accessibilityLabel("Step \(stepIndex + 1) of \(Step.flow.count)")

            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.monoPrimary)
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(MonochromePrimaryButtonStyle())
                .font(.headline)
                .disabled(step == .symptoms && symptoms.isEmpty)
                .opacity(step == .symptoms && symptoms.isEmpty ? 0.5 : 1)

            if let secondaryTitle {
                Button(secondaryTitle) { secondaryAction() }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.monoSecondary)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hook: hook
        case .hours: hours
        case .symptoms: symptomsStep
        case .mirror: mirror
        case .research: research
        case .plan: plan
        case .howItWorks: howItWorks
        case .reminders: reminders
        case .ready: ready
        }
    }

    private var hook: some View {
        VStack(spacing: 28) {
            Button {
                blinkCount += 1
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 96, weight: .ultraLight))
                    .foregroundStyle(Color.monoPrimary)
                    .symbolEffect(.bounce, value: blinkCount)
                    .frame(width: 160, height: 160)
                    .background(Color.monoCard, in: Circle())
                    .overlay(Circle().stroke(Color.monoBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eye")
            .accessibilityHint("Tap to blink")

            title("Your eyes weren't made for screens all day.")
            subtitle("TWNI helps them rest, 20 seconds at a time.")
        }
        .multilineTextAlignment(.center)
        .padding(.top, 24)
    }

    private var hours: some View {
        VStack(spacing: 28) {
            title("How many hours a day are you on screens?")
            subtitle("Phone, computer, TV: all of it. A guess is fine.")

            HStack(spacing: 24) {
                roundButton("minus", label: "Fewer hours") {
                    timerManager.dailyScreenHours = max(timerManager.dailyScreenHours - 1, 1)
                }
                VStack(spacing: 0) {
                    Text("\(timerManager.dailyScreenHours)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(timerManager.dailyScreenHours == 1 ? "hour" : "hours")
                        .font(.headline)
                        .foregroundStyle(Color.monoSecondary)
                }
                .frame(minWidth: 120)
                .foregroundStyle(Color.monoPrimary)
                .accessibilityElement(children: .combine)
                roundButton("plus", label: "More hours") {
                    timerManager.dailyScreenHours = min(timerManager.dailyScreenHours + 1, 16)
                }
            }
            .animation(.snappy, value: timerManager.dailyScreenHours)
        }
        .multilineTextAlignment(.center)
    }

    private var symptomsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("After a long screen day, do your eyes feel like this?")
            subtitle("Pick any that apply.")
            VStack(spacing: 10) {
                ForEach(Symptom.allCases) { symptom in
                    SymptomRow(title: symptom.rawValue, isSelected: symptoms.contains(symptom)) {
                        toggle(symptom)
                    }
                }
            }
        }
    }

    private var mirror: some View {
        let hoursPerYear = timerManager.dailyScreenHours * 365
        let days = hoursPerYear / 24
        let breaksPerDay = timerManager.dailyScreenHours * 60 / max(timerManager.effectiveIntervalMinutes, 1)
        return VStack(spacing: 20) {
            subtitle("At \(timerManager.dailyScreenHours) hours a day, that's")
            Text("\(hoursPerYear.formatted()) hours")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.monoPrimary)
                .minimumScaleFactor(0.6)
            subtitle("of screen time this year, about \(days) full days with your eyes focused up close.")
            Divider().padding(.vertical, 8)
            Text("Your plan gives them \(breaksPerDay) short breaks a day.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
        }
        .multilineTextAlignment(.center)
    }

    private var research: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.monoPrimary)
                .accessibilityHidden(true)
            title(hasSymptoms ? "You're not alone." : "It's more common than you'd think.")
            subtitle("In pooled studies, roughly 2 in 3 people who use screens a lot report eye strain: tired, dry or blurry eyes, or headaches.")
            subtitle("Eye doctors recommend a simple habit to ease it: the 20-20-20 rule.")
            Button("See the sources") { showingSources = true }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.monoPrimary)
                .underline()
        }
        .multilineTextAlignment(.center)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Your plan")
            VStack(alignment: .leading, spacing: 14) {
                planRow("clock", "Every 20 minutes of screen time")
                planRow("mountain.2", "look at something 6 m (20 ft) away")
                planRow("timer", "for 20 seconds")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .monochromeCard()

            Text("How firm should breaks be?")
                .font(.headline)
                .foregroundStyle(Color.monoPrimary)
            Picker("Break style", selection: $timerManager.breakStyle) {
                ForEach(BreakStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(timerManager.breakStyle.summary)
                .font(.subheadline)
                .foregroundStyle(Color.monoSecondary)

            Text("Each day gets a Break Score from 0 to 100. Reach \(timerManager.dailyGoal) to grow your streak.")
                .font(.subheadline)
                .foregroundStyle(Color.monoSecondary)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            title("TWNI lives in your menu bar")
            planRow("laptopcomputer", "Counts screen time only while you use your Mac")
            planRow("figure.walk", "Steps away? Locked screen? That counts as a rest")
            planRow("phone", "Holds breaks while you're on a call")
            planRow("rectangle.inset.filled", "Covers every screen when it's time to look away")
            #else
            title("How it works on iPhone")
            planRow("hourglass", "With Screen Time access, TWNI counts only the time you spend in your apps, even when it's closed")
            planRow("lock", "After 20 minutes, those apps lock until you rest your eyes for 20 seconds")
            planRow("bell", "No access? Start a screen session and TWNI reminds you every 20 minutes")
            #endif
        }
    }

    private var reminders: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.monoPrimary)
                .accessibilityHidden(true)
            title("Allow reminders")
            subtitle("Reminders are how TWNI reaches you in other apps. You'll only get them during a screen session.")
        }
        .multilineTextAlignment(.center)
    }

    private var ready: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.monoPrimary)
                .accessibilityHidden(true)
            title("You're set")
            #if os(macOS)
            subtitle("Try your first eye break now. It takes 20 seconds.")
            #else
            subtitle("Start your first screen session, or come back when you settle in.")
            #endif
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Buttons

    private var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private var primaryTitle: String {
        switch step {
        case .hook: return "Get started"
        case .reminders: return "Allow notifications"
        case .ready: return isMac ? "Take my first break" : "Start a 1-hour session"
        default: return "Continue"
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .reminders: return "Not now"
        case .ready: return isMac ? "Start without it" : "Later"
        default: return nil
        }
    }

    private func primaryAction() {
        switch step {
        case .reminders:
            Task {
                await timerManager.requestNotificationPermission()
                advance()
            }
        case .ready:
            timerManager.completeOnboarding()
            #if os(macOS)
            timerManager.startBreakNow()
            #else
            timerManager.startSession(minutes: 60)
            #endif
        default:
            advance()
        }
    }

    private func secondaryAction() {
        switch step {
        case .ready:
            timerManager.completeOnboarding()
        default:
            advance()
        }
    }

    private func advance() {
        let flow = Step.flow
        guard stepIndex + 1 < flow.count else { return }
        step = flow[stepIndex + 1]
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        step = Step.flow[stepIndex - 1]
    }

    private var hasSymptoms: Bool {
        !symptoms.isEmpty && !symptoms.contains(.none)
    }

    private func toggle(_ symptom: Symptom) {
        if symptom == .none {
            symptoms = symptoms.contains(.none) ? [] : [.none]
            return
        }
        symptoms.remove(.none)
        if symptoms.contains(symptom) {
            symptoms.remove(symptom)
        } else {
            symptoms.insert(symptom)
        }
    }

    // MARK: - Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Color.monoPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(Color.monoSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func planRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.monoPrimary)
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(Color.monoCard, in: Circle())
                .overlay(Circle().stroke(Color.monoBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.monoPrimary)
        .accessibilityLabel(label)
    }
}

private struct SymptomRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.monoPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(isSelected ? Color.monoElevated : Color.monoCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.monoPrimary : Color.monoBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
