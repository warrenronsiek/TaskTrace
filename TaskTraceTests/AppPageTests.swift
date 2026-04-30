//
//  AppPageTests.swift
//  TaskTraceTests
//
//  Created by Codex on 4/23/26.
//

import Testing
@testable import TaskTrace

@MainActor
struct AppPageTests {
    @Test("local builds show stats page")
    func localBuildsShowStatsPage() {
        #expect(ContentView.AppPage.sidebarPages(bundleIdentifier: "com.tasktrace.TaskTrace.local").contains(.stats))
    }

    @Test("dev builds show stats page")
    func devBuildsShowStatsPage() {
        #expect(ContentView.AppPage.sidebarPages(bundleIdentifier: "com.tasktrace.TaskTrace.dev").contains(.stats))
    }

    @Test("production builds show stats page")
    func productionBuildsShowStatsPage() {
        #expect(ContentView.AppPage.sidebarPages(bundleIdentifier: "com.tasktrace.TaskTrace").contains(.stats))
    }

    @Test("production builds use consumer stats copy")
    func productionBuildsUseConsumerStatsCopy() {
        #expect(Vars.statsViewUsesConsumerText(forBundleIdentifier: "com.tasktrace.TaskTrace"))
    }

    @Test("local builds use developer stats copy")
    func localBuildsUseDeveloperStatsCopy() {
        #expect(!Vars.statsViewUsesConsumerText(forBundleIdentifier: "com.tasktrace.TaskTrace.local"))
    }

    @Test("production stats copy maps text scheduler names")
    func productionStatsCopyMapsTextSchedulerNames() {
        let copy = StatsViewDisplayCopy(bundleIdentifier: "com.tasktrace.TaskTrace")

        #expect(copy.schedulerName(id: AIModelSchedulerKind.textBig.rawValue, fallback: "Text Big") == "Detailed text processing")
    }

    @Test("production stats copy maps knowledge graph work")
    func productionStatsCopyMapsKnowledgeGraphWork() {
        let copy = StatsViewDisplayCopy(bundleIdentifier: "com.tasktrace.TaskTrace")

        #expect(copy.telemetryLabel("knowledge-chunk-graph") == "Knowledge graph updates")
    }

    @Test("local stats copy preserves raw work keys")
    func localStatsCopyPreservesRawWorkKeys() {
        let copy = StatsViewDisplayCopy(bundleIdentifier: "com.tasktrace.TaskTrace.local")

        #expect(copy.telemetryLabel("knowledge-chunk-graph") == "knowledge-chunk-graph")
    }
}
