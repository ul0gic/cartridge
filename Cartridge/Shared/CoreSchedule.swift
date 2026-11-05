import Darwin

extension CartridgeCoreSchedule {
    var policyName: String {
        switch policy {
        case 0: "unknown"
        case POLICY_TIMESHARE: "timeshare"
        case POLICY_RR: "rr"
        case POLICY_FIFO: "fifo"
        default: String(policy)
        }
    }
}
