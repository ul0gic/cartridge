import Darwin

enum RealTimePolicy {
    // OpenEmu applies 7 ms computation and 30 ms constraint to every core (OEGameCore.m:236).
    private static let computationNs: UInt64 = 7_000_000
    private static let constraintNs: UInt64 = 30_000_000
    private static let roleNames: [Int32: String] = [
        TASK_UNSPECIFIED.rawValue: "unspecified",
        TASK_FOREGROUND_APPLICATION.rawValue: "foreground",
        TASK_BACKGROUND_APPLICATION.rawValue: "background",
        TASK_CONTROL_APPLICATION.rawValue: "control",
        TASK_GRAPHICS_SERVER.rawValue: "graphics",
        TASK_THROTTLE_APPLICATION.rawValue: "throttle",
        TASK_NONUI_APPLICATION.rawValue: "nonui",
        TASK_DEFAULT_APPLICATION.rawValue: "default",
        TASK_DARWINBG_APPLICATION.rawValue: "darwinbg",
        TASK_USER_INIT_APPLICATION.rawValue: "user-init",
    ]

    static func apply(periodNs: UInt64) -> kern_return_t {
        var policy = thread_time_constraint_policy_data_t(
            period: FramePacing.ticks(fromNs: periodNs),
            computation: FramePacing.ticks(fromNs: computationNs),
            constraint: FramePacing.ticks(fromNs: constraintNs),
            preemptible: 1
        )
        let count = MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size
        return withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: count) {
                thread_policy_set(
                    pthread_mach_thread_np(pthread_self()),
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    $0,
                    mach_msg_type_number_t(count)
                )
            }
        }
    }

    static func applyStandard() -> kern_return_t {
        var policy = thread_standard_policy_data_t()
        return withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: 1) {
                thread_policy_set(
                    pthread_mach_thread_np(pthread_self()),
                    thread_policy_flavor_t(THREAD_STANDARD_POLICY),
                    $0,
                    mach_msg_type_number_t(THREAD_STANDARD_POLICY_COUNT)
                )
            }
        }
    }

    static func currentSchedule() -> CartridgeCoreSchedule? {
        extendedInfo().map { CartridgeCoreSchedule(policy: $0.pth_policy, priority: $0.pth_curpri) }
    }

    static func roleSummary() -> String {
        let role = taskRole().map(name(of:)) ?? "unknown"
        guard let info = extendedInfo() else {
            return "role=\(role) thread=unknown"
        }
        let schedule = CartridgeCoreSchedule(policy: info.pth_policy, priority: info.pth_curpri)
        // A darwinbg or lowpri-suppressed task clamps every thread to MAXPRI_THROTTLE, 4 (xnu task_policy.c:1249-1252).
        return """
        role=\(role) maxpri=\(info.pth_maxpriority) basepri=\(info.pth_priority) \
        policy=\(schedule.policyName) curpri=\(info.pth_curpri)
        """
    }

    private static func extendedInfo() -> thread_extended_info_data_t? {
        var info = thread_extended_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                thread_info(pthread_mach_thread_np(pthread_self()), thread_flavor_t(THREAD_EXTENDED_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private static func taskRole() -> task_role_t? {
        var policy = task_category_policy_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_category_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        var getDefault: boolean_t = 0
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_policy_get(mach_task_self_, task_policy_flavor_t(TASK_CATEGORY_POLICY), $0, &count, &getDefault)
            }
        }
        return result == KERN_SUCCESS ? policy.role : nil
    }

    private static func name(of role: task_role_t) -> String {
        roleNames[role.rawValue] ?? String(role.rawValue)
    }
}
