//
//  ContentView.swift
//  MutableCompositionIssue
//
//  Created by Semeniuk Slava on 23.04.2024.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State private var compositionStore = CompositionStore()
    @State private var generateTask: Task<Void, Never>?
    @State private var player = AVPlayer()

    private var currentDuration: CMTime? {
        player.currentItem?.duration
    }

    var body: some View {
        ZStack {
            if player.currentItem != nil {
                VideoPlayer(player: player)
                    .frame(height: 400)
            } else if generateTask != nil {
                ProgressView()
                    .tint(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.yellow)
        .overlay(alignment: .top) {
            if let currentDuration {
                VStack {
                    Text("Duration: \(currentDuration.value) / \(currentDuration.timescale)")
                    Text("Duration (seconds): \(currentDuration.seconds, format: .number.precision(.fractionLength(14))) s")
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                Text("Generate composition with speed applied:")
                HStack {
                    Button("To whole composition") { generate(isSequential: false) }
                    Button("Segment by segment") { generate(isSequential: true) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .buttonStyle(BorderedButtonStyle())
            .padding(8)
        }
        .onAppear { generate(isSequential: true) }
    }

    @MainActor
    private func generate(isSequential: Bool) {
        generateTask?.cancel()
        generateTask = Task {
            compositionStore.asset = nil
            if isSequential {
                try! await compositionStore.buildWithSequentialSpeed()
            } else {
                try! await compositionStore.buildWithTotalSpeed()
            }
            if Task.isCancelled { return }
            let item = compositionStore.asset.map(AVPlayerItem.init)
            item?.appliesPerFrameHDRDisplayMetadata = false
            player.replaceCurrentItem(with: item)
            generateTask = nil
        }
    }
}

@Observable
final class CompositionStore {

    var asset: AVMutableComposition?

    @MainActor
    func buildWithTotalSpeed() async throws {
        let date = Date()
        print("Start")
        defer { print("Complete: \(-date.timeIntervalSinceNow)") }
        let bundleFileURL = Bundle.main.url(forResource: "Sound", withExtension: "aac")!
        let sourceComposition = AVURLAsset(url: bundleFileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        asset = nil
        let targetComposition = AVMutableComposition()
        guard let targetTrack = targetComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: 1) else { return }
        guard let sourceTrack = try await sourceComposition.loadTracks(withMediaType: .audio).first else { return }

        let sourceTimeRange = try await sourceTrack.load(.timeRange)
        print(sourceTimeRange.duration)

        try targetTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceTrack,
            at: .zero
        )

        try targetTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceTrack,
            at: targetTrack.timeRange.end
        )

        print(targetComposition.duration)
        print(targetTrack.timeRange)

        targetTrack.scaleTimeRange(
            targetTrack.timeRange,
            toDuration: CMTimeMultiplyByRatio(targetTrack.timeRange.duration, multiplier: 1, divisor: 2)
        )

        print(targetComposition.duration)
        print(targetTrack.timeRange)

        asset = targetComposition
    }

    @MainActor
    func buildWithSequentialSpeed() async throws {
        let date = Date()
        print("Start")
        defer { print("Complete: \(-date.timeIntervalSinceNow)") }
        let bundleFileURL = Bundle.main.url(forResource: "Sound", withExtension: "aac")!
        let sourceComposition = AVURLAsset(url: bundleFileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        asset = nil
        let targetComposition = AVMutableComposition()
        guard let targetTrack = targetComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: 1) else { return }
        guard let sourceTrack = try await sourceComposition.loadTracks(withMediaType: .audio).first else { return }

        let sourceDuration = try await sourceComposition.load(.duration)

        let scaledDuration = CMTimeMultiplyByRatio(sourceDuration, multiplier: 1, divisor: 2)

        let sourceTimeRange = CMTimeRange(
            start: .zero,
            duration: sourceDuration
        )

        try targetTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceTrack,
            at: .zero
        )

        targetTrack.scaleTimeRange(
            sourceTimeRange,
            toDuration: scaledDuration
        )

        try targetTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceTrack,
            at: scaledDuration
        )

        print(targetComposition.duration)
        print(targetTrack.timeRange)

        let timeRangeToScale = CMTimeRange(
            start: scaledDuration,
            duration: sourceDuration
        )

        targetTrack.scaleTimeRange(
            timeRangeToScale,
            toDuration: scaledDuration
        )

        print(targetComposition.duration)
        print(targetTrack.timeRange)

        asset = targetComposition
    }
}

#Preview {
    ContentView()
}

extension CMTime {
    var debugString: String {
        "\(String(format: "%03d", value))/\(timescale)"
    }
}

extension CMTimeRange {
    var debugString: String {
        "\(start.debugString) - \(end.debugString)"
    }
}
