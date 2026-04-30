//
//  AIStatsStore.swift
//  TaskTrace
//

import Combine
import Darwin
import Foundation

@MainActor
final class AIStatsStore: ObservableObject {
    @Published private(set) var schedulerSnapshots: [AISchedulerStatsSnapshot]
    @Published private(set) var appMemoryFootprintBytes: Int64

    private let schedulerReporter: (any AISchedulerStatsReporting)?
    private let memoryFootprintReader: @Sendable () -> Int64
    private var pollingTask: Task<Void, Never>?

    init(
        schedulerReporter: (any AISchedulerStatsReporting)? = nil,
        previewSchedulerSnapshots: [AISchedulerStatsSnapshot] = [],
        previewAppMemoryFootprintBytes: Int64 = 0,
        memoryFootprintReader: @escaping @Sendable () -> Int64 = AIStatsStore.currentProcessMemoryFootprintBytes
    ) {
        self.schedulerReporter = schedulerReporter
        self.memoryFootprintReader = memoryFootprintReader
        self.schedulerSnapshots = previewSchedulerSnapshots
        self.appMemoryFootprintBytes = previewAppMemoryFootprintBytes
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task {
            while !Task.isCancelled {
                self.schedulerSnapshots = await loadSchedulerSnapshots().sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.appMemoryFootprintBytes = memoryFootprintReader()

                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func stop() {
        // Stop background polling immediately during quit.
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func loadSchedulerSnapshots() async -> [AISchedulerStatsSnapshot] {
        guard let schedulerReporter else {
            return []
        }

        return await schedulerReporter.aiSchedulerSnapshots()
    }

    nonisolated static func currentProcessMemoryFootprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return Int64(info.phys_footprint)
    }

    deinit {
        pollingTask?.cancel()
    }
}
