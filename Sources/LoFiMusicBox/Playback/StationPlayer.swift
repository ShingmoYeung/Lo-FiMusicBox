import Foundation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}

@MainActor
protocol StationPlayer: AnyObject {
    func load(_ station: Station) async throws
    func play()
    func pause()
    func setVolume(_ volume: Float)
}
