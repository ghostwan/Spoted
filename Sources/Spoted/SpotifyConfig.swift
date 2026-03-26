import Foundation

enum SpotifyConfig {
    // IMPORTANT: Create a Spotify Developer App at https://developer.spotify.com/dashboard
    // Set the Redirect URI to: spoted://callback
    // Then create a file Spoted/Config.xcconfig (git-ignored) with:
    //   SPOTIFY_CLIENT_ID = your_client_id
    //   SPOTIFY_CLIENT_SECRET = your_client_secret
    //
    // Or replace the values below directly (not recommended for version control).

    static let clientID = "18dc7247f590462cb120bc41ea40e551"
    static let clientSecret = "" // Not needed for PKCE flow

    static let redirectURI = "spoted://callback"
    static let scopes = "user-read-currently-playing user-read-playback-state user-library-read user-library-modify"

    static let authorizeURL = "https://accounts.spotify.com/authorize"
    static let tokenURL = "https://accounts.spotify.com/api/token"
    static let apiBaseURL = "https://api.spotify.com/v1"
}
