//
//  BoxAuthService.swift
//  Photo2drive
//

import Foundation
import UIKit
import AuthenticationServices

/// Service for handling Box OAuth authentication.
@MainActor
@Observable
final class BoxAuthService: NSObject {
    /// Box OAuth configuration.
    private let clientId = "9kfo24w6b9f7kfy0iy98thircffqlfi3"
    private let clientSecret = "juLWuUMB80CSGywXNUphQ2Ogsb5r8iee"
    private let redirectUri = "com.googleusercontent.apps.114679640018-nfrj12im4hbv49f9rfm4c5oosiv1thdb://box/callback"
    private let authURL = "https://account.box.com/api/oauth2/authorize"
    private let tokenURL = "https://api.box.com/oauth2/token"

    /// Current access token.
    private var accessToken: String?

    /// Current refresh token.
    private var refreshToken: String?

    /// Token expiration date.
    private var tokenExpirationDate: Date?

    /// User's display name.
    private(set) var userName: String?

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
        accessToken = KeychainService.load(forKey: KeychainService.BoxKeys.accessToken)
        refreshToken = KeychainService.load(forKey: KeychainService.BoxKeys.refreshToken)

        if accessToken != nil {
            // ユーザー名を取得
            Task {
                await fetchUserInfo()
            }
        }
    }

    /// Saves tokens to Keychain.
    private func saveTokens() {
        if let accessToken = accessToken {
            KeychainService.save(token: accessToken, forKey: KeychainService.BoxKeys.accessToken)
        }
        if let refreshToken = refreshToken {
            KeychainService.save(token: refreshToken, forKey: KeychainService.BoxKeys.refreshToken)
        }
    }

    /// Signs in the user with Box.
    /// - Parameter viewController: View controller to present sign-in UI.
    func signIn(from viewController: UIViewController) async throws {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri)
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
        guard let url = URL(string: tokenURL) else {
            throw CloudStorageError.authenticationFailed("Invalid token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectUri
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudStorageError.authenticationFailed("Token exchange failed: \(errorMessage)")
        }

        let tokenResponse = try JSONDecoder().decode(BoxTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

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
            "client_id": clientId,
            "client_secret": clientSecret
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // リフレッシュ失敗時はログアウト
            signOut()
            throw CloudStorageError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(BoxTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        saveTokens()
    }

    /// Fetches user info from Box API.
    private func fetchUserInfo() async {
        guard let token = accessToken,
              let url = URL(string: "https://api.box.com/2.0/users/me") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let userInfo = try JSONDecoder().decode(BoxUserInfo.self, from: data)
            userName = userInfo.name
        } catch {
            print("[Box] Failed to fetch user info: \(error)")
        }
    }

    /// Signs out the current user.
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        userName = nil

        KeychainService.delete(forKey: KeychainService.BoxKeys.accessToken)
        KeychainService.delete(forKey: KeychainService.BoxKeys.refreshToken)
    }

    /// Gets a valid access token, refreshing if necessary.
    func getAccessToken() async throws -> String {
        guard let token = accessToken else {
            throw CloudStorageError.notAuthenticated
        }

        // トークンが期限切れの場合はリフレッシュ
        if let expirationDate = tokenExpirationDate, Date() >= expirationDate {
            try await refreshAccessToken()
            guard let newToken = accessToken else {
                throw CloudStorageError.tokenRefreshFailed
            }
            return newToken
        }

        return token
    }

    /// Handles URL callback from Box OAuth.
    func handleURL(_ url: URL) -> Bool {
        guard url.absoluteString.contains("box/callback") else {
            return false
        }
        // ASWebAuthenticationSessionが自動的に処理する
        return true
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension BoxAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Response Models

private struct BoxTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct BoxUserInfo: Decodable {
    let id: String
    let name: String
}
