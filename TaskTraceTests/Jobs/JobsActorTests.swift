import Foundation
import Testing
@testable import TaskTrace

struct JobsActorTests {
    @Test("initializing the jobs database actor seeds the ActivityUMAP job row")
    func initializingTheJobsDatabaseActorSeedsTheActivityUMAPJobRow() async throws {
        try await withJobsActor { jobsActor, jobsDatabaseActor, _, _, _ in
            _ = jobsActor
            let activityUMAPJob = try await jobsDatabaseActor.loadJob(named: .activityUMAP)
            #expect(activityUMAPJob != nil)
        }
    }

    @Test("initializing the jobs database actor seeds the ActivityTagOntologyRefresh job row")
    func initializingTheJobsDatabaseActorSeedsTheActivityTagOntologyRefreshJobRow() async throws {
        try await withJobsActor { jobsActor, jobsDatabaseActor, _, _, _ in
            _ = jobsActor
            let ontologyRefreshJob = try await jobsDatabaseActor.loadJob(named: .activityTagOntologyRefresh)
            #expect(ontologyRefreshJob != nil)
        }
    }

    @Test("initializing the jobs database actor seeds the GoalTodoDailyMaintenance job row")
    func initializingTheJobsDatabaseActorSeedsTheGoalTodoDailyMaintenanceJobRow() async throws {
        try await withJobsActor { jobsActor, jobsDatabaseActor, _, _, _ in
            _ = jobsActor
            let maintenanceJob = try await jobsDatabaseActor.loadJob(named: .goalTodoDailyMaintenance)
            #expect(maintenanceJob != nil)
        }
    }

    @Test("starting the jobs actor broadcasts due daily job requests")
    func startingTheJobsActorBroadcastsDueDailyJobRequests() async throws {
        try await withJobsActor(
            jobs: [
                JobInput(
                    name: .activityUMAP,
                    schedule: .daily(JobDailyPolicy(hour: 0, minute: 0)),
                    enabled: true
                )
            ]
        ) { jobsActor, _, _, recordingReceiver, _ in
            await jobsActor.start()
            #expect(Set(await recordingReceiver.requestedJobs()) == Set([.activityUMAP, .activityTagOntologyRefresh, .goalTodoDailyMaintenance]))
        }
    }

    @Test("starting the jobs actor stamps a lease on a claimed ActivityUMAP job")
    func startingTheJobsActorStampsALeaseOnAClaimedActivityUMAPJob() async throws {
        try await withJobsActor(
            jobs: [
                JobInput(
                    name: .activityUMAP,
                    schedule: .daily(JobDailyPolicy(hour: 0, minute: 0)),
                    enabled: true
                )
            ]
        ) { jobsActor, jobsDatabaseActor, _, _, _ in
            await jobsActor.start()
            let activityUMAPJob = try #require(try await jobsDatabaseActor.loadJob(named: .activityUMAP))
            #expect(activityUMAPJob.leaseUntil != nil)
        }
    }

    @Test("job success writes the ActivityUMAP last success timestamp")
    func jobSuccessWritesTheActivityUMAPLastSuccessTimestamp() async throws {
        try await withJobsActor(
            jobs: [
                JobInput(
                    name: .activityUMAP,
                    schedule: .daily(JobDailyPolicy(hour: 0, minute: 0)),
                    enabled: true
                )
            ]
        ) { jobsActor, jobsDatabaseActor, actorSystem, _, now in
            await jobsActor.start()
            let finishedAt = now.addingTimeInterval(120)
            await actorSystem.broadcast(
                from: nil,
                message: JobRunSucceeded(
                    jobName: .activityUMAP,
                    finishedAt: finishedAt
                )
            )
            let activityUMAPJob = try #require(try await jobsDatabaseActor.loadJob(named: .activityUMAP))
            #expect(activityUMAPJob.lastSuccessAt == finishedAt)
        }
    }

    @Test("job failure clears the ActivityUMAP lease")
    func jobFailureClearsTheActivityUMAPLease() async throws {
        try await withJobsActor(
            jobs: [
                JobInput(
                    name: .activityUMAP,
                    schedule: .daily(JobDailyPolicy(hour: 0, minute: 0)),
                    enabled: true
                )
            ]
        ) { jobsActor, jobsDatabaseActor, actorSystem, _, now in
            await jobsActor.start()
            await actorSystem.broadcast(
                from: nil,
                message: JobRunFailed(
                    jobName: .activityUMAP,
                    finishedAt: now.addingTimeInterval(120),
                    errorMessage: "ActivityUMAP"
                )
            )
            let activityUMAPJob = try #require(try await jobsDatabaseActor.loadJob(named: .activityUMAP))
            #expect(activityUMAPJob.leaseUntil == nil)
        }
    }

    @Test("job deferral clears the ActivityTagOntologyRefresh lease without writing success")
    func jobDeferralClearsTheActivityTagOntologyRefreshLeaseWithoutWritingSuccess() async throws {
        try await withJobsActor(
            jobs: [
                JobInput(
                    name: .activityTagOntologyRefresh,
                    schedule: .daily(JobDailyPolicy(hour: 0, minute: 10)),
                    enabled: true
                )
            ]
        ) { jobsActor, jobsDatabaseActor, actorSystem, _, now in
            await jobsActor.start()
            await actorSystem.broadcast(
                from: nil,
                message: JobRunDeferred(
                    jobName: .activityTagOntologyRefresh,
                    finishedAt: now.addingTimeInterval(120)
                )
            )
            let ontologyRefreshJob = try #require(
                try await jobsDatabaseActor.loadJob(named: .activityTagOntologyRefresh)
            )

            #expect((ontologyRefreshJob.leaseUntil, ontologyRefreshJob.lastSuccessAt) == (nil, nil))
        }
    }
}

private actor RecordedJobRequests: Receiver {
    private var jobNames: [TaskTraceJobName] = []

    func receive(_ envelope: Envelope) async {
        guard let event = envelope.message as? JobRunRequested else {
            return
        }

        jobNames.append(event.jobName)
    }

    func requestedJobs() -> [TaskTraceJobName] {
        jobNames
    }
}

private func withJobsActor(
    jobs: [JobInput] = [],
    _ block: (JobsActor, JobsDatabaseActor, ActorSystem, RecordedJobRequests, Date) async throws -> Void
) async throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = rootURL.appendingPathComponent("TaskTrace.sqlite")
    let now = Date(timeIntervalSince1970: 1_765_000_000)

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try TaskTraceDatabaseBootstrap.migrate(databaseURL: databaseURL)

    let database = try TaskTraceDatabase(databaseURL: databaseURL)
    let actorSystem = ActorSystem()
    let jobsDatabaseActor = JobsDatabaseActor(database: database)
    let jobsActor = JobsActor(
        jobsDatabaseActor: jobsDatabaseActor,
        actorSystem: actorSystem,
        now: { now },
        checkIntervalNanoseconds: 60_000_000_000,
        leaseDuration: 3_600
    )
    let recordingReceiver = RecordedJobRequests()

    for job in jobs {
        try await jobsDatabaseActor.saveJob(job)
    }

    _ = await actorSystem.register(jobsActor)
    _ = await actorSystem.register(recordingReceiver)

    try await block(jobsActor, jobsDatabaseActor, actorSystem, recordingReceiver, now)
    await jobsActor.stop()
}
