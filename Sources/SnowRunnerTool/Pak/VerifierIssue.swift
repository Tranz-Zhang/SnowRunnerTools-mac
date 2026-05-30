public struct VerifierIssue: Equatable {
    public enum Severity: String {
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
