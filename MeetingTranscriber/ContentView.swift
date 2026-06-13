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
    @State private var isShowingDeleteConfirmation = false
    @State private var recordingFileToDelete: RecordingFile?
    @State private var transcriptionScrollTargetID: String?
    @State private var transcriptionErrorMessages: [String: String] = [:]
    @State private var playbackSeekTime: TimeInterval?
    @State private var copyFeedback: CopyFeedback?
    @State private var copyFeedbackResetWorkItem: DispatchWorkItem?

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
                            HStack(spacing: 8) {
                                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")

                                Text(audioRecorder.isRecording ? "録音停止" : "録音開始")

                                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                                    .opacity(0)
                                    .accessibilityHidden(true)
                            }
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
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    showDeleteConfirmation(for: recordingFile)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }

                                Button {
                                    showRenameAlert(for: recordingFile)
                                } label: {
                                    Label("名称変更", systemImage: "pencil")
                                }
                                .tint(.blue)
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
            .alert("録音を削除しますか？", isPresented: $isShowingDeleteConfirmation) {
                Button("削除", role: .destructive) {
                    deleteSelectedRecordingFile()
                }

                Button("キャンセル", role: .cancel) {
                    recordingFileToDelete = nil
                }
            } message: {
                Text("録音ファイルと文字起こし結果が削除されます。この操作は取り消せません。")
            }
        }
    }

    private func recordingRow(for recordingFile: RecordingFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recordingFile.title)
                .font(.headline)

            Text(recordingFile.createdAt.formatted(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(deletionCountdownText(for: recordingFile))
                .font(.caption)
                .foregroundStyle(.orange)

            HStack(spacing: 8) {
                if audioPlayer.playingRecordingURL == recordingFile.url {
                    statusBadge("再生中", color: .blue)
                }

                if audioPlayer.activeRecordingURL == recordingFile.url && audioPlayer.playbackState == .paused {
                    statusBadge("一時停止中", color: .secondary)
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
        let transcriptionText = transcriptionStore.transcription(for: recordingFile)?.text ?? ""

        return ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recordingFile.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("作成日時: \(recordingFile.createdAt.formatted(date: .numeric, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Label(deletionCountdownText(for: recordingFile), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    detailSection("再生") {
                        playbackControlView(for: recordingFile)
                    }

                    detailSection("文字起こし") {
                        transcriptionActionView(for: recordingFile)
                    }

                    detailSection("状態") {
                        VStack(alignment: .leading, spacing: 8) {
                            if audioPlayer.playingRecordingURL == recordingFile.url {
                                statusBadge("再生中", color: .blue)
                            }

                            if audioPlayer.activeRecordingURL == recordingFile.url && audioPlayer.playbackState == .loading {
                                statusBadge("読み込み中", color: .blue)
                            }

                            if audioPlayer.activeRecordingURL == recordingFile.url && audioPlayer.playbackState == .paused {
                                statusBadge("一時停止中", color: .secondary)
                            }

                            if speechTranscriber.transcribingRecordingURL == recordingFile.url {
                                statusBadge("文字起こし中", color: .orange)
                            }

                            if let transcriptionErrorMessage = transcriptionErrorMessages[recordingFile.id] {
                                Label(transcriptionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if audioPlayer.activeRecordingURL != recordingFile.url && speechTranscriber.transcribingRecordingURL != recordingFile.url {
                                Text("待機中")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    detailSection("文字起こし結果") {
                        if let transcription = transcriptionStore.transcription(for: recordingFile) {
                            transcriptionView(transcription)
                        } else {
                            Text("まだ文字起こし結果はありません")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .id(transcriptionSectionID(for: recordingFile))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("録音詳細")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                audioPlayer.loadPlaybackInfo(for: recordingFile)
            }
            .onChange(of: transcriptionText) { _, newText in
                guard transcriptionScrollTargetID == recordingFile.id,
                      !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }

                withAnimation(.easeInOut) {
                    scrollProxy.scrollTo(transcriptionSectionID(for: recordingFile), anchor: .top)
                }
            }
            .onChange(of: speechTranscriber.transcribingRecordingURL) { _, transcribingURL in
                guard transcribingURL == nil,
                      transcriptionScrollTargetID == recordingFile.id,
                      transcriptionStore.transcription(for: recordingFile) != nil else {
                    return
                }

                withAnimation(.easeInOut) {
                    scrollProxy.scrollTo(transcriptionSectionID(for: recordingFile), anchor: .top)
                }

                transcriptionScrollTargetID = nil
            }
        }
    }

    private func playbackControlView(for recordingFile: RecordingFile) -> some View {
        let isCurrentRecording = audioPlayer.activeRecordingURL == recordingFile.url
        let isLoading = isCurrentRecording && audioPlayer.playbackState == .loading
        let isPlaying = isCurrentRecording && audioPlayer.playbackState == .playing
        let currentTime = isCurrentRecording ? audioPlayer.currentTime : 0
        let duration = audioPlayer.loadedRecordingURL == recordingFile.url ? audioPlayer.duration : 0
        let sliderUpperBound = max(duration, 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    togglePlayback(for: recordingFile)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.leading, isPlaying ? 0 : 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel(isPlaying ? "一時停止" : "再生")

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)

                        Text(playbackStatusText(for: recordingFile))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text("\(formattedPlaybackTime(currentTime)) / \(formattedPlaybackTime(duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()
            }

            Slider(
                value: Binding(
                    get: {
                        playbackSeekTime ?? currentTime
                    },
                    set: { newValue in
                        playbackSeekTime = newValue
                    }
                ),
                in: 0...sliderUpperBound,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        audioPlayer.seek(to: playbackSeekTime ?? currentTime)
                        playbackSeekTime = nil
                    }
                }
            )
            .disabled(duration <= 0 || isLoading)

            HStack {
                Text(formattedPlaybackTime(playbackSeekTime ?? currentTime))

                Spacer()

                Text(formattedPlaybackTime(duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func transcriptionActionView(for recordingFile: RecordingFile) -> some View {
        let state = transcriptionActionState(for: recordingFile)

        return Button {
            transcribe(recordingFile)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.tint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    if state.isProcessing {
                        ProgressView()
                            .tint(state.tint)
                    } else {
                        Image(systemName: state.systemImage)
                            .font(.headline)
                            .foregroundStyle(state.tint)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: state.trailingSystemImage)
                    .font(.subheadline)
                    .foregroundStyle(state.tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(state.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(state.tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isProcessing || speechTranscriber.transcribingRecordingURL != nil)
    }

    private func transcriptionActionState(for recordingFile: RecordingFile) -> TranscriptionActionState {
        if speechTranscriber.transcribingRecordingURL == recordingFile.url {
            return .processing
        }

        if transcriptionErrorMessages[recordingFile.id] != nil {
            return .failed
        }

        if transcriptionStore.transcription(for: recordingFile) != nil {
            return .completed
        }

        return .ready
    }

    private func playbackStatusText(for recordingFile: RecordingFile) -> String {
        guard audioPlayer.activeRecordingURL == recordingFile.url else {
            return "再生準備完了"
        }

        switch audioPlayer.playbackState {
        case .stopped:
            return "再生準備完了"
        case .loading:
            return "読み込み中"
        case .playing:
            return "再生中"
        case .paused:
            return "一時停止中"
        }
    }

    private func formattedPlaybackTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time > 0 else {
            return "0:00"
        }

        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func deletionCountdownText(for recordingFile: RecordingFile, now: Date = Date()) -> String {
        let remainingSeconds = max(0, recordingFile.deletionDate.timeIntervalSince(now))
        let totalMinutes = Int(ceil(remainingSeconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return "あと\(hours)時間\(minutes)分で消去されます"
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

    private func detailSection<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transcriptionSectionID(for recordingFile: RecordingFile) -> String {
        "transcription-\(recordingFile.id)"
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
                    Label(copyFeedback?.message ?? "コピー", systemImage: copyFeedback?.systemImage ?? "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(copyFeedback?.color)
                .disabled(transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(transcription.text)
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text("文字起こし日時: \(transcription.createdAt.formatted(date: .numeric, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var consentConfirmationView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("録音への同意")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                Text("内容をご確認のうえ、同意いただける場合は下のボタンを押してください。")
                    .foregroundStyle(.secondary)

                Label("この打ち合わせの音声を録音します", systemImage: "mic.fill")
                Label("録音した音声は文字起こしに使用します", systemImage: "text.bubble.fill")
                Label("録音データと文字起こし結果はこの端末に保存されます", systemImage: "lock.fill")
                Label("保存されたデータは一定時間後に削除されます", systemImage: "clock.fill")
            }
            .font(.body)

            Spacer()

            Button {
                isShowingConsentConfirmation = false
                startRecording()
            } label: {
                Text("同意して録音を開始する")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingConsentConfirmation = false
            } label: {
                Text("同意しない")
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
        newRecordingName = recordingFile.title
        isShowingRenameAlert = true
    }

    private func showDeleteConfirmation(for recordingFile: RecordingFile) {
        recordingFileToDelete = recordingFile
        isShowingDeleteConfirmation = true
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

    private func deleteSelectedRecordingFile() {
        guard let recordingFile = recordingFileToDelete else {
            return
        }

        audioPlayer.stopPlayback()
        speechTranscriber.cancelTranscription()

        do {
            try recordingFileStore.delete(recordingFile)
            transcriptionStore.deleteTranscription(for: recordingFile)
            recordingFileToDelete = nil
            statusMessage = "録音を削除しました"
            loadRecordingFiles()
        } catch {
            debugPrint("Failed to delete recording file: \(error.localizedDescription)")
            statusMessage = "録音を削除できませんでした。もう一度お試しください。"
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
        transcriptionScrollTargetID = recordingFile.id
        transcriptionErrorMessages[recordingFile.id] = nil

        speechTranscriber.transcribe(
            recordingFile: recordingFile,
            onResult: { text, _ in
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedText.isEmpty else {
                    return
                }

                transcriptionErrorMessages[recordingFile.id] = nil
                transcriptionStore.updateTranscription(text: trimmedText, for: recordingFile)
                transcriptionStore.saveTranscriptions()
            },
            onCompletion: { error in
                guard let error else {
                    return
                }

                let message = message(for: error)
                debugPrint("Transcription failed for \(recordingFile.name): \(error.logDescription)")
                transcriptionErrorMessages[recordingFile.id] = message
                statusMessage = message
            }
        )
    }

    private func copyTranscriptionText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            showCopyFeedback(.failure)
            return
        }

        UIPasteboard.general.string = trimmedText

        if UIPasteboard.general.string == trimmedText {
            showCopyFeedback(.success)
        } else {
            showCopyFeedback(.failure)
        }
    }

    private func showCopyFeedback(_ feedback: CopyFeedback) {
        copyFeedbackResetWorkItem?.cancel()
        copyFeedback = feedback

        let resetWorkItem = DispatchWorkItem {
            copyFeedback = nil
            copyFeedbackResetWorkItem = nil
        }

        copyFeedbackResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: resetWorkItem)
    }

    private func message(for error: SpeechTranscriberError) -> String {
        switch error {
        case .recordingFileNotFound:
            return "録音ファイルが見つかりません。録音一覧を開き直して、もう一度お試しください。"
        case .recordingFileEmpty:
            return "録音ファイルに音声が保存されていない可能性があります。録音し直してください。"
        case .recordingFileUnavailable:
            return "録音ファイルを確認できませんでした。ファイルの保存状態を確認してください。"
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
        case .noRecognizableSpeech:
            return "音声を認識できませんでした。録音の音量や周囲の雑音を確認して、もう一度お試しください。"
        case .recognitionFailed(let detail):
            return "文字起こしに失敗しました。録音の音量、通信状況、音声認識の利用状況を確認してください。詳細: \(detail)"
        }
    }
}

private enum CopyFeedback {
    case success
    case failure

    var message: String {
        switch self {
        case .success:
            return "コピーしました"
        case .failure:
            return "コピーできませんでした"
        }
    }

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

private enum TranscriptionActionState {
    case ready
    case processing
    case completed
    case failed

    var title: String {
        switch self {
        case .ready:
            return "文字起こしを開始"
        case .processing:
            return "文字起こし中"
        case .completed:
            return "文字起こし済み"
        case .failed:
            return "もう一度文字起こし"
        }
    }

    var subtitle: String {
        switch self {
        case .ready:
            return "録音音声からテキストを作成"
        case .processing:
            return "音声を解析しています"
        case .completed:
            return "結果を下に表示しています"
        case .failed:
            return "前回は完了できませんでした"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            return "text.bubble.fill"
        case .processing:
            return "text.bubble.fill"
        case .completed:
            return "checkmark"
        case .failed:
            return "arrow.clockwise"
        }
    }

    var trailingSystemImage: String {
        switch self {
        case .ready, .failed:
            return "chevron.right"
        case .processing:
            return "hourglass"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .accentColor
        case .processing:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    var backgroundColor: Color {
        switch self {
        case .ready:
            return Color.accentColor.opacity(0.08)
        case .processing:
            return Color.orange.opacity(0.08)
        case .completed:
            return Color.green.opacity(0.08)
        case .failed:
            return Color.red.opacity(0.08)
        }
    }

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }

        return false
    }
}
