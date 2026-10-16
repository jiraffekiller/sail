import Foundation

/// Every identifier the app, the helper, launchd and the install scripts agree on.
/// Rename the product here (and in Resources/Info.plist, Makefile) and nowhere else.
public enum SailIDs {
    public static let appName = "Sail"
    /// Shown in the About panel.
    public static let developer = "JiraffeKiller"
    public static let appBundleID = "com.jiraffekiller.sail"
    /// launchd label and Mach service name of the privileged helper.
    public static let helperLabel = "com.jiraffekiller.sail.helper"
    /// launchd label of the per-user LaunchAgent that keeps the app alive.
    public static let agentLabel = "com.jiraffekiller.sail.agent"
    /// Bumped whenever the helper's protocol or behaviour changes.
    public static let helperVersion = 1
    /// os_log subsystem.
    public static let logSubsystem = "com.jiraffekiller.sail"

    public static let helperBinaryPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    public static let helperPlistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
}

/// Where PowerUIAgent keeps the manual charge limit (root's preferences domain).
public enum PowerUIDefaults {
    public static let domain = "com.apple.smartcharging.topoffprotection"
    public static let limitKey = "mclLimitValue"
    public static let featureStateKey = "MCLFeatureState"
    public static let changedNotification = "com.apple.smartcharging.defaultschanged"
}
