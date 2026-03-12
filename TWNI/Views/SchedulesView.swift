#if os(iOS)
import SwiftUI

struct SchedulesView: View {
    var timerManager: TimerManager
    @State private var schedules: [BlockSchedule] = SharedDefaults.shared.schedules
    @State private var customGroups: [CustomAppGroup] = SharedDefaults.shared.customAppGroups

    var body: some View {
        Form {
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

            Section {
                if customGroups.isEmpty {
                    Text("Create custom app groups to quickly assign apps to schedules.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.monoTertiary)
                } else {
                    ForEach(customGroups) { group in
                        NavigationLink {
                            AppGroupEditorView(
                                group: group,
                                onSave: { updated in
                                    saveGroup(updated)
                                },
                                onDelete: {
                                    deleteGroup(group)
                                }
                            )
                        } label: {
                            AppGroupRow(group: group)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            deleteGroup(customGroups[index])
                        }
                    }
                }

                Button {
                    addGroup()
                } label: {
                    Label("Add App Group", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Custom App Groups")
            } footer: {
                Text("Reusable groups of apps you can assign to multiple schedules.")
                    .font(.caption2)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.monoSurface)
        .navigationTitle("Schedules")
        .onAppear {
            schedules = SharedDefaults.shared.schedules
            customGroups = SharedDefaults.shared.customAppGroups
        }
    }

    // MARK: - Schedule Actions

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

    // MARK: - App Group Actions

    private func addGroup() {
        let newGroup = CustomAppGroup()
        SharedDefaults.shared.updateCustomAppGroup(newGroup)
        customGroups = SharedDefaults.shared.customAppGroups
    }

    private func saveGroup(_ group: CustomAppGroup) {
        SharedDefaults.shared.updateCustomAppGroup(group)
        customGroups = SharedDefaults.shared.customAppGroups
    }

    private func deleteGroup(_ group: CustomAppGroup) {
        SharedDefaults.shared.removeCustomAppGroup(id: group.id)
        customGroups = SharedDefaults.shared.customAppGroups
    }
}

// MARK: - App Group Row

struct AppGroupRow: View {
    let group: CustomAppGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name)
                .font(.body.weight(.semibold))
            Text(appCountLabel)
                .font(.caption)
                .foregroundStyle(Color.monoSecondary)
        }
        .padding(.vertical, 2)
    }

    private var appCountLabel: String {
        #if canImport(FamilyControls)
        guard let data = group.selectionData,
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self, from: data
              ) else { return "No apps selected" }
        let count = selection.applicationTokens.count + selection.categoryTokens.count
        return count > 0 ? "\(count) app\(count == 1 ? "" : "s") selected" : "No apps selected"
        #else
        return "N/A"
        #endif
    }
}

// MARK: - App Group Editor

struct AppGroupEditorView: View {
    @State var group: CustomAppGroup
    var onSave: (CustomAppGroup) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Details") {
                TextField("Group Name", text: $group.name)
            }

            #if canImport(FamilyControls)
            Section("Apps") {
                NavigationLink {
                    AppGroupPickerView(group: $group)
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
                        Text("Delete Group")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            onSave(group)
        }
    }

    private var appCountLabel: String {
        #if canImport(FamilyControls)
        guard let data = group.selectionData,
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self, from: data
              ) else { return "None" }
        let count = selection.applicationTokens.count + selection.categoryTokens.count
        return count > 0 ? "\(count) selected" : "None"
        #else
        return "N/A"
        #endif
    }
}


// MARK: - Schedule Row

struct ScheduleRow: View {
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

// MARK: - Schedule Editor

struct ScheduleEditorView: View {
    @State var schedule: BlockSchedule
    var timerManager: TimerManager
    var onSave: (BlockSchedule) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var customGroups: [CustomAppGroup] = SharedDefaults.shared.customAppGroups

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
                DisclosureGroup("Built-in Categories") {
                    CategoryPresetsView(selectedPresets: $schedule.categoryPresets)
                }

                if !customGroups.isEmpty {
                    DisclosureGroup("Custom App Groups") {
                        ForEach(customGroups) { group in
                            Toggle(isOn: Binding(
                                get: { schedule.customGroupIDs.contains(group.id) },
                                set: { isOn in
                                    if isOn {
                                        schedule.customGroupIDs.insert(group.id)
                                    } else {
                                        schedule.customGroupIDs.remove(group.id)
                                    }
                                }
                            )) {
                                Label(group.name, systemImage: "folder.fill")
                            }
                        }
                    }
                }
            } header: {
                Text("App Groups")
            } footer: {
                Text("Select built-in categories or your custom groups. Use manual selection below for individual apps.")
                    .font(.caption2)
            }

            #if canImport(FamilyControls)
            Section("Manual App Selection") {
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
            customGroups = SharedDefaults.shared.customAppGroups
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

struct WeekdayPicker: View {
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

struct CategoryPresetsView: View {
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

// MARK: - FamilyControls Pickers

#if canImport(FamilyControls)
import FamilyControls

struct ScheduleAppPickerView: View {
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

struct AppGroupPickerView: View {
    @Binding var group: CustomAppGroup

    @State private var selection: FamilyActivitySelection

    init(group: Binding<CustomAppGroup>) {
        self._group = group
        if let data = group.wrappedValue.selectionData,
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
                group.selectionData = try? JSONEncoder().encode(selection)
            }
    }
}
#endif

#endif
