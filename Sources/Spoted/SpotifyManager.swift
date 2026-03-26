import Foundation
import AppKit
import CryptoKit

// MARK: - File Logger

enum Log {
    private static let logFile: URL = {
        let url = URL(fileURLWithPath: "/tmp/spoted.log")
        // Clear log on launch
        try? "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    static func debug(_ message: String) {
        write("DEBUG", message)
    }

    private static func write(_ level: String, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}

@MainActor
class SpotifyManager: ObservableObject {
    @Published var currentTrack: SpotifyTrack?
    @Published var isPlaying: Bool = false
    @Published var isLiked: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?
    private var pollingTimer: Timer?
    private var codeVerifier: String?
    private var lastTrackId: String?

    private let keychainAccessTokenKey = "spotify_access_token"
    private let keychainRefreshTokenKey = "spotify_refresh_token"
    private let keychainExpirationKey = "spotify_token_expiration"

    init() {
        Log.info("SpotifyManager init")
        loadTokens()
        if isAuthenticated {
            Log.info("Tokens found, starting polling")
            startPolling()
        }
    }

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Authentication (PKCE Flow)

    func authenticate() {
        Log.info("Starting authentication...")
        Log.info("Requested scopes: \(SpotifyConfig.scopes)")
        codeVerifier = generateCodeVerifier()
        guard let verifier = codeVerifier else { return }
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: SpotifyConfig.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        if let url = components.url {
            Log.debug("Auth URL: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        }
    }

    func handleCallback(url: URL) async {
        Log.info("Received callback URL: \(url.absoluteString)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            self.error = "Failed to get authorization code"
            Log.error("Failed to extract authorization code from callback URL")
            return
        }

        Log.info("Got authorization code, exchanging for token...")
        await exchangeCodeForToken(code: code)
    }

    func logout() {
        Log.info("Logging out, clearing tokens")
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        currentTrack = nil
        isPlaying = false
        isLiked = false
        isAuthenticated = false
        pollingTimer?.invalidate()

        KeychainHelper.delete(key: keychainAccessTokenKey)
        KeychainHelper.delete(key: keychainRefreshTokenKey)
        KeychainHelper.delete(key: keychainExpirationKey)
    }

    // MARK: - Token Management

    private func exchangeCodeForToken(code: String) async {
        guard let verifier = codeVerifier else { return }

        var request = URLRequest(url: URL(string: SpotifyConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                Log.info("Token exchange HTTP \(httpResponse.statusCode)")
                Log.debug("Token response body: \(rawBody)")
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            Log.info("Token granted scopes: \(tokenResponse.scope ?? "nil")")
            Log.info("Has refresh token: \(tokenResponse.refreshToken != nil)")
            saveTokens(tokenResponse)
            isAuthenticated = true
            startPolling()
            await fetchCurrentTrack()
        } catch {
            Log.error("Token exchange failed: \(error)")
            self.error = "Authentication failed: \(error.localizedDescription)"
        }
    }

    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = refreshToken else {
            Log.error("No refresh token available")
            return false
        }

        Log.info("Refreshing access token...")

        var request = URLRequest(url: URL(string: SpotifyConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientID
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                Log.info("Token refresh HTTP \(httpResponse.statusCode)")
            }
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            Log.info("Refreshed token scopes: \(tokenResponse.scope ?? "nil")")
            saveTokens(tokenResponse)
            return true
        } catch {
            Log.error("Token refresh failed: \(error)")
            self.error = "Token refresh failed"
            isAuthenticated = false
            return false
        }
    }

    private func saveTokens(_ response: TokenResponse) {
        accessToken = response.accessToken
        if let newRefreshToken = response.refreshToken {
            refreshToken = newRefreshToken
            KeychainHelper.save(key: keychainRefreshTokenKey, value: newRefreshToken)
        }
        let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        tokenExpirationDate = expiration

        KeychainHelper.save(key: keychainAccessTokenKey, value: response.accessToken)
        KeychainHelper.save(key: keychainExpirationKey, value: "\(expiration.timeIntervalSince1970)")
    }

    private func loadTokens() {
        accessToken = KeychainHelper.load(key: keychainAccessTokenKey)
        refreshToken = KeychainHelper.load(key: keychainRefreshTokenKey)

        if let expirationString = KeychainHelper.load(key: keychainExpirationKey),
           let expirationInterval = Double(expirationString) {
            tokenExpirationDate = Date(timeIntervalSince1970: expirationInterval)
        }

        isAuthenticated = accessToken != nil && refreshToken != nil
    }

    private func getValidToken() async -> String? {
        if let expiration = tokenExpirationDate, expiration < Date() {
            let success = await refreshAccessToken()
            if !success { return nil }
        }
        return accessToken
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - API Calls

    func fetchCurrentTrack() async {
        guard let token = await getValidToken() else {
            Log.error("fetchCurrentTrack: no valid token")
            return
        }

        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/currently-playing")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 204 {
                currentTrack = nil
                isPlaying = false
                isLiked = false
                lastTrackId = nil
                return
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                Log.error("fetchCurrentTrack: HTTP \(httpResponse.statusCode) - \(body)")
                return
            }

            let playingResponse = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
            currentTrack = playingResponse.item
            isPlaying = playingResponse.isPlaying

            // Only check liked status when the track changes
            if let trackId = playingResponse.item?.id, trackId != lastTrackId {
                lastTrackId = trackId
                await checkIfLiked(trackId: trackId)
            }
        } catch {
            Log.error("fetchCurrentTrack error: \(error)")
            self.error = "Failed to fetch current track"
        }
    }

    func checkIfLiked(trackId: String) async {
        guard let token = await getValidToken() else { return }

        let uri = "spotify:track:\(trackId)"
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/library/contains?uris=\(encodedUri)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let body = String(data: data, encoding: .utf8) ?? ""
                Log.info("checkIfLiked: HTTP \(httpResponse.statusCode) - \(body)")
                if httpResponse.statusCode != 200 {
                    Log.error("checkIfLiked failed: HTTP \(httpResponse.statusCode) - \(body)")
                    return
                }
            }
            let results = try JSONDecoder().decode([Bool].self, from: data)
            isLiked = results.first ?? false
        } catch {
            Log.error("checkIfLiked error: \(error)")
        }
    }

    func toggleLike() async {
        guard let track = currentTrack,
              let token = await getValidToken() else {
            Log.error("toggleLike: no track or no token")
            return
        }

        let method = isLiked ? "DELETE" : "PUT"
        let uri = "spotify:track:\(track.id)"
        let encodedUri = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        Log.info("toggleLike: \(method) track \(track.id) (\(track.name))")

        let url = URL(string: "\(SpotifyConfig.apiBaseURL)/me/library?uris=\(encodedUri)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let body = String(data: data, encoding: .utf8) ?? ""
                Log.info("toggleLike: HTTP \(httpResponse.statusCode) - \(body)")
                if httpResponse.statusCode == 200 {
                    isLiked.toggle()
                    Log.info("toggleLike: success, isLiked=\(isLiked)")
                } else {
                    Log.error("toggleLike failed: HTTP \(httpResponse.statusCode) - \(body)")
                    self.error = "Spotify error \(httpResponse.statusCode): \(body)"
                }
            }
        } catch {
            Log.error("toggleLike error: \(error)")
            self.error = "Failed to update liked status"
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchCurrentTrack()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
