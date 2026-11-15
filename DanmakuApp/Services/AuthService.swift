import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation

/// 遊ぶだけは匿名認証。投稿・いいね・通報は Sign in with Apple（匿名アカウントからリンクして引き継ぐ）
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var uid: String?
    @Published private(set) var isMember = false
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    func start() {
        guard Backend.isAvailable, handle == nil else { return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.uid = user?.uid
                self?.isMember = user.map { !$0.isAnonymous } ?? false
            }
        }
        if Auth.auth().currentUser == nil {
            Task { try? await Auth.auth().signInAnonymously() }
        }
    }

    // MARK: Sign in with Apple（SignInWithAppleButton の onRequest / onCompletion から呼ぶ）

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = Self.failureMessage(error) }
        case .success(let auth):
            guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else { errorMessage = L("error.signin.failed"); return }
            isBusy = true
            defer { isBusy = false }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
            do {
                if let user = Auth.auth().currentUser, user.isAnonymous {
                    do {
                        _ = try await user.link(with: credential)
                    } catch let e as NSError where e.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        // 既に Apple で登録済みのアカウントがあれば、そちらに切り替える
                        if let existing = e.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                            _ = try await Auth.auth().signIn(with: existing)
                        } else {
                            _ = try await Auth.auth().signIn(with: credential)
                        }
                    } catch let e as NSError where Self.anonymousUnusable.contains(e.code) {
                        // 匿名のアカウントが使えなくなっている(期限切れ・消えた・トークンが壊れた)ときだけ、
                        // 匿名の分はあきらめて、Apple で直接サインインする(ずっと登録できないままにならないように)。
                        // 一時的な失敗では切り替えない(匿名で遊んだ分が、黙って引き継がれなくなるため)
                        _ = try await Auth.auth().signIn(with: credential)
                    }
                } else {
                    _ = try await Auth.auth().signIn(with: credential)
                }
                // サーバーが「サインイン済み」と分かるように、トークンを作り直す(失敗したら少し待って、もう一度)
                await refreshToken()
                isMember = Auth.auth().currentUser.map { !$0.isAnonymous } ?? false
            } catch {
                errorMessage = Self.failureMessage(error)
            }
        }
    }

    /// 匿名のアカウントがもう使えないことを表す失敗(期限切れ・見つからない・トークンが壊れた・もう一度ログインが要る)
    private static let anonymousUnusable: Set<Int> = [
        AuthErrorCode.userTokenExpired.rawValue, AuthErrorCode.userNotFound.rawValue,
        AuthErrorCode.invalidUserToken.rawValue, AuthErrorCode.requiresRecentLogin.rawValue,
    ]

    /// サインインのあと、トークンを作り直す(つなぐ前の「匿名」のトークンのままだと、投稿などがサインインを求められて失敗する)。
    /// 失敗しても、サーバーはアカウントの実際の状態も見るので、投稿はできる
    private func refreshToken() async {
        for attempt in 0..<3 {
            if (try? await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)) != nil { return }
            try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
        }
    }

    /// サインインに失敗したときの文。よくある原因(iPhone の Apple ID の設定・スクリーンタイムの制限・通信)は、それに合わせて案内する。
    /// それ以外は、原因を調べられるように失敗の種類(コード)を添える(要望フォームで教えてもらう)
    static func failureMessage(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == ASAuthorizationError.errorDomain {
            // 1000(unknown)は、Apple ID にサインインしていない・2ファクタ認証がない・スクリーンタイムの制限などで起きる
            if e.code == ASAuthorizationError.unknown.rawValue || e.code == ASAuthorizationError.notHandled.rawValue {
                return L("error.signin.apple.setup")
            }
        } else if e.domain == AuthErrorDomain, e.code == AuthErrorCode.networkError.rawValue {
            return L("error.signin.network")
        }
        return String(format: L("error.signin.failed.code"), "\(e.domain.split(separator: ".").last.map(String.init) ?? e.domain) \(e.code)")
    }

    /// アカウント削除。Apple のトークンを失効させてから、サーバーで投稿・データ・認証ユーザーを削除する
    func deleteAccount(_ result: Result<ASAuthorization, Error>) async -> Bool {
        errorMessage = nil
        guard case .success(let auth) = result, let apple = auth.credential as? ASAuthorizationAppleIDCredential,
              let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
            if case .failure(let e) = result, (e as? ASAuthorizationError)?.code == .canceled { return false }
            errorMessage = L("error.delete.failed")
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Auth.auth().revokeToken(withAuthorizationCode: code)
            _ = try await Backend.functions.httpsCallable("deleteAccount").call([:])
            try? Auth.auth().signOut()
            _ = try? await Auth.auth().signInAnonymously()
            isMember = false
            return true
        } catch {
            errorMessage = L("error.delete.failed")
            return false
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        Task { try? await Auth.auth().signInAnonymously() }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        while out.count < length {
            var byte: UInt8 = 0
            if SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess, Int(byte) < chars.count * (256 / chars.count) {
                out.append(chars[Int(byte) % chars.count])
            }
        }
        return out
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
