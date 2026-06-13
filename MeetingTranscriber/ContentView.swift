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

    var body: some View {
        VStack {
            Text("打ち合わせ文字起こし")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Button(isRecording ? "録音停止" : "録音開始") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .font(.title)
            .fontWeight(.bold)
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let statusMessage {
                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            }

            if recordingFiles.isEmpty {
                Text("まだ録音はありません")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, statusMessage == nil ? 24 : 8)

                Spacer()
            } else {
                List(recordingFiles) { recordingFile in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recordingFile.name)
                                .font(.headline)

                            Text(recordingFile.createdAt.formatted(date: .numeric, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if playingRecordingURL == recordingFile.url {
                                Text("再生中")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }

                            if transcribingRecordingURL == recordingFile.url {
                                Text("文字起こし中")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }

                            if let transcription = transcriptions[recordingFile.name] {
                                Text(transcription.text)
                                    .font(.subheadline)
                                    .padding(.top, 6)

                                Text("文字起こし日時: \(transcription.createdAt.formatted(date: .numeric, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Button(playingRecordingURL == recordingFile.url ? "停止" : "再生") {
                                togglePlayback(for: recordingFile)
                            }
                            .buttonStyle(.bordered)

                            Button(transcribingRecordingURL == recordingFile.url ? "文字起こし中" : "文字起こし") {
                                transcribe(recordingFile)
                            }
                            .buttonStyle(.bordered)
                            .disabled(transcribingRecordingURL != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(32)
        .onAppear {
            loadSavedTranscriptions()
            loadRecordingFiles(clearStatus: true)
        }
    }

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecording()
                } else {
                    statusMessage = "マイクの使用が許可されていません"
                }
            }
        }
    }

    private func beginRecording() {
        stopPlayback()
        cancelTranscription()

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let recorder = try AVAudioRecorder(url: newRecordingURL(), settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])

            recorder.record()
            audioRecorder = recorder
            isRecording = true
            statusMessage = "録音中です"
        } catch {
            statusMessage = "録音を開始できませんでした"
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
            statusMessage = "録音は停止しましたが、音声設定の終了に失敗しました"
        }
    }

    private func newRecordingURL() -> URL {
        let fileName = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
        return documentsFolderURL().appendingPathComponent(fileName)
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

            let player = try AVAudioPlayer(contentsOf: recordingFile.url)
            audioPlayerDelegate.didFinishPlaying = {
                DispatchQueue.main.async {
                    audioPlayer = nil
                    playingRecordingURL = nil
                }
            }
            player.delegate = audioPlayerDelegate
            player.play()

            audioPlayer = player
            playingRecordingURL = recordingFile.url
            statusMessage = nil
        } catch {
            statusMessage = "音声を再生できませんでした"
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingRecordingURL = nil
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
                    statusMessage = "音声認識の使用が許可されていません"
                case .restricted:
                    transcribingRecordingURL = nil
                    statusMessage = "この端末では音声認識を使用できません"
                case .notDetermined:
                    transcribingRecordingURL = nil
                    statusMessage = "音声認識の許可を確認できませんでした"
                @unknown default:
                    transcribingRecordingURL = nil
                    statusMessage = "音声認識を開始できませんでした"
                }
            }
        }
    }

    private func startSpeechRecognition(for recordingFile: RecordingFile) {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja_JP")) else {
            transcribingRecordingURL = nil
            statusMessage = "日本語の音声認識を使用できません"
            return
        }

        guard speechRecognizer.isAvailable else {
            transcribingRecordingURL = nil
            statusMessage = "現在、音声認識を使用できません"
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
                        statusMessage = "文字起こしに失敗しました"
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
