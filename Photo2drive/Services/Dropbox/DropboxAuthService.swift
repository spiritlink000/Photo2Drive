//
//  DropboxAuthService.swift
//  Photo2drive
//

import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

/// Service for handling Dropbox OAuth authentication with PKCE.
@MainActor
@Observable
final class DropboxAuthService: NSObject {
    /// Dropbox OAuth configuration.
    private let appKey = "pysu4003p812xfz"
    private let redirectUri = "com.googleusercontent.apps.114679640018-nfrj12im4hbv49f9rfm4c5oosiv1thdb://dropbox/callback"
    private let authURL = "https://www.dropbox.com/oauth2/authorize"
    private let tokenURL = "https://api.dropboxapi.com/oauth2/token"

    /// Current access token.
    private var accessToken: String?

    /// Current refresh token.
    private var refreshToken: String?

    /// User's display name.
    private(set) var userName: String?

    /// PKCE code verifier.
    private var codeVerifier: String?

    /// Web authentication session.
    private var authSession: ASWebAuthenticationSession?

    /// Continuation for async sign-in.
    private var signInContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        loadTokens()
    }

    /// Whether user is currently signed in.
    var isSignedIn: Bool {
        accessToken != nil
    }

    /// Loads tokens from Keychain.
    private func loadTokens() {
        accessToken = KeychainService.load(forKey: KeychainService.DropboxKeys.accessToken)
        refreshToken = KeychainService.load(forKey: KeychainService.DropboxKeys.refreshToken)

        if accessToken != nil {
            Task {
                await fetchUserInfo()
            }
        }
    }

    /// Saves tokens to Keychain.
    private func saveTokens() {
        if let accessToken = accessToken {
            KeychainService.save(token: accessToken, forKey: KeychainService.DropboxKeys.accessToken)
        }
        if let refreshToken = refreshToken {
            KeychainService.save(token: refreshToken, forKey: KeychainService.DropboxKeys.refreshToken)
        }
    }

    /// Generates PKCE code verifier.
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Generates PKCE code challenge from verifier.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Signs in the user with Dropbox.
    func signIn(from viewController: UIViewController) async throws {
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: appKey),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "token_access_type", value: "offline")
        ]

        guard let authorizationURL = components.url else {
            throw CloudStorageError.authenticationFailed("Failed to create authorization URL")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.signInContinuation = continuation

            authSession = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: "com.googleusercontent.apps.114679640018-nfrj12im4hbv49f9rfm4c5oosiv1thdb"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self = self else { return }

                    if let error = error {
                        self.signInContinuation?.resume(throwing: CloudStorageError.authenticationFailed(error.localizedDescription))
                        self.signInContinuation = nil
                        return
                    }

                    guard let callbackURL = callbackURL,
                          let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value else {
                        self.signInContinuation?.resume(throwing: CloudStorageError.authenticationFailed("No authorization code received"))
                        self.signInContinuation = nil
                        return
                    }

                    do {
                        try await self.exchangeCodeForToken(code: code)
                        await self.fetchUserInfo()
                        self.signInContinuation?.resume()
                    } catch {
                        self.signInContinuation?.resume(throwing: error)
                    }
                    self.signInContinuation = nil
                }
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }

    /// Exchanges authorization code for access token.
    private func exchangeCodeForToken(code: String) async throws {
        guard let codeVerifier = codeVerifier else {
            throw CloudStorageError.authenticationFailed("Code verifier not found")
        }

        guard let url = URL(string: tokenURL) else {
            throw CloudStorageError.authenticationFailed("Invalid token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": appKey,
            "redirect_uri": redirectUri,
            "code_verifier": codeVerifier
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudStorageError.authenticationFailed("Token exchange failed: \(errorMessage)")
        }

        let tokenResponse = try JSONDecoder().decode(DropboxTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken

        saveTokens()
    }

    /// Refreshes the access token.
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw CloudStorageError.tokenRefreshFailed
        }

        guard let url = URL(string: tokenURL) else {
            throw CloudStorageError.tokenRefreshFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": appKey
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            signOut()
            throw CloudStorageError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(DropboxTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        // Dropboxはリフレッシュ時に新しいリフレッシュトークンを返さないことがある
        if let newRefreshToken = tokenResponse.refreshToken {
            self.refreshToken = newRefreshToken
        }

        saveTokens()
    }

    /// Fetches user info from Dropbox API.
    private func fetchUserInfo() async {
        guard let token = accessToken,
              let url = URL(string: "https://api.dropboxapi.com/2/users/get_current_account") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let userInfo = try JSONDecoder().decode(DropboxUserInfo.self, from: data)
            userName = userInfo.name.displayName
        } catch {
            print("[Dropbox] Failed to fetch user info: \(error)")
        }
    }

    /// Signs out the current user.
    func signOut() {
        accessToken = nil
        refreshToken = nil
        userName = nil
        codeVerifier = nil

        KeychainService.delete(forKey: KeychainService.DropboxKeys.accessToken)
        KeychainService.delete(forKey: KeychainService.DropboxKeys.refreshToken)
    }

    /// Gets a valid access token, refreshing if necessary.
    func getAccessToken() async throws -> String {
        guard let token = accessToken else {
            throw CloudStorageError.notAuthenticated
        }

        // Dropboxはトークンの有効期限を返さないので、エラー時にリフレッシュを試みる
        return token
    }

    /// Refreshes token if the current one is invalid.
    func refreshTokenIfNeeded() async throws -> String {
        do {
            let token = try await getAccessToken()
            return token
        } catch {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw CloudStorageError.tokenRefreshFailed
            }
            return newToken
        }
    }

    /// Handles URL callback from Dropbox OAuth.
    func handleURL(_ url: URL) -> Bool {
        guard url.absoluteString.contains("dropbox/callback") else {
            return false
        }
        return true
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension DropboxAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Response Models

private struct DropboxTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct DropboxUserInfo: Decodable {
    let name: DropboxName

    struct DropboxName: Decodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}
