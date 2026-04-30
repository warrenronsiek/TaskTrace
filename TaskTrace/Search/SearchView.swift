//
//  SearchView.swift
//  TaskTrace
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

struct SearchView: View {
    @ObservedObject var searchStore: SearchStore

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer(minLength: 0)

                        if let activeStage = searchStore.progress.activeStage {
                            SearchStatusView(stage: activeStage)
                                .frame(maxWidth: 460)
                        } else {
                            HStack(spacing: 12) {
                                TextField("Search activities, screenshots, and overviews", text: $searchStore.query)
                                    .textFieldStyle(.plain)
                                    .font(Styles.Fonts.subheadline)
                                    .onSubmit {
                                        Task {
                                            await searchStore.search()
                                        }
                                    }

                                Button {
                                    Task {
                                        await searchStore.search()
                                    }
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(Styles.Fonts.subheadlineSemibold)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(AppColors.chipBackground, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(searchStore.isSearching)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .frame(maxWidth: 460)
                        }

                        Spacer(minLength: 0)
                    }
                }

                if let errorMessage = searchStore.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.danger)
                } else if searchStore.hasSearched && !searchStore.isSearching && searchStore.results.isEmpty {
                    Text("No search results.")
                        .foregroundStyle(AppColors.textSecondary)
                } else if !searchStore.results.isEmpty {
                    GeometryReader { resultsGeometry in
                        let summaryHeight = min(max(resultsGeometry.size.height * 0.30, 160), 280)
                        let webViewHeight = max(resultsGeometry.size.height - summaryHeight - 16, 0)

                        VStack(alignment: .leading, spacing: 16) {
                            TaskTraceWebView(
                                payload: .searchResults(searchStore.results)
                            )
                                .frame(maxWidth: .infinity)
                                .frame(height: webViewHeight)
                                .background(AppColors.insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            SearchSummaryView(
                                summaryText: searchStore.searchSummaryText,
                                isStreaming: searchStore.isSearching || searchStore.progress.status(for: .searchSummary) == .active
                            )
                                .frame(maxWidth: .infinity)
                                .frame(height: summaryHeight)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .navigationTitle("Search")
    }
}

private struct SearchStatusView: View {
    let stage: SearchProgressStage

    var body: some View {
        let phrase = {
            switch stage {
            case .firstPassKeywordize:
                "Distilling tachyons"
            case .firstPassSearch:
                "Fracking timelines"
            case .secondPassKeywordize:
                "Crushing chronovores"
            case .secondPassSearch:
                "Unspooling causality"
            case .reranking:
                "Polishing relevance"
            case .searchSummary:
                "Weaving the answer"
            }
        }()

        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let progress = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.2) / 2.2

                    Text(phrase)
                        .font(Styles.Fonts.subheadlineSemibold)
                        .foregroundStyle(AppColors.textPrimary.opacity(0.72))
                        .overlay {
                            GeometryReader { geometry in
                                let waveWidth = max(geometry.size.width * 0.42, 56)
                                LinearGradient(
                                    colors: [
                                        AppColors.textPrimary.opacity(0),
                                        AppColors.accent.opacity(0.35),
                                        AppColors.accent,
                                        AppColors.textPrimary
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: waveWidth)
                                .offset(x: (geometry.size.width + waveWidth) * progress - waveWidth)
                            }
                            .mask(
                                Text(phrase)
                                    .font(Styles.Fonts.subheadlineSemibold)
                            )
                        }
                }

                Text(stage.title)
                    .font(Styles.Fonts.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(Styles.Fonts.subheadlineSemibold)
                .foregroundStyle(AppColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SearchSummaryView: View {
    let summaryText: String?
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Search Summary")
                    .font(Styles.Fonts.headline)

                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let summaryText, !summaryText.isEmpty {
                ScrollView {
                    Text(summaryText)
                        .font(Styles.Fonts.subheadline)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if isStreaming {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Summarizing the top ranked results...")
                            .font(Styles.Fonts.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Summary unavailable.")
                        .font(Styles.Fonts.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
