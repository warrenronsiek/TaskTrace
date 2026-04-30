//
//  ActivityWorkerDependencies.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation

struct ActivityWorkerDependencies: Sendable {
    let makeActivityEmbeddingActor: @Sendable (ActorSystem) -> ActivityEmbeddingActor
    let makeDescribeImageActor: @Sendable (ActorSystem) -> DescribeImageActor
    let makeReadScreenshotTextActor: @Sendable (ActorSystem) -> ReadScreenshotTextActor
    let makeSummarizeScreenshotActor: @Sendable (ActorSystem) -> SummarizeScreenshotActor
    let makeSummarizeActivityActor: @Sendable (ActorSystem) -> SummarizeActivityActor
    let makeActivityTagOntologyActor: @Sendable (ActorSystem, ActivityDatabaseActor) -> ActivityTagOntologyActor
    let makeOntologyOverviewActor: @Sendable (ActorSystem, OverviewDatabaseActor) -> OntologyOverviewActor
    let makeMergeOverviewsActor: @Sendable (ActorSystem) -> MergeOverviewsActor

    init(
        makeActivityEmbeddingActor: @escaping @Sendable (ActorSystem) -> ActivityEmbeddingActor,
        makeDescribeImageActor: @escaping @Sendable (ActorSystem) -> DescribeImageActor,
        makeReadScreenshotTextActor: @escaping @Sendable (ActorSystem) -> ReadScreenshotTextActor,
        makeSummarizeScreenshotActor: @escaping @Sendable (ActorSystem) -> SummarizeScreenshotActor,
        makeSummarizeActivityActor: @escaping @Sendable (ActorSystem) -> SummarizeActivityActor,
        makeActivityTagOntologyActor: @escaping @Sendable (ActorSystem, ActivityDatabaseActor) -> ActivityTagOntologyActor,
        makeOntologyOverviewActor: @escaping @Sendable (ActorSystem, OverviewDatabaseActor) -> OntologyOverviewActor,
        makeMergeOverviewsActor: @escaping @Sendable (ActorSystem) -> MergeOverviewsActor
    ) {
        self.makeActivityEmbeddingActor = makeActivityEmbeddingActor
        self.makeDescribeImageActor = makeDescribeImageActor
        self.makeReadScreenshotTextActor = makeReadScreenshotTextActor
        self.makeSummarizeScreenshotActor = makeSummarizeScreenshotActor
        self.makeSummarizeActivityActor = makeSummarizeActivityActor
        self.makeActivityTagOntologyActor = makeActivityTagOntologyActor
        self.makeOntologyOverviewActor = makeOntologyOverviewActor
        self.makeMergeOverviewsActor = makeMergeOverviewsActor
    }

    init(activityAI: any ActivityAIOperating) {
        self.init(
            makeActivityEmbeddingActor: { actorSystem in
                ActivityEmbeddingActor(
                    actorSystem: actorSystem,
                    embeddingGenerator: activityAI as? any ActivityEmbeddingGenerating
                )
            },
            makeDescribeImageActor: { DescribeImageActor(actorSystem: $0, imageDescriber: activityAI) },
            makeReadScreenshotTextActor: { ReadScreenshotTextActor(actorSystem: $0, screenshotTextRecognizer: activityAI) },
            makeSummarizeScreenshotActor: { SummarizeScreenshotActor(actorSystem: $0, screenshotSummarizer: activityAI) },
            makeSummarizeActivityActor: { SummarizeActivityActor(actorSystem: $0, summarizer: activityAI) },
            makeActivityTagOntologyActor: { ActivityTagOntologyActor(actorSystem: $0, activityDatabaseActor: $1) },
            makeOntologyOverviewActor: {
                OntologyOverviewActor(
                    actorSystem: $0,
                    overviewDatabaseActor: $1,
                    textResponder: activityAI as? any AITextResponding
                )
            },
            makeMergeOverviewsActor: { MergeOverviewsActor(actorSystem: $0, overviewMerger: activityAI) }
        )
    }

    static func production() -> ActivityWorkerDependencies {
        ActivityWorkerDependencies(
            makeActivityEmbeddingActor: { ActivityEmbeddingActor(actorSystem: $0) },
            makeDescribeImageActor: { DescribeImageActor(actorSystem: $0) },
            makeReadScreenshotTextActor: { ReadScreenshotTextActor(actorSystem: $0) },
            makeSummarizeScreenshotActor: { SummarizeScreenshotActor(actorSystem: $0) },
            makeSummarizeActivityActor: { SummarizeActivityActor(actorSystem: $0) },
            makeActivityTagOntologyActor: { ActivityTagOntologyActor(actorSystem: $0, activityDatabaseActor: $1) },
            makeOntologyOverviewActor: { OntologyOverviewActor(actorSystem: $0, overviewDatabaseActor: $1) },
            makeMergeOverviewsActor: { MergeOverviewsActor(actorSystem: $0) }
        )
    }
}
