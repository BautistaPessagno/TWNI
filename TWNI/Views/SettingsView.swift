import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    var timerManager: TimerManager

    @AppStorage("intervalMinutes") private var intervalMinutes: Int = 20
    @AppStorage("breakDurationSeconds") private var breakDurationSeconds: Int = 20
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true

    #if os(macOS)
    @State private var launchAtLogin = false
    #endif

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Protection Mode", selection: Binding(
                    get: { timerManager.timerMode },
                    set: { timerManager.timerMode = $0 }
                )) {
                    Text("Auto (20-20-20)").tag(TimerMode.auto)
                    Text("Manual").tag(TimerMode.manual)
                }
                .pickerStyle(.segmented)

                if timerManager.timerMode == .auto {
                    Text("Every 20 minutes, look at something 20 feet away for 20 seconds.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                } else {
                    Stepper(
                        "Interval: \(intervalMinutes) min",
                        value: $intervalMinutes,
                        in: 1...120
                    )
                    .onChange(of: intervalMinutes) {
                        timerManager.intervalMinutes = intervalMinutes
                    }

                    Stepper(
                        "Break duration: \(breakDurationSeconds) sec",
                        value: $breakDurationSeconds,
                        in: 5...120,
                        step: 5
                    )
                    .onChange(of: breakDurationSeconds) {
                        timerManager.breakDurationSeconds = breakDurationSeconds
                    }
                }
            }

            Section("Behavior") {
                Toggle("Sound effects", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) {
                        timerManager.soundEnabled = soundEnabled
                    }
            }

            #if os(iOS)
            AppBlockingSection(timerManager: timerManager)
            ScheduleSection(timerManager: timerManager)
            #endif

            #if os(macOS)
            Section("macOS") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        toggleLaunchAtLogin(launchAtLogin)
                    }
                    .onAppear {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            #endif

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Rule", value: "20-20-20")

                VStack(alignment: .leading, spacing: 8) {
                    Text("The 20-20-20 Rule")
                        .font(.subheadline.weight(.heavy))
                    Text("Every 20 minutes, look at something 20 feet away for 20 seconds. This helps reduce eye strain from prolonged screen use.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.monoSurface)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    #if os(macOS)
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
    #endif
}

// MARK: - App Blocking Section (iOS)

#if os(iOS)
private struct AppBlockingSection: View {
    var timerManager: TimerManager

    var body: some View {
        if let blockingService = timerManager.appBlockingService, blockingService.isAvailable {
            Section("App Blocking During Breaks") {
                if blockingService.isAuthorized {
                    Toggle("Block apps during breaks", isOn: Binding(
                        get: { blockingService.isBlockingEnabled },
                        set: { blockingService.isBlockingEnabled = $0 }
                    ))

                    #if canImport(FamilyControls)
                    if blockingService.isBlockingEnabled {
                        NavigationLink {
                            BreakAppSelectionView(blockingService: blockingService)
                        } label: {
                            LabeledContent("Apps to block", value: appsSelectedLabel)
                        }
                    }
                    #endif
                } else {
                    Button("Authorize App Blocking") {
                        Task {
                            await blockingService.requestAuthorization()
                        }
                    }

                    Text("Requires Screen Time authorization to block apps during breaks.")
                        .font(.caption)
                        .foregroundStyle(Color.monoTertiary)
                }
            }
        }
    }

    private var appsSelectedLabel: String {
        #if canImport(FamilyControls)
        let count = blockingService.activitySelection.applicationTokens.count
            + blockingService.activitySelection.categoryTokens.count
        return count > 0 ? "\(count) selected" : "None"
        #else
        return "N/A"
        #endif
    }

    private var blockingService: AppBlockingService {
        timerManager.appBlockingService!
    }
}
#endif

// MARK: - Break App Selection (iOS)

#if os(iOS) && canImport(FamilyControls)
import FamilyControls

private struct BreakAppSelectionView: View {
    var blockingService: AppBlockingService

    var body: some View {
        FamilyActivityPicker(selection: Binding(
            get: { blockingService.activitySelection },
            set: { blockingService.activitySelection = $0 }
        ))
        .navigationTitle("Break App Selection")
    }
}
#endif

// MARK: - Schedule Section (iOS)

#if os(iOS)
private struct ScheduleSection: View {
    var timerManager: TimerManager
    @State private var schedules: [BlockSchedule] = SharedDefaults.shared.schedules

    var body: some View {
        Section {
            if schedules.isEmpty {
                Text("No schedules yet. Add one to block apps on a recurring basis.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.monoTertiary)
            } else {
                ForEach(schedules) { schedule in
                    NavigationLink {
                        ScheduleEditorView(
                            schedule: schedule,
                            timerManager: timerManager,
                            onSave: { updated in
                                saveSchedule(updated)
                            },
                            onDelete: {
                                deleteSchedule(schedule)
                            }
                        )
                    } label: {
                        ScheduleRow(schedule: schedule)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        deleteSchedule(schedules[index])
                    }
                }
            }

            Button {
                addSchedule()
            } label: {
                Label("Add Schedule", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Scheduled Blocking")
        } footer: {
            Text("Schedules block selected apps during set time windows, even when this app isn't open.")
                .font(.caption2)
        }
        .onAppear {
            schedules = SharedDefaults.shared.schedules
        }
    }

    private func addSchedule() {
        let newSchedule = BlockSchedule()
        SharedDefaults.shared.updateSchedule(newSchedule)
        schedules = SharedDefaults.shared.schedules
        timerManager.screenTimeService?.syncAllSchedules()
    }

    private func saveSchedule(_ schedule: BlockSchedule) {
        SharedDefaults.shared.updateSchedule(schedule)
        schedules = SharedDefaults.shared.schedules
        timerManager.screenTimeService?.syncAllSchedules()
    }

    private func deleteSchedule(_ schedule: BlockSchedule) {
        timerManager.screenTimeService?.stopMonitoring(schedule: schedule)
        SharedDefaults.shared.removeSchedule(id: schedule.id)
        schedules = SharedDefaults.shared.schedules
    }
}

private struct ScheduleRow: View {
    let schedule: BlockSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.name)
                    .font(.body.weight(.semibold))
                Spacer()
                if !schedule.isEnabled {
                    Text("Off")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                }
            }
            HStack(spacing: 4) {
                Text(timeRangeText)
                Text("·")
                Text(weekdayText)
            }
            .font(.caption)
            .foregroundStyle(Color.monoSecondary)
        }
        .padding(.vertical, 2)
    }

    private var timeRangeText: String {
        let start = formatTime(schedule.startTime)
        let end = formatTime(schedule.endTime)
        return "\(start) – \(end)"
    }

    private var weekdayText: String {
        if schedule.weekdays.count == 7 {
            return "Every day"
        }
        let symbols = Calendar.current.shortWeekdaySymbols
        let sorted = schedule.weekdays.sorted()
        return sorted.map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    private func formatTime(_ time: ScheduleTimeOfDay) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(time.hour):\(String(format: "%02d", time.minute))"
    }
}
#endif

// MARK: - Schedule Editor (iOS)

#if os(iOS)
private struct ScheduleEditorView: View {
    @State var schedule: BlockSchedule
    var timerManager: TimerManager
    var onSave: (BlockSchedule) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var endDate = Date()

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $schedule.name)
                Toggle("Enabled", isOn: $schedule.isEnabled)
            }

            Section("Time Window") {
                DatePicker("Start", selection: $startDate, displayedComponents: .hourAndMinute)
                    .onChange(of: startDate) {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
                        schedule.startTime = ScheduleTimeOfDay(
                            hour: comps.hour ?? 9, minute: comps.minute ?? 0
                        )
                    }
                DatePicker("End", selection: $endDate, displayedComponents: .hourAndMinute)
                    .onChange(of: endDate) {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: endDate)
                        schedule.endTime = ScheduleTimeOfDay(
                            hour: comps.hour ?? 17, minute: comps.minute ?? 0
                        )
                    }
            }

            Section("Repeat") {
                WeekdayPicker(selectedDays: $schedule.weekdays)
            }

            Section {
                CategoryPresetsView(selectedPresets: $schedule.categoryPresets)
            } header: {
                Text("Category Presets")
            } footer: {
                Text("Quick-toggle common app categories. Use manual selection below for full control.")
                    .font(.caption2)
            }

            #if canImport(FamilyControls)
            Section("App Selection") {
                NavigationLink {
                    ScheduleAppPickerView(schedule: $schedule)
                } label: {
                    LabeledContent("Selected apps", value: appCountLabel)
                }
            }
            #endif

            Section {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Schedule")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(schedule.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startDate = makeDate(from: schedule.startTime)
            endDate = makeDate(from: schedule.endTime)
        }
        .onDisappear {
            onSave(schedule)
        }
    }

    private var appCountLabel: String {
        #if canImport(FamilyControls)
        guard let data = schedule.selectionData,
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self, from: data
              ) else { return "None" }
        let count = selection.applicationTokens.count + selection.categoryTokens.count
        return count > 0 ? "\(count) selected" : "None"
        #else
        return "N/A"
        #endif
    }

    private func makeDate(from time: ScheduleTimeOfDay) -> Date {
        var comps = DateComponents()
        comps.hour = time.hour
        comps.minute = time.minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Weekday Picker

private struct WeekdayPicker: View {
    @Binding var selectedDays: Set<Int>

    private let days: [(Int, String)] = {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.enumerated().map { ($0.offset + 1, $0.element) }
    }()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.0) { day, symbol in
                Button {
                    if selectedDays.contains(day) {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(String(symbol.prefix(2)))
                        .font(.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(
                            selectedDays.contains(day) ? Color.monoSurface : Color.monoPrimary
                        )
                        .background(
                            selectedDays.contains(day) ? Color.monoAccent : Color.monoCard,
                            in: Circle()
                        )
                        .overlay(
                            Circle().stroke(Color.monoBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Category Presets

private struct CategoryPresetsView: View {
    @Binding var selectedPresets: Set<String>

    var body: some View {
        ForEach(CategoryPreset.allCases) { preset in
            Toggle(isOn: Binding(
                get: { selectedPresets.contains(preset.rawValue) },
                set: { isOn in
                    if isOn {
                        selectedPresets.insert(preset.rawValue)
                    } else {
                        selectedPresets.remove(preset.rawValue)
                    }
                }
            )) {
                Label(preset.rawValue, systemImage: preset.systemImageName)
            }
        }
    }
}
#endif

// MARK: - Schedule App Picker (iOS)

#if os(iOS) && canImport(FamilyControls)
private struct ScheduleAppPickerView: View {
    @Binding var schedule: BlockSchedule

    @State private var selection: FamilyActivitySelection

    init(schedule: Binding<BlockSchedule>) {
        self._schedule = schedule
        if let data = schedule.wrappedValue.selectionData,
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self._selection = State(initialValue: decoded)
        } else {
            self._selection = State(initialValue: FamilyActivitySelection())
        }
    }

    var body: some View {
        FamilyActivityPicker(selection: $selection)
            .navigationTitle("Select Apps")
            .onChange(of: selection) {
                schedule.selectionData = try? JSONEncoder().encode(selection)
            }
    }
}
#endif
