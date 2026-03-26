import Foundation

struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int
    let externalUrls: ExternalUrls

    var artistName: String {
        artists.map(\.name).joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album
        case durationMs = "duration_ms"
        case externalUrls = "external_urls"
    }
}

struct SpotifyArtist: Codable {
    let id: String
    let name: String
}

struct SpotifyAlbum: Codable {
    let id: String
    let name: String
    let images: [SpotifyImage]

    var artworkURL: URL? {
        // Prefer medium-sized image
        let image = images.first(where: { $0.width == 300 }) ?? images.first
        return image.flatMap { URL(string: $0.url) }
    }
}

struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

struct ExternalUrls: Codable {
    let spotify: String?
}

struct CurrentlyPlayingResponse: Codable {
    let isPlaying: Bool
    let item: SpotifyTrack?
    let progressMs: Int?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case item
        case progressMs = "progress_ms"
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct CheckSavedResponse: Decodable {
    // Spotify returns a simple [Bool] array
}
