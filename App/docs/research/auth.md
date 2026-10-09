# Auth: Cognito sign-in without Amplify

Researched 2026-10-09 against the Cognito developer guide and the iOS 27 SDK (Xcode-beta).

## Recommendation

Use the **managed login** pages through the SwiftUI `webAuthenticationSession` environment value, which wraps `ASWebAuthenticationSession`. Run an **authorization code + PKCE (S256)** flow against a **public app client** (no secret) with a custom-scheme callback `kilnwatch://auth/callback`, and use `preferredBrowserSession: .ephemeral` so no Safari cookie outlives sign-out. Keep the **refresh token in the Keychain** (`AfterFirstUnlockThisDeviceOnly`) and keep the access and ID tokens in memory. One `actor` refreshes tokens, so the outbox flush and the UI never race a rotated refresh token. Sign out with `POST /oauth2/revoke`, then delete the Keychain item. `/logout` is unnecessary when the session is ephemeral. **Role = Cognito group** (`inspector`, `reviewer`). **District = custom attribute `custom:district`**, written only by admins. The app reads both from the ID token, only to hide actions. Every decision is still made by Verified Permissions on the server.

## Endpoints and parameters (domain `https://<prefix>.auth.<region>.amazoncognito.com`)

| Step | Request |
|---|---|
| Sign in | `GET /oauth2/authorize?response_type=code&client_id=…&redirect_uri=kilnwatch://auth/callback&scope=openid+profile+email&state=<rand>&code_challenge=<b64url(SHA256(verifier))>&code_challenge_method=S256` (optionally `&lang=en`, `&prompt=login`) |
| Callback | `kilnwatch://auth/callback?code=<uuid>&state=<rand>`. The code is valid for 5 min. On failure: `?error=invalid_request|unauthorized_client|invalid_scope|login_required` |
| Exchange | `POST /oauth2/token`, `Content-Type: application/x-www-form-urlencoded`, body `grant_type=authorization_code&client_id=…&code=…&redirect_uri=…&code_verifier=…`. Returns `id_token`, `access_token`, `refresh_token`, `expires_in` |
| Refresh | `POST /oauth2/token`, body `grant_type=refresh_token&client_id=…&refresh_token=…`. With rotation on, the response also carries a **new** `refresh_token`. Store it before you use the new access token. `invalid_grant` means the user must sign in again |
| Sign out | `POST /oauth2/revoke`, body `token=<refresh_token>&client_id=…`. Returns 200 with an empty body, and also revokes the access tokens minted from that refresh token. Needs revocation enabled on the client (the default) |
| Browser logout (only for a shared session) | `GET /logout?client_id=…&logout_uri=<allowed sign-out URL>` clears the 1-hour `cognito` cookie |
| Keys | `https://cognito-idp.<region>.amazonaws.com/<poolId>/.well-known/openid-configuration` (JWKS, for the backend and AgentCore) |

Do **not** request `aws.cognito.signin.user.admin`, because the app never calls the user-pool API directly.

App client settings for the backend owner: public client with no secret; allowed flow is code only (implicit off); callback `kilnwatch://auth/callback`; refresh token rotation **on** with a 10–60 s grace period; refresh validity sized to a field rotation (30 days is suggested, and rotation **does not extend** that window); access and ID tokens 60 min; **`WriteAttributes` must exclude `custom:district`**. Without that exclusion, any user can rewrite their own district with `UpdateUserAttributes`, and both the UI and the policies trust that value.

## How role and district reach the app

- `cognito:groups` is in **both** the ID and the access token. `custom:*` attributes are in the **ID token only**. They reach the access token only through a pre-token-generation trigger (v2), which needs the Essentials or Plus plan. Managed login already needs Essentials or Plus, so the plan is not extra.
- In Verified Permissions, ID-token claims become **principal attributes** (`principal["custom:district"]`), access-token claims go into `context.token.*`, and groups become parents of type `<Namespace>::UserGroup::"<poolId>|inspector"`. The concept's policy becomes:
  `permit (principal in KilnWatch::UserGroup::"<poolId>|inspector", action == KilnWatch::Action::"RecordVerdict", resource) when { resource.district == principal["custom:district"] };`
  That holds if the API authorizes with the **ID token**. If it authorizes with the access token, add the trigger and compare `context.token.district`.
- The app decodes the ID token payload (base64url JSON, no signature check, because it is a UI hint only). It shows **Record verdict** only when `groups ∋ "inspector"` and `kiln.district == district`, and it labels other kilns read-only. A 403 from the API is still handled, because tokens can be up to 60 min stale after an admin change.

## Example (PKCE and claims verified on Swift 6.4 against the RFC 7636 test vector)

```swift
struct Session: Sendable { var access: String; var id: String; var expires: Date }

actor Auth {
    let domain = URL(string: "https://kilnwatch.auth.us-west-2.amazoncognito.com")!, clientID = "<app client id>"
    let redirect = "kilnwatch://auth/callback"
    private var session: Session?
    private var refreshing: Task<Session, Error>?

    // Called from a view: let url = try await webAuthenticationSession.authenticate(using: authorizeURL,
    //   callback: .customScheme("kilnwatch"), preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])
    func authorizeURL(verifier: String, state: String) -> URL {
        var c = URLComponents(url: domain.appending(path: "oauth2/authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
                        .init(name: "redirect_uri", value: redirect), .init(name: "scope", value: "openid profile email"),
                        .init(name: "state", value: state), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URL)]
        return c.url!
    }

    func accessToken() async throws -> String {          // every API call goes through here
        if let s = session, s.expires > .now + 60 { return s.access }
        if let t = refreshing { return try await t.value.access }
        let t = Task { try await tokenRequest(["grant_type": "refresh_token", "client_id": clientID,
                                               "refresh_token": try Keychain.read("refresh")]) }
        refreshing = t; defer { refreshing = nil }
        session = try await t.value; return session!.access
    }

    func tokenRequest(_ form: [String: String]) async throws -> Session {
        var r = URLRequest(url: domain.appending(path: "oauth2/token")); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents(); c.queryItems = form.map { .init(name: $0, value: $1) }
        r.httpBody = Data(c.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.signInRequired } // invalid_grant etc.
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let rt = t.refresh_token { try Keychain.write("refresh", rt) }   // write the rotated token before anything else
        return Session(access: t.access_token, id: t.id_token, expires: .now + Double(t.expires_in))
    }
}
// Keychain item: kSecClassGenericPassword, kSecAttrService "kilnwatch.auth",
// kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, so the outbox can flush while the
// phone is locked and the item never syncs to iCloud or migrates to another device.
```

Check `state` on the callback before you exchange the code. Generate the verifier from 32 `SecRandomCopyBytes` bytes encoded as base64url (43 characters). `URLComponents` leaves `+` unescaped, which is why `+` is re-escaped above.

## Evidence

- Authorize endpoint (PKCE S256 only, custom schemes allowed, `lang`, `prompt`): https://docs.aws.amazon.com/cognito/latest/developerguide/authorization-endpoint.html
- Token endpoint (public client `client_id` in body, rotation returns a new refresh token, error codes): https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html
- Revoke: https://docs.aws.amazon.com/cognito/latest/developerguide/revocation-endpoint.html
- Logout: https://docs.aws.amazon.com/cognito/latest/developerguide/logout-endpoint.html
- Refresh lifetimes, rotation, and "rotation doesn't extend the window": https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-the-refresh-token.html
- Managed login (1 h cookie, the languages list, and SDK-created clients needing `CreateManagedLoginBranding`): https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-managed-login.html
- Feature plans (managed login and access-token customization need Essentials or Plus): https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-sign-in-feature-plans.html
- `WriteAttributes` warning: https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-attributes.html
- Verified Permissions token mapping and group entity id format: https://docs.aws.amazon.com/verifiedpermissions/latest/userguide/cognito-map-token-to-schema.html and https://docs.aws.amazon.com/verifiedpermissions/latest/userguide/policies-examples.html
- iOS 27 SDK: `WebAuthenticationSession.authenticate(using:callback:preferredBrowserSession:additionalHeaderFields:)` (iOS 17.4+) in `_AuthenticationServices_SwiftUI.swiftinterface`, and `ASWebAuthenticationSessionCallback.customScheme(_:)` / `https(host:path:)`.

## Open questions for the backend owner

1. Which token does the API authorize with? The **ID token** (simplest, matching the concept's `principal.district`) or the access token plus a pre-token trigger? AgentCore validates `client_id` for access tokens and `aud` for ID tokens, so pick one and send it everywhere.
2. Can an inspector cover several districts? If so, use a string set via the trigger, or one group per district (`district:hapur`).
3. **Hindi is not a managed login language** (de, en, es, fr, id, nl, it, ja, ko, pt-BR, zh-CN, zh-TW). Phase 6 must accept English sign-in pages, or build sign-in natively with `InitiateAuth`.
4. User pool and app client IDs, the domain, and the refresh validity (open item in build-plan.md).
5. Is MFA required for inspectors? Managed login handles it with no app change.
