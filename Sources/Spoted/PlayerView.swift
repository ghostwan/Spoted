import SwiftUI

struct PlayerView: View {
    @ObservedObject var spotifyManager: SpotifyManager

    var body: some View {
        VStack(spacing: 0) {
            if spotifyManager.isAuthenticated {
                authenticatedView
            } else {
                loginView
            }
        }
        .frame(width: 320)
    }

    // MARK: - Login View

    private var loginView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Spoted")
                .font(.title2)
                .fontWeight(.bold)

            Text("Connect to Spotify to see what's playing and like tracks.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                spotifyManager.authenticate()
            }) {
                HStack {
                    Image(systemName: "link")
                    Text("Connect with Spotify")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            if let track = spotifyManager.currentTrack {
                trackView(track: track)
            } else {
                noTrackView
            }

            Divider()

            // Footer
            HStack {
                if let error = spotifyManager.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    spotifyManager.logout()
                }) {
                    Text("Logout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Track View

    private func trackView(track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            // Album artwork
            AsyncImage(url: track.album.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    artworkPlaceholder
                case .empty:
                    artworkPlaceholder
                        .overlay(ProgressView().scaleEffect(0.5))
                @unknown default:
                    artworkPlaceholder
                }
            }
            .frame(width: 64, height: 64)
            .cornerRadius(8)

            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(track.album.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Like button
            Button(action: {
                Task {
                    await spotifyManager.toggleLike()
                }
            }) {
                Image(systemName: spotifyManager.isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(spotifyManager.isLiked ? .green : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: spotifyManager.isLiked)
            }
            .buttonStyle(.plain)
            .help(spotifyManager.isLiked ? "Remove from Liked Songs" : "Add to Liked Songs")
        }
        .padding(12)
    }

    // MARK: - No Track View

    private var noTrackView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Nothing is playing")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Play something on Spotify to see it here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    // MARK: - Helpers

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
            )
    }
}
