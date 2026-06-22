public struct VerifierIssue: Equatable, Sendable {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public let severity: Severity
    public let code: String
    public let message: String

    public init(severity: Severity = .error, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}
