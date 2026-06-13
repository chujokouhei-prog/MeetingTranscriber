//
//  ContentView.swift
//  MeetingTranscriber
//
//  Created by 中條航平 on 2026/06/13.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var message = "まだ録音はありません"

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

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Spacer()
        }
        .padding(32)
    }

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecording()
                } else {
                    message = "マイクの使用が許可されていません"
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
            message = "録音中です"
        } catch {
            message = "録音を開始できませんでした"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        message = "録音を保存しました"

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            message = "録音は停止しましたが、音声設定の終了に失敗しました"
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
}

#Preview {
    ContentView()
}
