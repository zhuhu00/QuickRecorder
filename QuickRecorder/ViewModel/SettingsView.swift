//
//  SettingsView.swift
//  QuickRecorder
//

import AppKit
import SwiftUI
import ServiceManagement
import KeyboardShortcuts

struct CompactSettingsView: View {
    var compact = false
    var onHotkeysExpandedChange: ((Bool) -> Void)?

    @AppStorage("audioFormat") private var audioFormat: AudioFormat = .aac
    @AppStorage("audioQuality") private var audioQuality: AudioQuality = .good
    @AppStorage("videoFormat") private var videoFormat: VideoFormat = .mp4
    @AppStorage("videoQuality") private var videoQuality: Double = 1.0
    @AppStorage("recordingIndicatorStyle") private var recordingIndicatorStyle: RecordingIndicatorStyle = .defaultValue
    @AppStorage("showPreview") private var showPreview: Bool = true
    @AppStorage("saveDirectory") private var saveDirectory: String = NSHomeDirectory() + "/Documents/Records"
    @AppStorage("showOnDock") private var showOnDock: Bool = true
    @AppStorage("showMenubar") private var showMenubar: Bool = true
    @AppStorage(TranscriptionStore.autoTranscribeKey) private var autoTranscribe: Bool = true
    @AppStorage(TranscriptionStore.languageKey) private var transcriptionLanguage: TranscriptionLanguage = .automatic

    @State private var launchAtLogin = false
    @State private var hotkeysExpanded = false
    @ObservedObject private var transcription = TranscriptionStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if compact {
                VStack(spacing: 10) {
                    outputSettings
                    transcriptionSettings
                    recordingSettings
                    startupSettings
                    compactHotkeySettings
                }
            } else {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        outputSettings
                        transcriptionSettings
                        recordingSettings
                        startupSettings
                    }

                    if hotkeysExpanded {
                        CompactSettingsCard(title: "Keyboard Shortcuts", minimumHeight: nil) {
                            CoreHotkeySettingsView(compact: false)
                        }
                    }
                }
            }

        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var outputSettings: some View {
        CompactSettingsCard(title: "Output") {
            HStack(spacing: 8) {
                CompactMenuPicker(
                    selection: $audioQuality,
                    options: [(.good, "192K"), (.high, "256K")]
                )
                .frame(maxWidth: .infinity)

                CompactMenuPicker(
                    selection: $videoQuality,
                    options: [(0.7, "Standard".local), (1.0, "High".local)]
                )
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 26)

            HStack(spacing: 8) {
                Picker("Audio Format".local, selection: $audioFormat) {
                    Text("AAC").tag(AudioFormat.aac)
                    Text("MP3").tag(AudioFormat.mp3)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Picker("Video Format".local, selection: $videoFormat) {
                    Text("MP4").tag(VideoFormat.mp4)
                    Text("MOV").tag(VideoFormat.mov)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 26)

            HStack(spacing: 8) {
                Text("Output Folder".local)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                Button(action: updateOutputDirectory) {
                    HStack(spacing: 4) {
                        Text(saveDirectory.lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 92, alignment: .trailing)
            }
            .frame(minHeight: 26)

            HStack(spacing: 8) {
                Text((saveDirectory as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(saveDirectory)
                Spacer(minLength: 0)
                Button("Default".local, action: confirmDefaultOutputDirectory)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(size: 10))
            }
        }
    }

    private var transcriptionSettings: some View {
        CompactSettingsCard(title: "Transcription") {
            CompactSettingRow(label: "Auto Transcribe") {
                Toggle("Auto Transcribe".local, isOn: autoTranscribeBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            CompactSettingRow(label: "Language") {
                CompactMenuPicker(
                    selection: $transcriptionLanguage,
                    options: TranscriptionLanguage.allCases.map { ($0, $0.displayName) }
                )
                .frame(width: compact ? 155 : 100)
            }

            CompactSettingRow(label: "Model") {
                modelControl
            }

            if case .downloading = transcription.modelStatus {
                ProgressView(value: transcription.downloadProgress)
                    .progressViewStyle(.linear)
            } else if let task = transcription.currentTask {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.displayName)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Cancel".local) {
                            transcription.cancelCurrentTask()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                    }
                    ProgressView(value: transcription.progress)
                        .progressViewStyle(.linear)
                }
            } else if transcription.waitingCount > 0 {
                Text(String(format: "%d task(s) waiting".local, transcription.waitingCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let issue = transcription.retainedIssues.first {
                HStack(spacing: 6) {
                    Text(issue.displayName)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Retry".local) { transcription.retry(issue) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                    Button("Remove".local) { transcription.remove(issue) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        switch transcription.modelStatus {
        case .notDownloaded, .failed:
            Button("Download".local) {
                transcription.downloadModel()
            }
            .buttonStyle(.borderless)
        case .downloading:
            HStack(spacing: 5) {
                Text("\(Int(transcription.downloadProgress * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Cancel".local) {
                    transcription.cancelModelDownload()
                }
                .buttonStyle(.borderless)
            }
        case .ready:
            HStack(spacing: 5) {
                Text(TranscriptionStore.approximateModelSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("Delete".local, role: .destructive) {
                    confirmModelDeletion()
                }
                .buttonStyle(.borderless)
            }
        case .loading:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var autoTranscribeBinding: Binding<Bool> {
        Binding(
            get: { autoTranscribe },
            set: { newValue in
                if !newValue {
                    autoTranscribe = false
                    transcription.setAutomaticTranscription(false)
                    return
                }

                if transcription.modelStatus == .ready {
                    autoTranscribe = true
                    return
                }

                let alert = createAlert(
                    level: .informational,
                    title: "Download Transcription Model",
                    message: String(
                        format: "QuickRecorder will download a %@ local model. Recordings and transcripts never leave this Mac.".local,
                        TranscriptionStore.approximateModelSize
                    ),
                    button1: "Download",
                    button2: "Cancel"
                )
                if alert.runModal() == .alertFirstButtonReturn {
                    autoTranscribe = true
                    transcription.setAutomaticTranscription(true)
                } else {
                    autoTranscribe = false
                }
            }
        )
    }

    private func confirmModelDeletion() {
        let alert = createAlert(
            title: "Delete Transcription Model",
            message: "Automatic transcription will be turned off. Existing recordings and transcripts will not be deleted.",
            button1: "Delete",
            button2: "Cancel"
        )
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        autoTranscribe = false
        transcription.deleteModel()
    }

    private var recordingSettings: some View {
        CompactSettingsCard(title: "Recording", minimumHeight: compact ? nil : 132) {
            CompactMenuPicker(
                selection: $recordingIndicatorStyle,
                options: [
                    (.full, "Full Controls".local),
                    (.discreet, "Discreet Stop Icon".local)
                ]
            )
            .frame(maxWidth: .infinity, minHeight: 26)

            CompactSettingRow(label: "Show Preview") {
                Toggle("Show Preview".local, isOn: $showPreview)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            if !compact {
                hotkeyToggleButton
            }
        }
    }

    private var compactHotkeySettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            hotkeyToggleButton

            if hotkeysExpanded {
                Divider()
                CoreHotkeySettingsView(compact: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var hotkeyToggleButton: some View {
        Button(action: toggleHotkeys) {
            HStack(spacing: 8) {
                Label("Keyboard Shortcuts".local, systemImage: "command")
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(hotkeysExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 26)
    }

    private var startupSettings: some View {
        CompactSettingsCard(title: "Startup") {
            CompactSettingRow(label: "Launch at Login") {
                Toggle("Launch at Login".local, isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            CompactSettingRow(label: "Show on Dock") {
                Toggle("Show on Dock".local, isOn: showOnDockBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(showOnDock && !showMenubar)
            }

            CompactSettingRow(label: "Show on Menu Bar") {
                Toggle("Show on Menu Bar".local, isOn: showMenubarBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(showMenubar && !showOnDock)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = newValue
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                    print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                }
            }
        )
    }

    private var showOnDockBinding: Binding<Bool> {
        Binding(
            get: { showOnDock },
            set: { newValue in
                guard CompactRecorderPreferences.hasReachableAppEntry(
                    showOnDock: newValue,
                    showMenubar: showMenubar
                ) else { return }
                showOnDock = newValue
                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                if newValue { NSApp.activate(ignoringOtherApps: true) }
            }
        )
    }

    private var showMenubarBinding: Binding<Bool> {
        Binding(
            get: { showMenubar },
            set: { newValue in
                guard CompactRecorderPreferences.hasReachableAppEntry(
                    showOnDock: showOnDock,
                    showMenubar: newValue
                ) else { return }
                showMenubar = newValue
                updateStatusBar()
            }
        )
    }

    private func confirmDefaultOutputDirectory() {
        let defaultDirectory = NSHomeDirectory() + "/Documents/Records"
        let alert = createAlert(
            level: .informational,
            title: "Restore Default Output Folder?",
            message: String(format: "The output folder will change to:\n%@".local, defaultDirectory),
            button1: "Restore Default",
            button2: "Cancel"
        )
        if alert.runModal() == .alertFirstButtonReturn {
            saveDirectory = defaultDirectory
        }
    }

    private func updateOutputDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Select".local
        if openPanel.runModal() == .OK, let path = openPanel.url?.path {
            saveDirectory = path
        }
    }

    private func toggleHotkeys() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hotkeysExpanded.toggle()
        }
        onHotkeysExpandedChange?(hotkeysExpanded)
    }
}

private struct CompactSettingsCard<Content: View>: View {
    let title: String
    let minimumHeight: CGFloat?
    let content: Content

    init(title: String, minimumHeight: CGFloat? = 132, @ViewBuilder content: () -> Content) {
        self.title = title
        self.minimumHeight = minimumHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.local)
                .font(.system(size: 13, weight: .semibold))
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct CompactSettingRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label.local)
                .font(.system(size: 11))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }
}

private struct CompactMenuPicker<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(Selection, String)]

    private var selectionText: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.0
                } label: {
                    if selection == option.0 {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            Text(selectionText)
                .lineLimit(1)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
    }
}

private struct CoreHotkeySettingsView: View {
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: 7) {
                CoreHotkeyRow(label: "Record System Audio", name: .startWithAudio)
                CoreHotkeyRow(label: "Record Current Screen", name: .startWithScreen)
                CoreHotkeyRow(label: "Select Area to Record", name: .startWithArea)
                CoreHotkeyRow(label: "Stop Recording", name: .stop)
            }
        } else {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 7) {
                    CoreHotkeyRow(label: "Record System Audio", name: .startWithAudio)
                    CoreHotkeyRow(label: "Record Current Screen", name: .startWithScreen)
                }
                VStack(spacing: 7) {
                    CoreHotkeyRow(label: "Select Area to Record", name: .startWithArea)
                    CoreHotkeyRow(label: "Stop Recording", name: .stop)
                }
            }
        }
    }
}

private struct CoreHotkeyRow: View {
    let label: String
    let name: KeyboardShortcuts.Name

    var body: some View {
        HStack(spacing: 12) {
            Text(label.local)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            KeyboardShortcuts.Recorder("", name: name)
        }
        .frame(maxWidth: .infinity)
    }
}

extension KeyboardShortcuts.Name {
    static let startWithAudio = Self("startWithAudio", default: .init(.f2))
    static let startWithScreen = Self("startWithScreen", default: .init(.f4))
    static let startWithWindow = Self("startWithWindow")
    static let startWithArea = Self("startWithArea", default: .init(.f4, modifiers: .shift))
    static let screenMagnifier = Self("screenMagnifier")
    static let saveFrame = Self("saveFrame")
    static let pauseResume = Self("pauseResume")
    static let stop = Self("stop", default: .init(.f5))
    static let showPanel = Self("showPanel")
}

extension UserDefaults {
    func cgColor(forKey key: String) -> CGColor? {
        guard let data = data(forKey: key),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return nil
        }
        return nsColor.cgColor
    }
}
