import Foundation
import SailCore
import os

enum Log {
    static let app = Logger(subsystem: SailIDs.logSubsystem, category: "app")
    static let control = Logger(subsystem: SailIDs.logSubsystem, category: "control")
}
