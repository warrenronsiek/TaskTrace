//
//  KnowledgePipelineBootstrap.swift
//  TaskTrace
//
//  Created by Codex on 4/7/26.
//

import Foundation

enum KnowledgePipelineBootstrap {
    static func register(
        actorSystem: ActorSystem,
        knowledgeGraphActor: KnowledgeGraphActor,
        knowledgeDatabaseActor: KnowledgeDatabaseActor,
        knowledgeBuildTrackerActor: KnowledgeBuildTrackerActor,
        knowledgeCommunityDetectionActor: KnowledgeCommunityDetectionActor,
        knowledgeChunkGraphActor: KnowledgeChunkGraphActor,
        coalesceKnowledgeNodeActor: CoalesceKnowledgeNodeActor,
        coalesceKnowledgeEdgeActor: CoalesceKnowledgeEdgeActor,
        knowledgeNodeEmbeddingActor: KnowledgeNodeEmbeddingActor,
        knowledgeCommunitySummaryActor: KnowledgeCommunitySummaryActor,
        knowledgeCommunityEmbeddingActor: KnowledgeCommunityEmbeddingActor,
        knowledgeObsidianWriterActor: KnowledgeObsidianWriterActor,
        knowledgeClaimEmbeddingActor: KnowledgeClaimEmbeddingActor
    ) async {
        _ = await actorSystem.register(knowledgeGraphActor)
        _ = await actorSystem.register(knowledgeBuildTrackerActor)
        _ = await actorSystem.register(knowledgeCommunityDetectionActor)
        _ = await actorSystem.register(knowledgeDatabaseActor)
        _ = await actorSystem.register(knowledgeChunkGraphActor)
        _ = await actorSystem.register(coalesceKnowledgeNodeActor)
        _ = await actorSystem.register(coalesceKnowledgeEdgeActor)
        _ = await actorSystem.register(knowledgeNodeEmbeddingActor)
        _ = await actorSystem.register(knowledgeCommunitySummaryActor)
        _ = await actorSystem.register(knowledgeCommunityEmbeddingActor)
        _ = await actorSystem.register(knowledgeObsidianWriterActor)
        _ = await actorSystem.register(knowledgeClaimEmbeddingActor)
    }
}
