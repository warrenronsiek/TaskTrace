//
//  OverviewPipelineBootstrap.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

enum OverviewPipelineBootstrap {
    static func register(
        actorSystem: ActorSystem,
        overviewActor: OverviewActor,
        overviewDatabaseActor: OverviewDatabaseActor,
        dependencies: ActivityWorkerDependencies
    ) async {
        _ = await actorSystem.register(overviewActor)
        _ = await actorSystem.register(dependencies.makeOntologyOverviewActor(actorSystem, overviewDatabaseActor))
        _ = await actorSystem.register(dependencies.makeMergeOverviewsActor(actorSystem))
        _ = await actorSystem.register(overviewDatabaseActor)
    }
}
