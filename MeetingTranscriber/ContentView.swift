//
//  ContentView.swift
//  MeetingTranscriber
//
//  Created by 中條航平 on 2026/06/13.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var recordingFileStore = RecordingFileStore()
    @StateObject private var audioRecorder = AudioRecorderManager()
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var speechTranscriber = SpeechTranscriber()
    @StateObject private var transcriptionStore = TranscriptionStore()

    @State private var statusMessage: String?
    @State private var isShowingConsentConfirmation = false
    @State private var isShowingRenameAlert = false
    @State private var recordingFileToRename: RecordingFile?
    @State private var newRecordingName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(audioRecorder.isRecording ? "録音中" : "録音待機中", systemImage: audioRecorder.isRecording ? "record.circle.fill" : "mic.circle")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(audioRecorder.isRecording ? .red : .secondary)

                            Spacer()
                        }

                        Button {
                            if audioRecorder.isRecording {
                                stopRecording()
                            } else {
                                isShowingConsentConfirmation = true
                            }
                        } label: {
                            Label(audioRecorder.isRecording ? "録音停止" : "録音開始", systemImage: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title3)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(audioRecorder.isRecording ? .red : .accentColor)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("録音一覧") {
                    if recordingFileStore.recordingFiles.isEmpty {
                        Text("まだ録音はありません")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(recordingFileStore.recordingFiles) { recordingFile in
                            NavigationLink {
                                recordingDetailView(
                                    recordingID: recordingFile.id,
                                    fallbackRecordingFile: recordingFile
                                )
                            } label: {
                                recordingRow(for: recordingFile)
                            }
                        }
                    }
                }
            }
            .navigationTitle("打ち合わせ文字起こし")
            .listStyle(.insetGrouped)
            .onAppear {
                loadInitialData()
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
    }

    private func recordingRow(for recordingFile: RecordingFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recordingFile.title)
                .font(.headline)

            Text(recordingFile.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if audioPlayer.playingRecordingURL == recordingFile.url {
                    statusBadge("再生中", color: .blue)
                }

                if speechTranscriber.transcribingRecordingURL == recordingFile.url {
                    statusBadge("文字起こし中", color: .orange)
                }

                if transcriptionStore.transcription(for: recordingFile) != nil {
                    statusBadge("文字起こし済み", color: .green)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func recordingDetailView(recordingID: String, fallbackRecordingFile: RecordingFile) -> some View {
        let recordingFile = recordingFileStore.recordingFiles.first { $0.id == recordingID } ?? fallbackRecordingFile

        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recordingFile.title)
                        .font(.headline)

                    Text(recordingFile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("作成日時: \(recordingFile.createdAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("操作") {
                Button {
                    togglePlayback(for: recordingFile)
                } label: {
                    Label(audioPlayer.playingRecordingURL == recordingFile.url ? "停止" : "再生", systemImage: audioPlayer.playingRecordingURL == recordingFile.url ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    transcribe(recordingFile)
                } label: {
                    Label(speechTranscriber.transcribingRecordingURL == recordingFile.url ? "処理中" : "文字起こし", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(speechTranscriber.transcribingRecordingURL != nil)

                Button {
                    showRenameAlert(for: recordingFile)
                } label: {
                    Label("名前変更", systemImage: "pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("状態") {
                if audioPlayer.playingRecordingURL == recordingFile.url {
                    statusBadge("再生中", color: .blue)
                }

                if speechTranscriber.transcribingRecordingURL == recordingFile.url {
                    statusBadge("文字起こし中", color: .orange)
                }

                if audioPlayer.playingRecordingURL != recordingFile.url && speechTranscriber.transcribingRecordingURL != recordingFile.url {
                    Text("待機中")
                        .foregroundStyle(.secondary)
                }
            }

            Section("文字起こし") {
                if let transcription = transcriptionStore.transcription(for: recordingFile) {
                    transcriptionView(transcription)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } else {
                    Text("まだ文字起こし結果はありません")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("録音詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func transcriptionView(_ transcription: SavedTranscription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文字起こし結果")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyTranscriptionText(transcription.text)
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(transcription.text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)

            Text("文字起こし日時: \(transcription.createdAt.formatted(date: .numeric, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func loadInitialData() {
        transcriptionStore.loadSavedTranscriptions()
        loadRecordingFiles(clearStatus: true)
    }

    private func loadRecordingFiles(clearStatus: Bool = false) {
        do {
            try recordingFileStore.loadRecordingFiles()
            transcriptionStore.migrateFilenameKeysIfNeeded(recordingFiles: recordingFileStore.recordingFiles)
            transcriptionStore.deleteOldTranscriptionResults(recordingFiles: recordingFileStore.recordingFiles)

            if clearStatus {
                statusMessage = nil
            }
        } catch {
            statusMessage = "録音ファイルを読み込めませんでした"
        }
    }

    private func startRecording() {
        audioPlayer.stopPlayback()
        speechTranscriber.cancelTranscription()

        audioRecorder.startRecording(to: recordingFileStore.newRecordingURL()) { result in
            switch result {
            case .success:
                statusMessage = "録音中です"
            case .failure(.microphonePermissionDenied):
                statusMessage = "マイクの使用が許可されていません。設定アプリでマイクの使用を許可してください。"
            case .failure:
                statusMessage = "録音を開始できませんでした。マイクの許可や端末の空き容量を確認してください。"
            }
        }
    }

    private func stopRecording() {
        let result = audioRecorder.stopRecording()
        statusMessage = "録音を保存しました"
        loadRecordingFiles()

        if case .failure(.audioSessionDeactivationFailed) = result {
            statusMessage = "録音は保存されましたが、音声設定の終了に失敗しました。再度録音する前にアプリを開き直してください。"
        }
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

        audioPlayer.stopPlayback()
        speechTranscriber.cancelTranscription()

        do {
            let result = try recordingFileStore.rename(recordingFile, to: newRecordingName)
            transcriptionStore.handleRename(result)

            recordingFileToRename = nil
            newRecordingName = ""
            statusMessage = "録音名を変更しました"
            loadRecordingFiles()
        } catch let error as RecordingFileStoreError {
            statusMessage = error.localizedDescription
        } catch {
            debugPrint("Failed to rename recording file: \(error.localizedDescription)")
            statusMessage = "録音名を変更できませんでした。もう一度お試しください。"
        }
    }

    private func togglePlayback(for recordingFile: RecordingFile) {
        do {
            speechTranscriber.cancelTranscription()
            try audioPlayer.togglePlayback(for: recordingFile)
            statusMessage = nil
        } catch {
            debugPrint("Failed to play audio: \(error.localizedDescription)")
            statusMessage = "音声を再生できませんでした。録音ファイルが見つからないか、読み込めない可能性があります。"
        }
    }

    private func transcribe(_ recordingFile: RecordingFile) {
        audioPlayer.stopPlayback()
        statusMessage = nil

        speechTranscriber.transcribe(
            recordingFile: recordingFile,
            onResult: { text, isFinal in
                transcriptionStore.updateTranscription(text: text, for: recordingFile)

                if isFinal {
                    transcriptionStore.saveTranscriptions()
                }
            },
            onCompletion: { error in
                guard let error else {
                    return
                }

                statusMessage = message(for: error)
            }
        )
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

    private func message(for error: SpeechTranscriberError) -> String {
        switch error {
        case .speechPermissionDenied:
            return "音声認識の使用が許可されていません。設定アプリで音声認識を許可してください。"
        case .speechRestricted:
            return "この端末では音声認識を使用できません。端末や利用制限の設定を確認してください。"
        case .speechPermissionNotDetermined:
            return "音声認識の許可を確認できませんでした。もう一度「文字起こし」を押してください。"
        case .speechAuthorizationFailed:
            return "音声認識を開始できませんでした。しばらくしてからもう一度お試しください。"
        case .japaneseRecognizerUnavailable:
            return "日本語の音声認識を使用できません。端末の言語設定や音声認識の利用状況を確認してください。"
        case .recognizerUnavailable:
            return "現在、音声認識を使用できません。端末の状態を確認して、時間をおいて再試行してください。"
        case .onDeviceRecognitionUnavailable:
            return "この端末ではオフライン音声認識を使用できません。外部送信を避けるため、文字起こしは開始しませんでした。"
        case .recognitionFailed:
            return "文字起こしに失敗しました。録音の音量や周囲の雑音を確認して、もう一度お試しください。"
        }
    }
}
