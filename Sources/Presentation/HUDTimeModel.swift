#if canImport(Combine)
// Sources/Presentation/HUDTimeModel.swift
import Foundation
import Combine

@MainActor
final class HUDTimeModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var isLiveStream = false
    var isSeeking = false
    private var lastLiveUIUpdate: TimeInterval = 0

    func apply(seconds: Double, itemDuration: Double?) {
        guard !isSeeking, seconds.isFinite else { return }
        guard let itemDuration else {
            currentTime = seconds
            return
        }
        let live = !(itemDuration.isFinite && itemDuration > 0)
        if live != isLiveStream { isLiveStream = live }
        if !live {
            duration = itemDuration
            currentTime = seconds
        } else if !lastLiveUIUpdate.isFinite || seconds - lastLiveUIUpdate >= 2 {
            lastLiveUIUpdate = seconds
            currentTime = seconds
        }
    }
}
#endif
