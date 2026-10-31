/// Release restrictions, intentionally independent of preferences and environment variables.
/// Re-enable only after the corresponding hardening acceptance criteria are verified.
public enum CapabilityAvailability {
    public static let automaticUpdates = false // H14: fork signing, identity, and upgrade verification
    public static let terminalReplies = false // H09: exact destination and agent ownership
    public static let remoteApprovals = false // H10/H11: authenticated encryption and endpoint lifecycle
}
