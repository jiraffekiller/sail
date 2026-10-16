import Foundation

/// XPC interface of the privileged helper. Deliberately tiny: the helper can set the
/// charge limit, read it back and report its version. Nothing else runs as root.
@objc public protocol SailHelperProtocol {
    /// Writes `percent` (1...100) as the manual charge limit and tells PowerUIAgent to
    /// re-read its preferences. Reply: success flag and an error message (empty on success).
    func setChargeLimit(_ percent: Int, withReply reply: @escaping (Bool, String) -> Void)

    /// Reads the stored limit and feature state back. Reply: limit (0 if unset), MCL enabled.
    func getChargeLimit(withReply reply: @escaping (Int, Bool) -> Void)

    /// Reply: `SailIDs.helperVersion` of the installed helper.
    func getVersion(withReply reply: @escaping (Int) -> Void)
}
