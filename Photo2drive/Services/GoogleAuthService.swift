//
//  GoogleAuthService.swift
//  Photo2drive
//

import Foundation
import GoogleSignIn

/// Error types for Google authentication.
enum GoogleAuthError: LocalizedError {
    case noClientId
    case signInFailed(String)
    case noCurrentUser
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .noClientId:
            return "Google Client ID not found in Info.plist"
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .noCurrentUser:
            return "No user is currently signed in"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        }
    }
}

/// Service for handling Google Sign-In authentication.
@MainActor
@Observable
final class GoogleAuthService {
    /// Current signed-in user.
    private(set) var currentUser: GIDGoogleUser?

    /// Whether user is currently signed in.
    var isSignedIn: Bool {
        currentUser != nil
    }

    /// User's display name.
    var userName: String? {
        currentUser?.profile?.name
    }

    /// User's email address.
    var userEmail: String? {
        currentUser?.profile?.email
    }

    /// User's profile image URL.
    var userProfileImageURL: URL? {
        currentUser?.profile?.imageURL(withDimension: 100)
    }

    /// Google Drive API scope for full access to user's Drive.
    private let driveScope = "https://www.googleapis.com/auth/drive"

    init() {
        // 以前のセッションを復元
        restorePreviousSignIn()
    }

    /// Restores previous sign-in session if available.
    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                if let user = user {
                    self?.currentUser = user
                }
            }
        }
    }

    /// Signs in the user with Google.
    /// - Parameter presentingViewController: View controller to present sign-in UI.
    func signIn(presentingViewController: UIViewController) async throws {
        guard let clientId = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw GoogleAuthError.noClientId
        }

        let configuration = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = configuration

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: [driveScope]
            )
            currentUser = result.user
        } catch {
            throw GoogleAuthError.signInFailed(error.localizedDescription)
        }
    }

    /// Signs out the current user.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }

    /// Gets a valid access token, refreshing if necessary.
    /// - Returns: Valid access token string.
    func getAccessToken() async throws -> String {
        guard let user = currentUser else {
            throw GoogleAuthError.noCurrentUser
        }

        // トークンが期限切れの場合はリフレッシュ
        do {
            try await user.refreshTokensIfNeeded()
            guard let accessToken = user.accessToken.tokenString as String? else {
                throw GoogleAuthError.tokenRefreshFailed
            }
            return accessToken
        } catch {
            throw GoogleAuthError.tokenRefreshFailed
        }
    }

    /// Handles URL callback from Google Sign-In.
    /// - Parameter url: Callback URL.
    /// - Returns: Whether the URL was handled.
    func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
