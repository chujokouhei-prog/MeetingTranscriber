//
//  ContentView.swift
//  MeetingTranscriber
//
//  Created by 中條航平 on 2026/06/13.
//

import SwiftUI
import AVFoundation
import Speech

struct RecordingFile: Identifiable {
    let id: URL
    let name: String
    let createdAt: Date
    let url: URL
}

struct SavedTranscription: Codable {
    let text: String
    let createdAt: Date
}

final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var didFinishPlaying: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinishPlaying?()
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate = AudioPlayerDelegate()
    @State private var playingRecordingURL: URL?
    @State private var speechRecognitionTask: SFSpeechRecognitionTask?
    @State private var transcribingRecordingURL: URL?
    @State private var transcriptions: [String: SavedTranscription] = [:]
    @State private var statusMessage: String?
    @State private var recordingFiles: [RecordingFile] = []
    @State private var isShowingConsentConfirmation = false
    @State private var isShowingRenameAlert = false
    @State private var recordingFileToRename: RecordingFile?
    @State private var newRecordingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("打ち合わせ文字起こし")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(isRecording ? "録音中" : "録音待機中")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isRecording ? .red : .secondary)
            }

            Button {
                if isRecording {
                    stopRecording()
                } else {
                    isShowingConsentConfirmation = true
                }
            } label: {
                Label(isRecording ? "録音停止" : "録音開始", systemImage: isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            }
            .background(isRecording ? Color.red : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let statusMessage {
                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("録音一覧")
                    .font(.title3)
                    .fontWeight(.bold)

                if recordingFiles.isEmpty {
                    Text("まだ録音はありません")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    List(recordingFiles) { recordingFile in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(recordingTitle(for: recordingFile))
                                        .font(.headline)

                                    Text(recordingFile.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(spacing: 8) {
                                    Button(playingRecordingURL == recordingFile.url ? "停止" : "再生") {
                                        togglePlayback(for: recordingFile)
                                    }
                                    .buttonStyle(.bordered)

                                    Button(transcribingRecordingURL == recordingFile.url ? "処理中" : "文字起こし") {
                                        transcribe(recordingFile)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(transcribingRecordingURL != nil)

                                    Button("名前変更") {
                                        showRenameAlert(for: recordingFile)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            HStack(spacing: 8) {
                                if playingRecordingURL == recordingFile.url {
                                    Text("再生中")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }

                                if transcribingRecordingURL == recordingFile.url {
                                    Text("文字起こし中")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }
                            }

                            if let transcription = transcriptions[recordingFile.name] {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("文字起こし結果")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Button("コピー") {
                                            copyTranscriptionText(transcription.text)
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .disabled(transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }

                                    Text(transcription.text)
                                        .font(.body)
                                        .lineSpacing(4)

                                    Text("文字起こし日時: \(transcription.createdAt.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .padding(24)
        .onAppear {
            loadSavedTranscriptions()
            loadRecordingFiles(clearStatus: true)
        }
        .sheet(isPresented: $isShowingConsentConfirmation) {
            consentConfirmationView
        }
        .alert("録音名を変更", isPresented: $isShowingRenameAlert) {
            TextField("新しい名前", text: $newRecordingName)

            Button("保存") {
                renameSelectedRecordingFile()
            }

            Button("キャンセル", role: .cancel) {
                recordingFileToRename = nil
                newRecordingName = ""
            }
        } message: {
            Text("拡張子 .m4a は自動で付きます。")
        }
    }

    private var consentConfirmationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("録音前の確認")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                Label("この打ち合わせの音声を録音します", systemImage: "mic.fill")
                Label("録音した音声は文字起こしに使用します", systemImage: "text.bubble.fill")
                Label("保存されたデータは一定時間後に削除されます", systemImage: "clock.fill")
                Label("相手の同意を得たうえで録音を開始してください", systemImage: "person.fill.checkmark")
            }
            .font(.body)

            Spacer()

            Button {
                isShowingConsentConfirmation = false
                startRecording()
            } label: {
                Text("同意を得たので録音開始")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingConsentConfirmation = false
            } label: {
                Text("キャンセル")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecording()
                } else {
                    statusMessage = "マイクの使用が許可されていません。設定アプリでマイクの使用を許可してください。"
                }
            }
        }
    }

    private func beginRecording() {
        stopPlayback()
        cancelTranscription()

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try audioSession.setActive(true)

            let recorder = try AVAudioRecorder(url: newRecordingURL(), settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])

            guard recorder.record() else {
                audioRecorder = nil
                isRecording = false
                statusMessage = "録音を開始できませんでした。少し時間をおいて、もう一度お試しください。"
                return
            }

            audioRecorder = recorder
            isRecording = true
            statusMessage = "録音中です"
        } catch {
            debugPrint("Failed to start recording: \(error.localizedDescription)")
            audioRecorder = nil
            isRecording = false
            statusMessage = "録音を開始できませんでした。マイクの許可や端末の空き容量を確認してください。"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        statusMessage = "録音を保存しました"
        loadRecordingFiles()

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            debugPrint("Failed to deactivate audio session: \(error.localizedDescription)")
            statusMessage = "録音は保存されましたが、音声設定の終了に失敗しました。再度録音する前にアプリを開き直してください。"
        }
    }

    private func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"

        let baseFileName = "meeting_\(formatter.string(from: Date()))"
        return uniqueRecordingURL(baseFileName: baseFileName)
    }

    private func recordingTitle(for recordingFile: RecordingFile) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 H:mm"

        return "\(formatter.string(from: recordingFile.createdAt)) の録音"
    }

    private func uniqueRecordingURL(baseFileName: String) -> URL {
        let documentsFolder = documentsFolderURL()
        var fileURL = documentsFolder.appendingPathComponent("\(baseFileName).m4a")
        var number = 2

        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = documentsFolder.appendingPathComponent("\(baseFileName)_\(number).m4a")
            number += 1
        }

        return fileURL
    }

    private func showRenameAlert(for recordingFile: RecordingFile) {
        recordingFileToRename = recordingFile
        newRecordingName = recordingFile.url.deletingPathExtension().lastPathComponent
        isShowingRenameAlert = true
    }

    private func renameSelectedRecordingFile() {
        guard let recordingFile = recordingFileToRename else {
            return
        }

        let sanitizedName = sanitizedRecordingName(from: newRecordingName)

        guard !sanitizedName.isEmpty else {
            statusMessage = "録音名を入力してください。"
            return
        }

        stopPlayback()
        cancelTranscription()

        let newURL = uniqueRecordingURL(
            baseFileName: sanitizedName,
            excluding: recordingFile.url
        )
        let newFileName = newURL.lastPathComponent

        if newURL == recordingFile.url {
            recordingFileToRename = nil
            newRecordingName = ""
            statusMessage = "録音名は変更されていません"
            return
        }

        do {
            try FileManager.default.moveItem(at: recordingFile.url, to: newURL)

            if let transcription = transcriptions[recordingFile.name] {
                transcriptions[recordingFile.name] = nil
                transcriptions[newFileName] = transcription
                saveTranscriptions()
            }

            recordingFileToRename = nil
            newRecordingName = ""
            statusMessage = "録音名を変更しました"
            loadRecordingFiles()
        } catch {
            debugPrint("Failed to rename recording file: \(error.localizedDescription)")
            statusMessage = "録音名を変更できませんでした。もう一度お試しください。"
        }
    }

    private func sanitizedRecordingName(from name: String) -> String {
        var sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedName.lowercased().hasSuffix(".m4a") {
            sanitizedName.removeLast(4)
            sanitizedName = sanitizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let unsafeCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)

        return sanitizedName
            .components(separatedBy: unsafeCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private func uniqueRecordingURL(baseFileName: String, excluding excludedURL: URL) -> URL {
        let documentsFolder = documentsFolderURL()
        var fileURL = documentsFolder.appendingPathComponent("\(baseFileName).m4a")
        var number = 2

        while FileManager.default.fileExists(atPath: fileURL.path) && fileURL != excludedURL {
            fileURL = documentsFolder.appendingPathComponent("\(baseFileName)_\(number).m4a")
            number += 1
        }

        return fileURL
    }

    private func loadRecordingFiles(clearStatus: Bool = false) {
        do {
            deleteOldRecordingFiles()

            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsFolderURL(),
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            recordingFiles = fileURLs
                .filter { $0.pathExtension.lowercased() == "m4a" }
                .compactMap { fileURL in
                    let values = try? fileURL.resourceValues(forKeys: [.creationDateKey])

                    guard let createdAt = values?.creationDate else {
                        return nil
                    }

                    return RecordingFile(
                        id: fileURL,
                        name: fileURL.lastPathComponent,
                        createdAt: createdAt,
                        url: fileURL
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }

            let recordingFileNames = Set(recordingFiles.map(\.name))
            deleteOldTranscriptionResults(recordingFileNames: recordingFileNames)

            if clearStatus {
                statusMessage = nil
            }
        } catch {
            statusMessage = "録音ファイルを読み込めませんでした"
        }
    }

    private func togglePlayback(for recordingFile: RecordingFile) {
        if playingRecordingURL == recordingFile.url {
            stopPlayback()
        } else {
            startPlayback(for: recordingFile)
        }
    }

    private func startPlayback(for recordingFile: RecordingFile) {
        do {
            stopPlayback()
            try configureAudioSessionForPlayback()

            let player = try AVAudioPlayer(contentsOf: recordingFile.url)
            audioPlayerDelegate.didFinishPlaying = {
                DispatchQueue.main.async {
                    audioPlayer = nil
                    playingRecordingURL = nil
                }
            }
            player.delegate = audioPlayerDelegate

            guard player.play() else {
                statusMessage = "音声を再生できませんでした。録音ファイルが壊れている可能性があります。"
                return
            }

            audioPlayer = player
            playingRecordingURL = recordingFile.url
            statusMessage = nil
        } catch {
            debugPrint("Failed to play audio: \(error.localizedDescription)")
            statusMessage = "音声を再生できませんでした。録音ファイルが見つからないか、読み込めない可能性があります。"
        }
    }

    private func configureAudioSessionForPlayback() throws {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playback,
            mode: .default,
            options: [.defaultToSpeaker]
        )
        try audioSession.overrideOutputAudioPort(.speaker)
        try audioSession.setActive(true)
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordingURL = nil
    }

    private func copyTranscriptionText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            statusMessage = "コピーできる文字起こし結果がありません。"
            return
        }

        UIPasteboard.general.string = trimmedText
        statusMessage = "コピーしました"
    }

    private func transcribe(_ recordingFile: RecordingFile) {
        stopPlayback()
        cancelTranscription()

        transcribingRecordingURL = recordingFile.url
        statusMessage = nil

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    startSpeechRecognition(for: recordingFile)
                case .denied:
                    transcribingRecordingURL = nil
                    statusMessage = "音声認識の使用が許可されていません。設定アプリで音声認識を許可してください。"
                case .restricted:
                    transcribingRecordingURL = nil
                    statusMessage = "この端末では音声認識を使用できません。端末や利用制限の設定を確認してください。"
                case .notDetermined:
                    transcribingRecordingURL = nil
                    statusMessage = "音声認識の許可を確認できませんでした。もう一度「文字起こし」を押してください。"
                @unknown default:
                    transcribingRecordingURL = nil
                    statusMessage = "音声認識を開始できませんでした。しばらくしてからもう一度お試しください。"
                }
            }
        }
    }

    private func startSpeechRecognition(for recordingFile: RecordingFile) {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja_JP")) else {
            transcribingRecordingURL = nil
            statusMessage = "日本語の音声認識を使用できません。端末の言語設定や音声認識の利用状況を確認してください。"
            return
        }

        guard speechRecognizer.isAvailable else {
            transcribingRecordingURL = nil
            statusMessage = "現在、音声認識を使用できません。通信状態や端末の状態を確認して、時間をおいて再試行してください。"
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: recordingFile.url)
        request.shouldReportPartialResults = true

        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let result {
                    transcriptions[recordingFile.name] = SavedTranscription(
                        text: result.bestTranscription.formattedString,
                        createdAt: Date()
                    )

                    if result.isFinal {
                        saveTranscriptions()
                        speechRecognitionTask = nil
                        transcribingRecordingURL = nil
                    }
                }

                if error != nil {
                    speechRecognitionTask = nil
                    transcribingRecordingURL = nil

                    if transcriptions[recordingFile.name] == nil {
                        statusMessage = "文字起こしに失敗しました。録音の音量や周囲の雑音を確認して、もう一度お試しください。"
                    }
                }
            }
        }
    }

    private func cancelTranscription() {
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil
        transcribingRecordingURL = nil
    }

    private func loadSavedTranscriptions() {
        guard let data = UserDefaults.standard.data(forKey: "savedTranscriptions") else {
            return
        }

        do {
            transcriptions = try JSONDecoder().decode([String: SavedTranscription].self, from: data)
        } catch {
            statusMessage = "保存済みの文字起こし結果を読み込めませんでした"
        }
    }

    private func saveTranscriptions() {
        do {
            let data = try JSONEncoder().encode(transcriptions)
            UserDefaults.standard.set(data, forKey: "savedTranscriptions")
        } catch {
            statusMessage = "文字起こし結果を保存できませんでした"
        }
    }

    private func deleteOldTranscriptionResults(recordingFileNames: Set<String>) {
        let now = Date()
        let oneDay: TimeInterval = 24 * 60 * 60
        var updatedTranscriptions = transcriptions

        for (recordingFileName, transcription) in transcriptions {
            let isRecordingFileDeleted = !recordingFileNames.contains(recordingFileName)
            let isOlderThanOneDay = now.timeIntervalSince(transcription.createdAt) >= oneDay

            if isRecordingFileDeleted || isOlderThanOneDay {
                updatedTranscriptions[recordingFileName] = nil

                if isRecordingFileDeleted {
                    debugPrint("Deleted transcription because recording file is missing: \(recordingFileName)")
                } else {
                    debugPrint("Deleted old transcription: \(recordingFileName)")
                }
            }
        }

        if updatedTranscriptions.count != transcriptions.count {
            transcriptions = updatedTranscriptions
            saveTranscriptions()
        }
    }

    private func deleteOldRecordingFiles() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsFolderURL(),
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            let now = Date()
            let oneDay: TimeInterval = 24 * 60 * 60

            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "m4a" {
                let values = try fileURL.resourceValues(forKeys: [.creationDateKey])

                guard let createdAt = values.creationDate else {
                    continue
                }

                if now.timeIntervalSince(createdAt) >= oneDay {
                    try FileManager.default.removeItem(at: fileURL)
                    debugPrint("Deleted old recording file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            debugPrint("Failed to delete old recording files: \(error.localizedDescription)")
        }
    }

    private func documentsFolderURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }
}

#Preview {
    ContentView()
}
