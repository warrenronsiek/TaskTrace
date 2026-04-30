//
//  JobsActor.swift
//  TaskTrace
//
//  Created by Codex on 4/15/26.
//

import Foundation
import OSLog

actor JobsActor: Receiver {
    private let jobsDatabaseActor: JobsDatabaseActor
    private let actorSystem: ActorSystem
    private let now: @Sendable () -> Date
    private let checkIntervalNanoseconds: UInt64
    private let leaseDuration: TimeInterval
    private let logger = Logger(subsystem: "com.tasktrace.TaskTrace", category: "jobs")
    private var schedulerTask: Task<Void, Never>?

    init(
        jobsDatabaseActor: JobsDatabaseActor,
        actorSystem: ActorSystem,
        now: @escaping @Sendable () -> Date = Date.init,
        checkIntervalNanoseconds: UInt64 = 900_000_000_000,
        leaseDuration: TimeInterval = 3_600
    ) {
        self.jobsDatabaseActor = jobsDatabaseActor
        self.actorSystem = actorSystem
        self.now = now
        self.checkIntervalNanoseconds = checkIntervalNanoseconds
        self.leaseDuration = leaseDuration
    }

    func start() async {
        guard schedulerTask == nil else {
            return
        }

        do {
            try await jobsDatabaseActor.reconcileJobDefinitions(TaskTraceJobName.allCases.map(\.definition))
            await runSchedulerPass()
        } catch {
            logger.error(
                "jobs-actor failed operation=start error=\(String(describing: error), privacy: .public)"
            )
        }

        schedulerTask = Task { [checkIntervalNanoseconds] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: checkIntervalNanoseconds)
                } catch {
                    return
                }

                await self.runSchedulerPass()
            }
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    func runSchedulerPass() async {
        do {
            let dueJobs = try await jobsDatabaseActor.claimDueJobs(
                now: now(),
                leaseDuration: leaseDuration
            )

            for dueJob in dueJobs {
                guard let jobName = TaskTraceJobName(rawValue: dueJob.name),
                      let startedAt = dueJob.lastStartedAt,
                      let leaseUntil = dueJob.leaseUntil else {
                    continue
                }

                logger.log(
                    "jobs-actor dispatching job name=\(jobName.rawValue, privacy: .public) leaseUntil=\(leaseUntil.formatted(TaskTraceDatabase.sqlTimestampStyle), privacy: .public)"
                )

                await actorSystem.broadcast(
                    from: nil,
                    message: JobRunRequested(
                        jobName: jobName,
                        startedAt: startedAt,
                        leaseUntil: leaseUntil
                    )
                )
            }
        } catch {
            logger.error(
                "jobs-actor failed operation=run-scheduler-pass error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as JobRunSucceeded:
            do {
                try await jobsDatabaseActor.markJobSucceeded(
                    name: event.jobName,
                    finishedAt: event.finishedAt
                )
            } catch {
                logger.error(
                    "jobs-actor failed event=job-run-succeeded name=\(event.jobName.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as JobRunDeferred:
            do {
                try await jobsDatabaseActor.markJobDeferred(name: event.jobName)
            } catch {
                logger.error(
                    "jobs-actor failed event=job-run-deferred name=\(event.jobName.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as JobRunFailed:
            do {
                try await jobsDatabaseActor.markJobFailed(name: event.jobName)
            } catch {
                logger.error(
                    "jobs-actor failed event=job-run-failed name=\(event.jobName.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        default:
            return
        }
    }
}
