import AppKit
import AVFoundation
import Foundation
import SpeakerKit
import UserNotifications
import WhisperKit

enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic
    case chinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Auto Detect".local
        case .chinese: return "Chinese".local
        case .english: return "English".local
        }
    }

    var whisperLanguageCode: String? {
        switch self {
        case .automatic: return nil
        case .chinese: return "zh"
        case .english: return "en"
        }
    }
}

enum TranscriptionTaskStatus: String, Codable {
    case queued
    case waitingForModel
    case transcribing
    case failed
    case cancelled
}

struct TranscriptionTaskRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sourcePath: String
    let createdAt: Date
    var language: TranscriptionLanguage
    var status: TranscriptionTaskStatus
    var retryCount: Int
    var lastError: String?

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var displayName: String { sourceURL.lastPathComponent }
}

struct TranscriptSegment: Sendable, Equatable {
    let start: Float
    let end: Float
    let text: String
}

struct SpeakerTranscriptSegment: Sendable, Equatable {
    let start: Float
    let end: Float
    let speaker: String
    let text: String
}

enum SpeakerTranscriptFormatter {
    static func text(for segments: [SpeakerTranscriptSegment]) -> String {
        let visibleSegments = segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return visibleSegments.map { segment in
                let content = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return "[\(timestamp(segment.start)) - \(timestamp(segment.end))] Speaker \(segment.speaker): \(content)"
            }
            .joined(separator: "\n\n") + (visibleSegments.isEmpty ? "" : "\n")
    }

    private static func timestamp(_ seconds: Float) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
    }
}

enum TranscriptionModelStatus: Equatable {
    case notDownloaded
    case downloading
    case ready
    case loading
    case failed(String)

    var label: String {
        switch self {
        case .notDownloaded: return "Not Downloaded".local
        case .downloading: return "Downloading".local
        case .ready: return "Ready".local
        case .loading: return "Loading".local
        case .failed: return "Download Failed".local
        }
    }
}

enum TranscriptionFailure: LocalizedError {
    case sourceMissing
    case outputDirectoryUnavailable
    case noAudioTrack
    case modelMissing
    case emptyAudio
    case speakerDiarizationEmpty
    case incompleteSidecarCommit

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "The recording file no longer exists.".local
        case .outputDirectoryUnavailable:
            return "The recording folder is not writable.".local
        case .noAudioTrack:
            return "No audio track was found in the recording.".local
        case .modelMissing:
            return "The transcription model has not been downloaded.".local
        case .emptyAudio:
            return "The recording contains no readable audio.".local
        case .speakerDiarizationEmpty:
            return "No speaker labels could be generated for this recording.".local
        case .incompleteSidecarCommit:
            return "Could not save the transcript files.".local
        }
    }

    var shouldRetryAutomatically: Bool {
        switch self {
        case .sourceMissing, .outputDirectoryUnavailable, .noAudioTrack, .modelMissing, .emptyAudio, .speakerDiarizationEmpty, .incompleteSidecarCommit:
            return false
        }
    }
}

enum RecordingAudioPresence {
    // -60 dBFS RMS: reject silence and negligible noise without requiring speech.
    static func hasSound(in url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        for track in tracks {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard reader.canAdd(output) else { throw TranscriptionFailure.emptyAudio }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? TranscriptionFailure.emptyAudio }
            defer { reader.cancelReading() }
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                let audible = try autoreleasepool { () throws -> Bool in
                    guard let block = CMSampleBufferGetDataBuffer(sample) else {
                        throw TranscriptionFailure.emptyAudio
                    }
                    let length = CMBlockBufferGetDataLength(block)
                    guard length > 0 else { return false }
                    guard length.isMultiple(of: MemoryLayout<Float>.size) else {
                        throw TranscriptionFailure.emptyAudio
                    }
                    var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
                    let status = values.withUnsafeMutableBytes { bytes in
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                    }
                    guard status == kCMBlockBufferNoErr else { throw TranscriptionFailure.emptyAudio }
                    let energy = values.reduce(0.0) { $0 + Double($1) * Double($1) }
                    return energy / Double(values.count) > 0.000001
                }
                if audible { return true }
            }
            guard reader.status == .completed else { throw reader.error ?? TranscriptionFailure.emptyAudio }
        }
        return false
    }
}

enum TranscriptSidecarWriter {
    static func availableURLs(for sourceURL: URL, fileManager: FileManager = .default) -> (txt: URL, srt: URL?) {
        let directory = sourceURL.deletingLastPathComponent()
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let includesSRT = ["m4a", "mp3", "mp4", "mov"].contains(sourceURL.pathExtension.lowercased())
        var suffix = 0

        while true {
            let candidate = suffix == 0 ? basename : "\(basename)-\(suffix)"
            let txt = directory.appendingPathComponent(candidate).appendingPathExtension("txt")
            let srt = includesSRT ? directory.appendingPathComponent(candidate).appendingPathExtension("srt") : nil
            if !fileManager.fileExists(atPath: txt.path), srt.map({ !fileManager.fileExists(atPath: $0.path) }) ?? true {
                return (txt, srt)
            }
            suffix += 1
        }
    }

    static func srtText(for segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.start)) --> \(srtTimestamp(segment.end))
            \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }
        .joined(separator: "\n\n") + (segments.isEmpty ? "" : "\n")
    }

    static func write(
        sourceURL: URL,
        text: String,
        segments: [TranscriptSegment],
        fileManager: FileManager = .default
    ) throws -> (txt: URL, srt: URL?) {
        let targets = availableURLs(for: sourceURL, fileManager: fileManager)
        let directory = sourceURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw TranscriptionFailure.outputDirectoryUnavailable
        }

        let token = UUID().uuidString
        let temporaryTXT = directory.appendingPathComponent(".quickrecorder-\(token).txt.tmp")
        let temporarySRT = targets.srt.map { _ in
            directory.appendingPathComponent(".quickrecorder-\(token).srt.tmp")
        }
        var committedTXT = false

        defer {
            try? fileManager.removeItem(at: temporaryTXT)
            if let temporarySRT {
                try? fileManager.removeItem(at: temporarySRT)
            }
        }

        try Data(text.utf8).write(to: temporaryTXT, options: .atomic)
        if let temporarySRT {
            try Data(srtText(for: segments).utf8).write(to: temporarySRT, options: .atomic)
        }

        do {
            try fileManager.moveItem(at: temporaryTXT, to: targets.txt)
            committedTXT = true
            if let temporarySRT, let targetSRT = targets.srt {
                try fileManager.moveItem(at: temporarySRT, to: targetSRT)
            }
            return targets
        } catch {
            if committedTXT {
                try? fileManager.removeItem(at: targets.txt)
            }
            throw TranscriptionFailure.incompleteSidecarCommit
        }
    }

    private static func srtTimestamp(_ value: Float) -> String {
        let milliseconds = max(0, Int((value * 1_000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1_000) % 60
        let remainder = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, remainder)
    }
}

@MainActor
final class TranscriptionStore: ObservableObject {
    static let shared = TranscriptionStore()

    nonisolated static let autoTranscribeKey = "autoTranscribe"
    nonisolated static let languageKey = "transcriptionLanguage"
    nonisolated static let modelPathKey = "transcriptionModelPath"
    nonisolated static let modelName = "openai_whisper-large-v3-v20240930_626MB"
    nonisolated static let modelVariant = "large-v3-v20240930_626MB"
    nonisolated static let approximateModelSize = "637 MB"

    @Published private(set) var tasks: [TranscriptionTaskRecord] = []
    @Published private(set) var currentTaskID: UUID?
    @Published private(set) var progress: Double = 0
    @Published private(set) var modelStatus: TranscriptionModelStatus = .notDownloaded
    @Published private(set) var downloadProgress: Double = 0

    private var started = false
    private var thermalObserver: NSObjectProtocol?

    private init() {}

    var currentTask: TranscriptionTaskRecord? {
        tasks.first(where: { $0.id == currentTaskID })
    }

    var waitingCount: Int {
        tasks.filter { $0.status == .queued || $0.status == .waitingForModel }.count
    }

    var retainedIssues: [TranscriptionTaskRecord] {
        tasks.filter { $0.status == .failed || $0.status == .cancelled }
    }

    func start() {
        guard !started else { return }
        started = true
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: ProcessInfo.processInfo,
            queue: .main
        ) { _ in
            Task {
                await TranscriptionCoordinator.shared.resumeIfPossible()
            }
        }
        Task {
            if ud.bool(forKey: Self.autoTranscribeKey) {
                await TranscriptionCoordinator.shared.downloadModel()
            } else {
                await TranscriptionCoordinator.shared.bootstrap()
            }
        }
    }

    func setAutomaticTranscription(_ enabled: Bool) {
        ud.set(enabled, forKey: Self.autoTranscribeKey)
        if enabled {
            downloadModel()
        }
    }

    func downloadModel() {
        Task {
            await TranscriptionCoordinator.shared.downloadModel()
        }
    }

    func cancelModelDownload() {
        Task {
            await TranscriptionCoordinator.shared.cancelModelDownload()
        }
    }

    func deleteModel() {
        Task {
            await TranscriptionCoordinator.shared.deleteModel()
        }
    }

    func cancelCurrentTask() {
        guard let currentTaskID else { return }
        Task {
            await TranscriptionCoordinator.shared.cancel(id: currentTaskID)
        }
    }

    func retry(_ task: TranscriptionTaskRecord) {
        Task {
            await TranscriptionCoordinator.shared.retry(id: task.id)
        }
    }

    func remove(_ task: TranscriptionTaskRecord) {
        Task {
            await TranscriptionCoordinator.shared.remove(id: task.id)
        }
    }

    nonisolated static func enqueueIfEnabled(_ finalURL: URL) {
        guard ud.bool(forKey: autoTranscribeKey) else { return }
        Task {
            await TranscriptionCoordinator.shared.enqueue(finalURL: finalURL)
        }
    }

    func applySnapshot(
        tasks: [TranscriptionTaskRecord],
        currentTaskID: UUID?,
        progress: Double
    ) {
        self.tasks = tasks
        self.currentTaskID = currentTaskID
        self.progress = min(max(progress, 0), 1)
    }

    func applyModelStatus(_ status: TranscriptionModelStatus, progress: Double? = nil) {
        modelStatus = status
        if let progress {
            downloadProgress = min(max(progress, 0), 1)
        } else if status == .ready {
            downloadProgress = 1
        }
    }
}

actor WhisperTranscriptionWorker {
    static let shared = WhisperTranscriptionWorker()

    private var whisperKit: WhisperKit?
    private var speakerKit: SpeakerKit?

    func transcribe(
        audioURL: URL,
        speakerModelRoot: URL,
        language: TranscriptionLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (text: String, segments: [TranscriptSegment])? {
        try Task.checkCancellation()
        progress(0.05)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard !samples.isEmpty else { return nil }

        let vad = EnergyVAD(frameLength: 0.1, frameOverlap: 0.02)
        guard vad.voiceActivity(in: samples).contains(true) else {
            return nil
        }

        guard let modelPath = ud.string(forKey: TranscriptionStore.modelPathKey),
              fd.fileExists(atPath: modelPath) else {
            throw TranscriptionFailure.modelMissing
        }

        let kit: WhisperKit
        if let loaded = whisperKit {
            kit = loaded
        } else {
            progress(0.1)
            let config = WhisperKitConfig(
                model: TranscriptionStore.modelVariant,
                modelFolder: modelPath,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            let loaded = try await WhisperKit(config)
            whisperKit = loaded
            kit = loaded
        }

        try Task.checkCancellation()
        progress(0.3)
        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperLanguageCode,
            usePrefillPrompt: language != .automatic,
            detectLanguage: language == .automatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            concurrentWorkerCount: 1,
            chunkingStrategy: .vad
        )
        let results = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: options
        ) { update in
            progress(min(0.68, 0.35 + Double(update.windowId + 1) * 0.04))
            return !Task.isCancelled
        }
        try Task.checkCancellation()

        let textParts = results
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let segments = results
            .flatMap(\.segments)
            .map {
                TranscriptSegment(
                    start: $0.start,
                    end: $0.end,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }

        guard !textParts.isEmpty, !segments.isEmpty else {
            return nil
        }

        try Task.checkCancellation()
        progress(0.7)
        let diarizer: SpeakerKit
        if let loaded = speakerKit {
            diarizer = loaded
        } else {
            let config = PyannoteConfig(
                downloadBase: speakerModelRoot.path,
                download: true,
                load: true,
                verbose: false,
                fullRedundancy: true
            )
            let loaded = try await SpeakerKit(config)
            speakerKit = loaded
            diarizer = loaded
        }
        let diarization = try await diarizer.diarize(
            audioArray: samples,
            options: PyannoteDiarizationOptions(
                numberOfSpeakers: nil,
                useExclusiveReconciliation: true
            )
        ) { speakerProgress in
            progress(min(0.95, 0.7 + speakerProgress.fractionCompleted * 0.25))
        }
        try Task.checkCancellation()

        let speakerLines = SpeakerKit.generateRTTM(
            from: diarization,
            transcription: results,
            fileName: audioURL.deletingPathExtension().lastPathComponent
        )
        let speakerSegments = speakerLines.map { line in
            SpeakerTranscriptSegment(
                start: line.startTime,
                end: line.startTime + line.duration,
                speaker: line.speakerName,
                text: line.orthography
            )
        }
        let speakerText = SpeakerTranscriptFormatter.text(for: speakerSegments)
        guard !speakerText.isEmpty else {
            throw TranscriptionFailure.speakerDiarizationEmpty
        }
        progress(0.95)
        return (speakerText, segments)
    }

    func unload() async {
        await whisperKit?.unloadModels()
        await speakerKit?.unloadModels()
        whisperKit = nil
        speakerKit = nil
    }
}

actor TranscriptionCoordinator {
    static let shared = TranscriptionCoordinator()

    private let fileManager = FileManager.default
    private var records: [TranscriptionTaskRecord] = []
    private var processingTask: Task<Void, Never>?
    private var downloadTask: Task<URL, Error>?
    private var downloadID: UUID?
    private var idleUnloadTask: Task<Void, Never>?
    private var currentTaskID: UUID?
    private var progress: Double = 0
    private var bootstrapped = false
    private var isDeletingModel = false

    private var supportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("QuickRecorder/Transcription", isDirectory: true)
    }

    private var queueURL: URL {
        supportDirectory.appendingPathComponent("queue.json")
    }

    private var modelRoot: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    private var temporaryRoot: URL {
        supportDirectory.appendingPathComponent("Temp", isDirectory: true)
    }

    private var speakerModelRoot: URL {
        supportDirectory.appendingPathComponent("SpeakerModels", isDirectory: true)
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        do {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            records = try loadRecords()
            for index in records.indices where records[index].status == .transcribing {
                records[index].status = .queued
                records[index].lastError = nil
            }
            let hasModel = installedModelURL() != nil
            for index in records.indices where records[index].status == .waitingForModel && hasModel {
                records[index].status = .queued
            }
            for index in records.indices where records[index].status == .queued && !hasModel {
                records[index].status = .waitingForModel
            }
            try persist()
        } catch {
            print("Failed to restore transcription queue: \(error.localizedDescription)")
            records = []
        }

        let modelReady = installedModelURL() != nil
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(modelReady ? .ready : .notDownloaded)
        }
        await publish()
        scheduleProcessing()
    }

    func enqueue(finalURL: URL) async {
        if !bootstrapped { await bootstrap() }
        guard ["m4a", "mp3", "mp4", "mov"].contains(finalURL.pathExtension.lowercased()),
              fileManager.fileExists(atPath: finalURL.path),
              !records.contains(where: { $0.sourcePath == finalURL.path }) else { return }
        do {
            let containsSound = try await Task.detached(priority: .utility) {
                try await RecordingAudioPresence.hasSound(in: finalURL)
            }.value
            guard containsSound else { return }
        } catch {
            // A decoding failure is not proof of silence. Preserve normal queue error handling.
            NSLog("Audio presence check failed: %@", error.localizedDescription)
        }
        // Another completion callback may have enqueued this file while we scanned it.
        guard !records.contains(where: { $0.sourcePath == finalURL.path }) else { return }
        let rawLanguage = ud.string(forKey: TranscriptionStore.languageKey)
        let language = TranscriptionLanguage(rawValue: rawLanguage ?? "") ?? .automatic
        records.append(
            TranscriptionTaskRecord(
                id: UUID(),
                sourcePath: finalURL.path,
                createdAt: Date(),
                language: language,
                status: installedModelURL() == nil ? .waitingForModel : .queued,
                retryCount: 0,
                lastError: nil
            )
        )
        try? persist()
        await publish()
        scheduleProcessing()
    }

    func downloadModel() async {
        if !bootstrapped { await bootstrap() }
        if installedModelURL() != nil {
            await MainActor.run {
                TranscriptionStore.shared.applyModelStatus(.ready)
            }
            scheduleProcessing()
            return
        }
        guard downloadTask == nil else { return }

        let operationID = UUID()
        downloadID = operationID
        do {
            try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true)
            await MainActor.run {
                TranscriptionStore.shared.applyModelStatus(.downloading, progress: 0)
            }
            let task = Task(priority: .utility) {
                try await WhisperKit.download(
                    variant: TranscriptionStore.modelVariant,
                    downloadBase: self.modelRoot,
                    useBackgroundSession: true
                ) { modelProgress in
                    Task {
                        await self.updateDownloadProgress(
                            modelProgress.fractionCompleted,
                            operationID: operationID
                        )
                    }
                }
            }
            downloadTask = task
            let folder = try await task.value
            guard downloadID == operationID else { return }
            downloadID = nil
            downloadTask = nil
            guard isValidModelFolder(folder) else {
                throw TranscriptionFailure.modelMissing
            }
            ud.set(folder.path, forKey: TranscriptionStore.modelPathKey)
            for index in records.indices where records[index].status == .waitingForModel {
                records[index].status = .queued
            }
            try persist()
            await MainActor.run {
                TranscriptionStore.shared.applyModelStatus(.ready)
            }
            await publish()
            scheduleProcessing()
        } catch is CancellationError {
            guard downloadID == operationID else { return }
            downloadID = nil
            downloadTask = nil
            await MainActor.run {
                TranscriptionStore.shared.applyModelStatus(.notDownloaded, progress: 0)
            }
        } catch {
            guard downloadID == operationID else { return }
            downloadID = nil
            downloadTask = nil
            await MainActor.run {
                TranscriptionStore.shared.applyModelStatus(.failed(error.localizedDescription))
            }
        }
    }

    func cancelModelDownload() async {
        downloadTask?.cancel()
        downloadID = nil
        downloadTask = nil
        let modelStatus: TranscriptionModelStatus = installedModelURL() == nil ? .notDownloaded : .ready
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(
                modelStatus,
                progress: 0
            )
        }
    }

    func deleteModel() async {
        isDeletingModel = true
        downloadTask?.cancel()
        downloadID = nil
        downloadTask = nil
        let activeProcessingTask = processingTask
        activeProcessingTask?.cancel()
        await activeProcessingTask?.value
        await WhisperTranscriptionWorker.shared.unload()

        for index in records.indices where records[index].status == .transcribing || records[index].status == .queued {
            records[index].status = .waitingForModel
        }
        try? fileManager.removeItem(at: modelRoot)
        try? fileManager.removeItem(at: speakerModelRoot)
        ud.removeObject(forKey: TranscriptionStore.modelPathKey)
        ud.set(false, forKey: TranscriptionStore.autoTranscribeKey)
        try? persist()
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(.notDownloaded, progress: 0)
        }
        await publish()
        isDeletingModel = false
    }

    func cancel(id: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = .cancelled
        records[index].lastError = "Cancelled by user".local
        if currentTaskID == id {
            processingTask?.cancel()
        }
        try? persist()
        await publish()
    }

    func retry(id: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = installedModelURL() == nil ? .waitingForModel : .queued
        records[index].retryCount = 0
        records[index].lastError = nil
        try? persist()
        await publish()
        scheduleProcessing()
    }

    func remove(id: UUID) async {
        guard id != currentTaskID else { return }
        records.removeAll(where: { $0.id == id })
        try? persist()
        await publish()
    }

    func resumeIfPossible() {
        scheduleProcessing()
    }

    func suspendForRecording() {
        processingTask?.cancel()
    }

    private func scheduleProcessing() {
        guard processingTask == nil,
              !isDeletingModel,
              !SCContext.isRecordingActive,
              installedModelURL() != nil,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical,
              records.contains(where: { $0.status == .queued }) else {
            return
        }

        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        processingTask = Task(priority: .utility) {
            await self.processNext()
        }
    }

    private func processNext() async {
        guard let index = records.firstIndex(where: { $0.status == .queued }) else {
            finishProcessingCycle()
            return
        }

        let record = records[index]
        currentTaskID = record.id
        progress = 0
        records[index].status = .transcribing
        records[index].lastError = nil
        try? persist()
        await publish()
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(.loading)
        }

        do {
            try Task.checkCancellation()
            guard fileManager.fileExists(atPath: record.sourcePath) else {
                throw TranscriptionFailure.sourceMissing
            }
            guard fileManager.isWritableFile(atPath: record.sourceURL.deletingLastPathComponent().path) else {
                throw TranscriptionFailure.outputDirectoryUnavailable
            }

            let taskTemporaryDirectory = temporaryRoot.appendingPathComponent(record.id.uuidString, isDirectory: true)
            try? fileManager.removeItem(at: taskTemporaryDirectory)
            try fileManager.createDirectory(at: taskTemporaryDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: taskTemporaryDirectory) }

            let audioURL = try await audioURL(for: record.sourceURL, temporaryDirectory: taskTemporaryDirectory)
            let result = try await WhisperTranscriptionWorker.shared.transcribe(
                audioURL: audioURL,
                speakerModelRoot: speakerModelRoot,
                language: record.language
            ) { value in
                Task {
                    await self.updateProgress(value, taskID: record.id)
                }
            }
            try Task.checkCancellation()

            if let result {
                let urls = try TranscriptSidecarWriter.write(
                    sourceURL: record.sourceURL,
                    text: result.text,
                    segments: result.segments
                )
                TranscriptionNotifications.sendSuccess(sourceURL: record.sourceURL, textURL: urls.txt)
            } else {
                TranscriptionNotifications.sendNoSpeech(sourceURL: record.sourceURL)
            }

            records.removeAll(where: { $0.id == record.id })
        } catch TranscriptionFailure.noAudioTrack {
            records.removeAll(where: { $0.id == record.id })
        } catch is CancellationError {
            if let currentIndex = records.firstIndex(where: { $0.id == record.id }),
               records[currentIndex].status != .cancelled {
                records[currentIndex].status = .queued
            }
        } catch {
            await handleFailure(error, for: record)
        }

        try? persist()
        currentTaskID = nil
        progress = 0
        processingTask = nil
        let modelReady = installedModelURL() != nil
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(modelReady ? .ready : .notDownloaded)
        }
        await publish()
        scheduleProcessing()
        scheduleModelUnloadIfIdle()
    }

    private func handleFailure(_ error: Error, for record: TranscriptionTaskRecord) async {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        if records[index].status == .cancelled { return }

        let shouldRetry: Bool
        if let failure = error as? TranscriptionFailure {
            shouldRetry = failure.shouldRetryAutomatically
        } else if let cocoaError = error as? CocoaError {
            shouldRetry = ![
                CocoaError.Code.fileWriteOutOfSpace,
                .fileWriteNoPermission,
                .fileWriteVolumeReadOnly
            ].contains(cocoaError.code)
        } else {
            shouldRetry = true
        }

        if shouldRetry, records[index].retryCount < 1 {
            records[index].retryCount += 1
            records[index].status = .queued
            records[index].lastError = nil
        } else {
            records[index].status = .failed
            records[index].lastError = error.localizedDescription
            TranscriptionNotifications.sendFailure(sourceURL: record.sourceURL, error: error)
        }
    }

    private func audioURL(for sourceURL: URL, temporaryDirectory: URL) async throws -> URL {
        let videoExtensions = Set(["mp4", "mov"])
        guard videoExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            return sourceURL
        }

        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw TranscriptionFailure.noAudioTrack }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionFailure.noAudioTrack
        }
        let outputURL = temporaryDirectory.appendingPathComponent("audio.m4a")
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        try await LegacyAssetExportJob(session: exporter).run()
        return outputURL
    }

    private func updateProgress(_ value: Double, taskID: UUID) async {
        guard currentTaskID == taskID else { return }
        progress = value
        await publish()
    }

    private func updateDownloadProgress(_ value: Double, operationID: UUID) async {
        guard downloadID == operationID else { return }
        await MainActor.run {
            TranscriptionStore.shared.applyModelStatus(.downloading, progress: value)
        }
    }

    private func finishProcessingCycle() {
        currentTaskID = nil
        progress = 0
        processingTask = nil
        scheduleModelUnloadIfIdle()
    }

    private func scheduleModelUnloadIfIdle() {
        guard !records.contains(where: { $0.status == .queued || $0.status == .transcribing }) else { return }
        idleUnloadTask?.cancel()
        idleUnloadTask = Task(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(600))
                await WhisperTranscriptionWorker.shared.unload()
            } catch {
                return
            }
        }
    }

    private func installedModelURL() -> URL? {
        guard let path = ud.string(forKey: TranscriptionStore.modelPathKey),
              fileManager.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        return isValidModelFolder(url) ? url : nil
    }

    private func isValidModelFolder(_ url: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        var components = Set<String>()
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if name.hasPrefix("MelSpectrogram") {
                components.insert("mel")
            } else if name.hasPrefix("AudioEncoder") {
                components.insert("encoder")
            } else if name.hasPrefix("TextDecoder") {
                components.insert("decoder")
            }
            if components.count == 3 { return true }
        }
        return false
    }

    private func loadRecords() throws -> [TranscriptionTaskRecord] {
        guard fileManager.fileExists(atPath: queueURL.path) else { return [] }
        return try JSONDecoder().decode([TranscriptionTaskRecord].self, from: Data(contentsOf: queueURL))
    }

    private func persist() throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: queueURL, options: .atomic)
    }

    private func publish() async {
        let snapshot = records
        let activeID = currentTaskID
        let activeProgress = progress
        await MainActor.run {
            TranscriptionStore.shared.applySnapshot(
                tasks: snapshot,
                currentTaskID: activeID,
                progress: activeProgress
            )
        }
    }
}

enum TranscriptionNotifications {
    static let categoryIdentifier = "QUICKRECORDER_TRANSCRIPTION"
    static let copyActionIdentifier = "COPY_TRANSCRIPT"
    static let finderActionIdentifier = "SHOW_TRANSCRIPT_IN_FINDER"
    static let textPathKey = "textPath"

    static func configure() {
        let copy = UNNotificationAction(
            identifier: copyActionIdentifier,
            title: "Copy Text".local
        )
        let finder = UNNotificationAction(
            identifier: finderActionIdentifier,
            title: "Show in Finder".local
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [copy, finder],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func sendSuccess(sourceURL: URL, textURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Completed".local
        content.body = sourceURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [textPathKey: textURL.path]
        send(content, identifier: "quickrecorder.transcription.completed.\(UUID().uuidString)")
    }

    static func sendNoSpeech(sourceURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "No Speech Detected".local
        content.body = sourceURL.lastPathComponent
        content.sound = .default
        send(content, identifier: "quickrecorder.transcription.nospeech.\(UUID().uuidString)")
    }

    static func sendFailure(sourceURL: URL, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Failed".local
        content.body = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
        content.sound = .default
        send(content, identifier: "quickrecorder.transcription.failed.\(UUID().uuidString)")
    }

    private static func send(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Transcription notification failed: \(error.localizedDescription)")
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let path = response.notification.request.content.userInfo[TranscriptionNotifications.textPathKey] as? String else {
            return
        }
        let url = URL(fileURLWithPath: path)
        switch response.actionIdentifier {
        case TranscriptionNotifications.copyActionIdentifier:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case TranscriptionNotifications.finderActionIdentifier:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        default:
            NSWorkspace.shared.open(url)
        }
    }
}
