import Foundation

struct ProtectedServiceRequestTarget {
    let url: URL
    let bearerToken: String?

    var usesSessionToken: Bool {
        bearerToken != nil
    }
}

private struct ProtectedServiceEndpoints {
    let sessionURL: URL
    let chatURL: URL
}

private struct ProtectedServiceSession {
    let token: String
    let expiresAt: Date
    let appUserID: String
    let entitlementID: String
}

actor ProtectedServiceAuthStore {
    static let shared = ProtectedServiceAuthStore()

    private static let defaultSessionTTL: TimeInterval = 10 * 60
    private static let sessionRefreshLeeway: TimeInterval = 60

    private var cachedSession: ProtectedServiceSession?
    private var lastKnownSubscriber = false
    private let iso8601Formatter = ISO8601DateFormatter()
    private let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func updateSubscriptionStatus(isSubscriber: Bool) {
        guard lastKnownSubscriber != isSubscriber else {
            return
        }

        lastKnownSubscriber = isSubscriber
        cachedSession = nil
    }

    func invalidateSession() {
        cachedSession = nil
    }

    func requestTarget(
        legacyURL: URL,
        appUserID: String,
        entitlementID: String,
        requestKind: String,
        timeout: TimeInterval
    ) async throws -> ProtectedServiceRequestTarget {
        guard let endpoints = Self.configuredEndpoints else {
            return ProtectedServiceRequestTarget(url: legacyURL, bearerToken: nil)
        }

        let session = try await session(
            for: endpoints,
            appUserID: appUserID,
            entitlementID: entitlementID,
            requestKind: requestKind,
            timeout: timeout
        )
        return ProtectedServiceRequestTarget(url: endpoints.chatURL, bearerToken: session.token)
    }

    private func session(
        for endpoints: ProtectedServiceEndpoints,
        appUserID: String,
        entitlementID: String,
        requestKind: String,
        timeout: TimeInterval
    ) async throws -> ProtectedServiceSession {
        if let cachedSession,
           cachedSession.appUserID == appUserID,
           cachedSession.entitlementID == entitlementID,
           cachedSession.expiresAt.timeIntervalSinceNow > Self.sessionRefreshLeeway {
            return cachedSession
        }

        var request = URLRequest(url: endpoints.sessionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserID, forHTTPHeaderField: "X-CogniSphere-App-User-ID")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "app_user_id": appUserID,
                "platform": "ios",
                "entitlement_id": entitlementID,
                "request_kind": requestKind,
                "subscription_state": [
                    "is_subscriber": lastKnownSubscriber,
                    "updated_at": iso8601Formatter.string(from: Date())
                ]
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "ProtectedServiceAuthStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Protected session response was invalid."]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw sessionError(code: httpResponse.statusCode, responseData: data)
        }

        let session = try decodeSession(
            from: data,
            appUserID: appUserID,
            entitlementID: entitlementID
        )
        cachedSession = session
        return session
    }

    private func decodeSession(
        from data: Data,
        appUserID: String,
        entitlementID: String
    ) throws -> ProtectedServiceSession {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawToken = payload["token"] as? String else {
            throw NSError(
                domain: "ProtectedServiceAuthStore",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Protected session payload did not include a token."]
            )
        }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(
                domain: "ProtectedServiceAuthStore",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Protected session token was empty."]
            )
        }

        let expiresAt = parsedDate(from: payload["expires_at"])
            ?? Date().addingTimeInterval(Self.defaultSessionTTL)

        return ProtectedServiceSession(
            token: token,
            expiresAt: expiresAt,
            appUserID: appUserID,
            entitlementID: entitlementID
        )
    }

    private func parsedDate(from rawValue: Any?) -> Date? {
        if let number = rawValue as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }

        guard let string = rawValue as? String else {
            return nil
        }

        return fractionalISO8601Formatter.date(from: string)
            ?? iso8601Formatter.date(from: string)
    }

    private func sessionError(code: Int, responseData: Data) -> NSError {
        let detail: String
        if let responseText = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !responseText.isEmpty {
            detail = responseText
        } else {
            detail = "Protected session request failed."
        }

        return NSError(
            domain: "ProtectedServiceAuthStore",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: detail]
        )
    }

    private static var configuredEndpoints: ProtectedServiceEndpoints? {
        guard let sessionURL = bundleURL(forKey: "ProtectedSessionURL"),
              let chatURL = bundleURL(forKey: "ProtectedChatURL") else {
            return nil
        }

        return ProtectedServiceEndpoints(sessionURL: sessionURL, chatURL: chatURL)
    }

    private static func bundleURL(forKey key: String) -> URL? {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }
}
