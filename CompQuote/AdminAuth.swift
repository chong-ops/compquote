import SwiftUI
import Security
import Combine
import CryptoKit
import LocalAuthentication

// MARK: - Admin Auth Manager
// Stores a salted SHA-256 hash of the 6-digit PIN in Keychain — never the PIN
// itself. Tracks unlock state with a 5-minute timeout, locks out after
// repeated failed attempts with an escalating delay, and supports
// Face ID / Touch ID as a convenience unlock.
//
// NOTE: Face ID requires NSFaceIDUsageDescription in Info.plist, e.g.
// "Unlock admin settings with Face ID."

class AdminAuth: ObservableObject {
    static let shared = AdminAuth()

    @Published var isUnlocked = false
    @Published var isPINSet = false

    private var unlockTime: Date?
    private let timeoutSeconds: TimeInterval = 5 * 60  // 5 minutes
    private let keychainKey = "compquote.admin.pin"

    // Brute-force protection
    private let attemptsKey = "adminPINFailedAttempts"
    private let lockoutKey  = "adminPINLockoutUntil"
    private let maxFreeAttempts = 5

    private init() {
        isPINSet = storedSecret != nil
    }

    // MARK: - Keychain storage
    private var storedSecret: String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      keychainKey as CFString,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else { return nil }
        return secret
    }

    private func store(secret: String) {
        // Delete existing first
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: keychainKey as CFString
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        guard let data = secret.data(using: .utf8) else { return }
        let addQuery: [CFString: Any] = [
            kSecClass:             kSecClassGenericPassword,
            kSecAttrAccount:       keychainKey as CFString,
            kSecValueData:         data,
            kSecAttrAccessible:    kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Hashing
    // Secret format: "v1$<saltHex>$<sha256Hex>". Older installs stored the
    // 6-digit PIN as plaintext — pinMatches() verifies those and silently
    // upgrades them to hashed storage on the next successful unlock.
    private func hashHex(pin: String, saltHex: String) -> String {
        let digest = SHA256.hash(data: Data((saltHex + pin).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomSaltHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func pinMatches(_ pin: String) -> Bool {
        guard let secret = storedSecret else { return false }
        if secret.hasPrefix("v1$") {
            let parts = secret.split(separator: "$")
            guard parts.count == 3 else { return false }
            return hashHex(pin: pin, saltHex: String(parts[1])) == String(parts[2])
        }
        // Legacy plaintext secret — compare directly, then upgrade.
        if secret == pin {
            setPIN(pin)
            return true
        }
        return false
    }

    // MARK: - PIN management
    func setPIN(_ pin: String) {
        let salt = randomSaltHex()
        store(secret: "v1$\(salt)$\(hashHex(pin: pin, saltHex: salt))")
        isPINSet = true
        resetAttempts()
    }

    func deletePIN() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: keychainKey as CFString
        ]
        SecItemDelete(query as CFDictionary)
        isPINSet = false
        isUnlocked = false
        unlockTime = nil
        resetAttempts()
    }

    // MARK: - Brute-force lockout
    /// Seconds remaining before another attempt is allowed. 0 = not locked out.
    var lockoutRemaining: TimeInterval {
        max(0, UserDefaults.standard.double(forKey: lockoutKey) - Date().timeIntervalSince1970)
    }

    /// Failed attempts left before the lockout kicks in.
    var attemptsBeforeLockout: Int {
        max(0, maxFreeAttempts - UserDefaults.standard.integer(forKey: attemptsKey))
    }

    private func resetAttempts() {
        UserDefaults.standard.removeObject(forKey: attemptsKey)
        UserDefaults.standard.removeObject(forKey: lockoutKey)
    }

    // MARK: - Verification
    func verify(_ pin: String) -> Bool {
        guard lockoutRemaining <= 0 else { return false }
        if pinMatches(pin) {
            resetAttempts()
            unlock()
            return true
        }
        let attempts = UserDefaults.standard.integer(forKey: attemptsKey) + 1
        UserDefaults.standard.set(attempts, forKey: attemptsKey)
        if attempts >= maxFreeAttempts {
            // 30s after the 5th failure, doubling each further failure, capped at 15 min.
            let delay = min(30 * pow(2, Double(attempts - maxFreeAttempts)), 900)
            UserDefaults.standard.set(Date().timeIntervalSince1970 + delay, forKey: lockoutKey)
        }
        return false
    }

    // MARK: - Biometrics (Face ID / Touch ID)
    private func evaluatedContext() -> LAContext {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context
    }

    var biometricsAvailable: Bool {
        isPINSet && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometricName: String {
        evaluatedContext().biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    var biometricIcon: String {
        evaluatedContext().biometryType == .faceID ? "faceid" : "touchid"
    }

    func authenticateWithBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Unlock CompQuote admin settings") { success, _ in
            DispatchQueue.main.async {
                if success { self.unlock() }
                completion(success)
            }
        }
    }

    // MARK: - Forgot PIN
    /// True when the device has a passcode or biometrics, so a reset can be verified.
    var canResetWithDeviceAuth: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Verifies the device owner (Face ID / Touch ID, falling back to the device passcode).
    /// On success the PIN is removed so a new one can be created. Data is not touched.
    func resetPINWithDeviceAuth(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Reset the CompQuote admin PIN") { success, _ in
            DispatchQueue.main.async {
                if success { self.deletePIN() }
                completion(success)
            }
        }
    }

    // MARK: - Unlock state
    func unlock() {
        isUnlocked = true
        unlockTime = Date()
    }

    // Call this whenever a protected view appears
    func checkTimeout() {
        guard let t = unlockTime else { isUnlocked = false; return }
        if Date().timeIntervalSince(t) > timeoutSeconds {
            isUnlocked = false
            unlockTime = nil
        }
    }

    func lock() {
        isUnlocked = false
        unlockTime = nil
    }
}

// MARK: - PIN Entry View
struct PINEntryView: View {
    let title: String
    let subtitle: String
    let onSuccess: () -> Void
    var onCancel: (() -> Void)? = nil
    var isSetup = false          // true when creating a new PIN
    var allowReset = false       // show "Forgot PIN?" (verify mode only)

    @StateObject private var auth = AdminAuth.shared
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var step: Step = .enter   // .enter or .confirm (setup only)
    @State private var shake = false
    @State private var errorMessage = ""
    @State private var triedBiometrics = false
    @State private var showResetConfirm = false

    enum Step { case enter, confirm }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon + title
            VStack(spacing: 12) {
                Image(systemName: isSetup ? "lock.badge.plus" : "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                Text(isSetup ? (step == .enter ? title : "Confirm PIN") : title)
                    .font(.title2).fontWeight(.bold)
                Text(isSetup ? (step == .enter ? subtitle : "Re-enter your 6-digit PIN") : subtitle)
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // PIN dots
            HStack(spacing: 18) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i < currentPin.count ? (errorMessage.isEmpty ? Color.blue : Color.red) : Color.clear)
                        .overlay(Circle().stroke(i < currentPin.count ? Color.clear : Color(.systemGray3), lineWidth: 1.5))
                        .frame(width: 16, height: 16)
                        .scaleEffect(i < currentPin.count ? 1.15 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: currentPin.count)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(currentPin.count) of 6 digits entered")
            .offset(x: shake ? -10 : 0)
            .animation(shake ? .easeInOut(duration: 0.05).repeatCount(5, autoreverses: true) : .default, value: shake)

            // Error
            Text(errorMessage.isEmpty ? " " : errorMessage)
                .font(.footnote).foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 34, alignment: .top)
                .padding(.top, -16)

            // Number pad
            VStack(spacing: 14) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { num in
                            PINButton(label: "\(num)") { append("\(num)") }
                        }
                    }
                }
                HStack(spacing: 24) {
                    // Face ID / Touch ID sits in the empty corner (verify mode only)
                    if !isSetup && auth.biometricsAvailable {
                        PINButton(label: "", systemImage: auth.biometricIcon, filled: false) {
                            tryBiometrics()
                        }
                        .accessibilityLabel("Unlock with \(auth.biometricName)")
                    } else {
                        Color.clear.frame(width: 76, height: 76)
                            .accessibilityHidden(true)
                    }
                    PINButton(label: "0") { append("0") }
                    PINButton(label: "", systemImage: "delete.left", filled: false) { deleteLast() }
                        .accessibilityLabel("Delete")
                }
            }

            Spacer()

            if allowReset && !isSetup {
                Button("Forgot PIN?") { showResetConfirm = true }
                    .font(.subheadline)
                    .padding(.bottom, onCancel == nil ? 16 : 0)
            }

            if let cancel = onCancel {
                Button("Cancel", action: cancel)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .confirmationDialog("Reset admin PIN?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Verify and Reset PIN", role: .destructive) {
                auth.resetPINWithDeviceAuth { success in
                    if !success {
                        errorMessage = auth.canResetWithDeviceAuth
                            ? "Couldn't verify this device. Try again."
                            : "Set a device passcode in iOS Settings to reset the PIN."
                        triggerShake()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll confirm with Face ID or your device passcode, then create a new PIN. Your data isn't affected.")
        }
        .onAppear {
            // Offer Face ID straight away when verifying (not on every re-render).
            if !isSetup && auth.biometricsAvailable && auth.lockoutRemaining <= 0 && !triedBiometrics {
                triedBiometrics = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tryBiometrics() }
            }
        }
    }

    private func tryBiometrics() {
        auth.authenticateWithBiometrics { success in
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess()
            }
        }
    }

    private var currentPin: String { step == .confirm ? confirmPin : pin }

    private var lockoutMessage: String {
        let secs = Int(auth.lockoutRemaining.rounded(.up))
        return "Too many attempts. Try again in \(secs)s."
    }

    private func append(_ digit: String) {
        errorMessage = ""
        // Block input entirely while locked out (verify mode only).
        if !isSetup, auth.lockoutRemaining > 0 {
            errorMessage = lockoutMessage
            return
        }
        if step == .confirm {
            guard confirmPin.count < 6 else { return }
            confirmPin += digit
            if confirmPin.count == 6 { submitConfirm() }
        } else {
            guard pin.count < 6 else { return }
            pin += digit
            if pin.count == 6 {
                if isSetup { step = .confirm }
                else { submitVerify() }
            }
        }
    }

    private func deleteLast() {
        errorMessage = ""
        if step == .confirm { if !confirmPin.isEmpty { confirmPin.removeLast() } }
        else { if !pin.isEmpty { pin.removeLast() } }
    }

    private func submitVerify() {
        if auth.verify(pin) {
            onSuccess()
        } else if auth.lockoutRemaining > 0 {
            errorMessage = lockoutMessage
            triggerShake(); pin = ""
        } else {
            let left = auth.attemptsBeforeLockout
            errorMessage = left <= 2
                ? "Incorrect PIN. \(left) attempt\(left == 1 ? "" : "s") left before lockout."
                : "Incorrect PIN. Try again."
            triggerShake(); pin = ""
        }
    }

    private func submitConfirm() {
        if confirmPin == pin {
            auth.setPIN(pin)
            onSuccess()
        } else {
            errorMessage = "PINs don't match. Start over."
            triggerShake(); pin = ""; confirmPin = ""; step = .enter
        }
    }

    private func triggerShake() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        shake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shake = false }
    }
}

private struct PINButton: View {
    let label: String
    var systemImage: String? = nil
    var filled = true
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 26, weight: .regular))
                } else {
                    Text(label).font(.system(size: 32, weight: .regular, design: .rounded))
                }
            }
            .foregroundColor(filled ? .primary : .blue)
            .frame(width: 76, height: 76)
            .background(filled ? Color(.secondarySystemGroupedBackground) : Color.clear)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(PINPressStyle())
        .accessibilityLabel(label)
    }
}

private struct PINPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Admin Gate View
// Wraps any view behind PIN authentication.
struct AdminGate<Content: View>: View {
    @StateObject private var auth = AdminAuth.shared
    @State private var showSetup = false
    @State private var passedDangerCheck = false
    let content: () -> Content
    var dangerOnly = false   // if true, always re-prompt even if unlocked

    var body: some View {
        Group {
            if !auth.isPINSet {
                // No PIN yet — prompt to create one
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "lock.badge.plus")
                        .font(.system(size: 56)).foregroundColor(.blue)
                    Text("Set Admin PIN")
                        .font(.title2).fontWeight(.bold)
                    Text("Create a 6-digit PIN to protect Settings.\nYou'll need it each time you open Settings.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button {
                        showSetup = true
                    } label: {
                        Label("Create PIN", systemImage: "lock.badge.plus")
                            .frame(maxWidth: 240)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                }
                .sheet(isPresented: $showSetup) {
                    PINEntryView(
                        title: "Create Admin PIN",
                        subtitle: "Choose a 6-digit PIN to protect Settings",
                        onSuccess: { showSetup = false },
                        isSetup: true
                    )
                    .interactiveDismissDisabled()
                }
            } else if (dangerOnly && !passedDangerCheck) || !auth.isUnlocked {
                // PIN set but locked — show entry
                PINEntryView(
                    title: "Admin Access",
                    subtitle: "Enter your 6-digit PIN to continue",
                    onSuccess: { passedDangerCheck = true },
                    allowReset: true
                )
                .onAppear { auth.checkTimeout() }
            } else {
                // Unlocked — show content
                content()
                    .onAppear { auth.checkTimeout() }
            }
        }
    }
}

// MARK: - Change PIN Flow
// Requires the current PIN before allowing a new one to be set.
struct ChangePINFlow: View {
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var verified = false

    var body: some View {
        if verified {
            PINEntryView(
                title: "Create New PIN",
                subtitle: "Choose a new 6-digit PIN",
                onSuccess: onDone,
                onCancel: onCancel,
                isSetup: true
            )
        } else {
            PINEntryView(
                title: "Verify Current PIN",
                subtitle: "Enter your current 6-digit PIN first",
                onSuccess: { verified = true },
                onCancel: onCancel
            )
        }
    }
}
