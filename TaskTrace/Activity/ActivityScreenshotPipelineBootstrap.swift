//
//  ActivityScreenshotPipelineBootstrap.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

enum ActivityScreenshotPipelineBootstrap {
    static func register(
        actorSystem: ActorSystem,
        activityActor: ActivityActor,
        activityDatabaseActor: ActivityDatabaseActor,
        dependencies: ActivityWorkerDependencies
    ) async {
        _ = await actorSystem.register(activityActor)
        _ = await actorSystem.register(dependencies.makeActivityEmbeddingActor(actorSystem))
        _ = await actorSystem.register(dependencies.makeDescribeImageActor(actorSystem))
        _ = await actorSystem.register(dependencies.makeReadScreenshotTextActor(actorSystem))
        _ = await actorSystem.register(dependencies.makeSummarizeScreenshotActor(actorSystem))
        _ = await actorSystem.register(dependencies.makeSummarizeActivityActor(actorSystem))
        _ = await actorSystem.register(dependencies.makeActivityTagOntologyActor(actorSystem, activityDatabaseActor))
        _ = await actorSystem.register(activityDatabaseActor)
    }
}
