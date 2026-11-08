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
        #if DEBUG
        // 広告収録用(ci/ad-recording ブランチだけ): エミュレーターで、Apple ではなくメールのアカウントでログインして投稿できるようにする
        if ProcessInfo.processInfo.arguments.contains("-ad-member") && ProcessInfo.processInfo.arguments.contains("-use-emulator") {
            Task {
                let mail = "ad-recording@example.com", pass = "ad-recording-pass"
                do {
                    _ = try await Auth.auth().signIn(withEmail: mail, password: pass)
                    NSLog("AD-REC auth signIn ok")
                } catch {
                    NSLog("AD-REC auth signIn failed: \(error)")
                    do {
                        _ = try await Auth.auth().createUser(withEmail: mail, password: pass)
                        NSLog("AD-REC auth createUser ok")
                    } catch { NSLog("AD-REC auth createUser failed: \(error)") }
                }
            }
            return
        }
        #endif
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
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = L("error.signin.failed") }
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
                        try? await user.getIDTokenResult(forcingRefresh: true)
                    } catch let e as NSError where e.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        // 既に Apple で登録済みのアカウントがあれば、そちらに切り替える
                        guard let existing = e.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential else { throw e }
                        _ = try await Auth.auth().signIn(with: existing)
                    }
                } else {
                    _ = try await Auth.auth().signIn(with: credential)
                }
                isMember = Auth.auth().currentUser.map { !$0.isAnonymous } ?? false
            } catch {
                errorMessage = L("error.signin.failed")
            }
        }
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
