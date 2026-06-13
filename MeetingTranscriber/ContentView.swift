//
//  ContentView.swift
//  MeetingTranscriber
//
//  Created by 中條航平 on 2026/06/13.
//

import SwiftUI
import AVFoundation

struct RecordingFile: Identifiable {
    let id = UUID()
    let name: String
    let createdAt: Date
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recordingFile.name)
                            .font(.headline)

                        Text(recordingFile.createdAt.formatted(date: .numeric, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(32)
        .onAppear {
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
        let documentsFolder = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let fileName = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
        return documentsFolder.appendingPathComponent(fileName)
    }

    private func loadRecordingFiles(clearStatus: Bool = false) {
        do {
            let documentsFolder = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsFolder,
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
                        name: fileURL.lastPathComponent,
                        createdAt: createdAt
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }

            if clearStatus {
                statusMessage = nil
            }
        } catch {
            statusMessage = "録音ファイルを読み込めませんでした"
        }
    }
}

#Preview {
    ContentView()
}
