//
//  ContentView.swift
//  MeetingTranscriber
//
//  Created by 中條航平 on 2026/06/13.
//

import SwiftUI

struct ContentView: View {
    @State private var isRecording = false

    var body: some View {
        VStack {
            Text("打ち合わせ文字起こし")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Button(isRecording ? "録音停止" : "録音開始") {
                isRecording.toggle()
            }
            .font(.title)
            .fontWeight(.bold)
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("まだ録音はありません")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
