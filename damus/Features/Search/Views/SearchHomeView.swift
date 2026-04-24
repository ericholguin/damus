//
//  SearchHomeView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI
import CryptoKit
import NaturalLanguage

enum SearchExploreTab: Int, CaseIterable, Hashable {
    case trending = 0
    case news = 1
    case sports = 2
    case entertainment = 3
    case zaps = 4

    var title: String {
        switch self {
        case .trending:      return NSLocalizedString("Trending", comment: "Tab label for trending content in explore view")
        case .news:          return NSLocalizedString("News", comment: "Tab label for news content in explore view")
        case .sports:        return NSLocalizedString("Sports", comment: "Tab label for sports content in explore view")
        case .entertainment: return NSLocalizedString("Entertainment", comment: "Tab label for entertainment content in explore view")
        case .zaps:          return NSLocalizedString("Zaps", comment: "Tab label for zaps content in explore view")
        }
    }

    var hashtags: Set<String> {
        switch self {
        case .trending, .zaps:
            return []
        case .news:
            return ["news", "politics", "bitcoin", "finance", "economy", "world", "breaking"]
        case .sports:
            return ["sports", "football", "basketball", "soccer", "tennis", "fitness", "nfl", "nba"]
        case .entertainment:
            return ["music", "art", "memes", "movies", "gaming", "film", "comedy", "tv"]
        }
    }
}

private struct TrendingSnapshot {
    let hashtags: [(hashtag: String, count: Int)]
    let suggestedPubkeys: [Pubkey]
}

struct SearchHomeView: View {
    let damus_state: DamusState
    @StateObject var model: SearchHomeModel
    @StateObject var zapsModel: ZapsExploreModel
    @State var search: String = ""
    @State var tab_selection: SearchExploreTab = .trending
    @State private var trendingSnapshot: TrendingSnapshot? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    init(damus_state: DamusState, model: SearchHomeModel) {
        self.damus_state = damus_state
        self._model = StateObject(wrappedValue: model)
        self._zapsModel = StateObject(wrappedValue: ZapsExploreModel(damus_state: damus_state))
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }

    // MARK: - Computed engagement data

    var trendingHashtags: [(hashtag: String, count: Int)] {
        var counts: [String: Set<Pubkey>] = [:]
        for ev in model.events.all_events {
            for ht in ev.referenced_hashtags {
                let tag = ht.hashtag.lowercased()
                counts[tag, default: Set()].insert(ev.pubkey)
            }
        }
        return counts
            .map { (hashtag: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    var topReactedEvents: [(NostrEvent, Int)] {
        model.reactionCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { (noteId, count) -> (NostrEvent, Int)? in
                guard let note = model.topEngagedEvents[noteId] else { return nil }
                return (note, count)
            }
    }

    var topRepostedEvents: [(NostrEvent, Int)] {
        model.repostCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { (noteId, count) -> (NostrEvent, Int)? in
                guard let note = model.topEngagedEvents[noteId] else { return nil }
                return (note, count)
            }
    }

    var suggestedPubkeys: [Pubkey] {
        var seen = Set<Pubkey>()
        var result: [Pubkey] = []
        for ev in model.followPackEvents.all_events {
            let pack = FollowPackEvent.parse(from: ev)
            for pk in pack.publicKeys {
                guard !seen.contains(pk), pk != damus_state.pubkey else { continue }
                seen.insert(pk)
                result.append(pk)
                if result.count >= 10 { return result }
            }
        }
        return result
    }

    fileprivate func makeTrendingSnapshot() -> TrendingSnapshot {
        TrendingSnapshot(
            hashtags: trendingHashtags,
            suggestedPubkeys: suggestedPubkeys
        )
    }

    var filteredTabEvents: [NostrEvent] {
        let hashtags = tab_selection.hashtags
        let baseFilter = content_filter(FilterState.posts)
        return model.events.all_events.filter { ev in
            baseFilter(ev) &&
            ev.referenced_hashtags.contains(where: { hashtags.contains($0.hashtag.lowercased()) })
        }
    }

    // MARK: - Search input

    var SearchInput: some View {
        HStack {
            HStack {
                Image("search")
                    .foregroundColor(.gray)
                TextField(NSLocalizedString("Search...", comment: "Placeholder text to prompt entry of search query."), text: $search)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(20)

            if !search.isEmpty {
                Text("Cancel", comment: "Cancel out of search view.")
                    .foregroundColor(.accentColor)
                    .padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 10.0))
                    .onTapGesture {
                        self.search = ""
                        isFocused = false
                    }
            }
        }
    }

    // MARK: - Tabs bar

    var TabsBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                CustomPicker(
                    tabs: SearchExploreTab.allCases.map { ($0.title, $0) },
                    selection: $tab_selection
                )
                .padding(.horizontal)
            }
            Divider()
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    // MARK: - Trending tab sections

    var TrendingHashtagsSection: some View {
        let items = trendingSnapshot?.hashtags ?? []
        return VStack(alignment: .leading, spacing: 0) {
            ExploreSectionHeader(
                icon: "number",
                title: NSLocalizedString("Trending Hashtags", comment: "Section header for trending hashtags"),
                color: DamusColors.purple
            )

            if items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(items, id: \.hashtag) { item in
                    Button(action: {
                        let search_model = SearchModel(state: damus_state, search: NostrFilter(hashtag: [item.hashtag]))
                        damus_state.nav.push(route: Route.Search(search: search_model))
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "#\(item.hashtag)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                let count_str = pluralizedString(key: "users_talking_about_it", count: item.count)
                                Text(count_str)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    Divider()
                        .padding(.leading)
                }
            }
        }
    }

    var MostLikedSection: some View {
        let posts = topReactedEvents
        return Group {
            if !posts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ExploreSectionHeader(
                        icon: "heart.fill",
                        title: NSLocalizedString("Most Liked This Week", comment: "Section header for most liked posts"),
                        color: .pink
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(posts, id: \.0.id) { (ev, count) in
                                LikedPostCard(damus_state: damus_state, event: ev, count: count)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    var MostRepostedSection: some View {
        let posts = topRepostedEvents
        return Group {
            if !posts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ExploreSectionHeader(
                        icon: "arrow.2.squarepath",
                        title: NSLocalizedString("Most Reposted This Week", comment: "Section header for most reposted posts"),
                        color: DamusColors.green
                    )
                    ForEach(posts, id: \.0.id) { (ev, count) in
                        EngagementPostRow(
                            damus_state: damus_state,
                            event: ev,
                            metric: "\(count)",
                            icon: "arrow.2.squarepath",
                            iconColor: DamusColors.green
                        )
                    }
                }
            }
        }
    }

    var WhoToFollowSection: some View {
        let pubkeys = trendingSnapshot?.suggestedPubkeys ?? []
        return Group {
            if !pubkeys.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ExploreSectionHeader(
                        icon: "person.2.fill",
                        title: NSLocalizedString("Who to Follow", comment: "Section title for suggested users to follow in explore view"),
                        color: DamusColors.blue
                    )
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(pubkeys, id: \.self) { pk in
                                WhoToFollowCard(damus_state: damus_state, pubkey: pk)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    // MARK: - Tab content

    var TrendingContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TrendingHashtagsSection
                Divider().padding(.vertical, 8)
                MostLikedSection
                Divider().padding(.vertical, 8)
                MostRepostedSection
                Divider().padding(.vertical, 8)
                WhoToFollowSection
                    .padding(.bottom, 50)
            }
        }
    }

    var CategoryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let events = filteredTabEvents
                if events.isEmpty && !model.loading {
                    VStack {
                        Text("No posts found for this category", comment: "Empty state message for category tab in explore view")
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(events, id: \.id) { ev in
                        EventView(damus: damus_state, event: ev)
                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
        }
    }

    var ZapsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if zapsModel.loading && zapsModel.zappings.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if zapsModel.zappings.isEmpty {
                    Text("No zaps found", comment: "Empty state for the global zaps explore tab")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(zapsModel.zappings, id: \.request.ev.id) { zapping in
                        ZapsExploreRow(damus: damus_state, zapping: zapping)
                        Divider()
                    }
                }
            }
        }
    }

    var GlobalContent: some View {
        Group {
            switch tab_selection {
            case .trending:
                TrendingContent
            case .zaps:
                ZapsContent
            default:
                CategoryContent
            }
        }
    }

    var SearchContent: some View {
        SearchResultsView(damus_state: damus_state, search: $search)
    }

    var MainContent: some View {
        Group {
            if search.isEmpty {
                GlobalContent
            } else {
                SearchContent
            }
        }
    }

    var body: some View {
        VStack {
            MainContent
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                SearchInput
                    .padding()
                Divider()
                if search.isEmpty {
                    TabsBar
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .onReceive(handle_notify(.new_mutes)) { _ in
            self.model.filter_muted()
        }
        .onChange(of: model.loading) { loading in
            guard !loading else { return }
            trendingSnapshot = makeTrendingSnapshot()
        }
        .task {
            await model.load()
        }
        .task {
            await zapsModel.load()
        }
    }
}

// MARK: - Shared section header

private struct ExploreSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.headline).bold()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Most Liked card (horizontal scroll)

private struct LikedPostCard: View {
    let damus_state: DamusState
    let event: NostrEvent
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.footnote)
                    .foregroundColor(.pink)
                Text("\(count)")
                    .font(.footnote.bold())
                    .foregroundColor(.pink)
            }

            HStack(spacing: 6) {
                ProfilePicView(
                    pubkey: event.pubkey,
                    size: 28,
                    highlight: .none,
                    profiles: damus_state.profiles,
                    disable_animation: damus_state.settings.disable_animation,
                    damusState: damus_state
                )
                ProfileName(pubkey: event.pubkey, damus: damus_state, show_nip5_domain: false)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(event.content)
                .font(.caption)
                .lineLimit(4)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(12)
        .frame(width: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.1))
        )
        .onTapGesture {
            let thread = ThreadModel(event: event, damus_state: damus_state)
            damus_state.nav.push(route: Route.Thread(thread: thread))
        }
    }
}

// MARK: - Most Reposted row

private struct EngagementPostRow: View {
    let damus_state: DamusState
    let event: NostrEvent
    let metric: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundColor(iconColor)
                Text(metric)
                    .font(.footnote.bold())
                    .foregroundColor(iconColor)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            EventView(damus: damus_state, event: event)
            Divider().padding(.leading, 70)
        }
    }
}

// MARK: - Who to Follow card

private struct WhoToFollowCard: View {
    let damus_state: DamusState
    let pubkey: Pubkey

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ProfilePicView(
                pubkey: pubkey,
                size: 60,
                highlight: .none,
                profiles: damus_state.profiles,
                disable_animation: damus_state.settings.disable_animation,
                damusState: damus_state
            )

            ProfileName(pubkey: pubkey, damus: damus_state, show_nip5_domain: false)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 120)
                .multilineTextAlignment(.center)

            FollowButtonView(
                target: .pubkey(pubkey),
                follows_you: false,
                follow_state: damus_state.contacts.follow_state(pubkey)
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.1))
        )
        .onTapGesture {
            damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
        }
    }
}

// MARK: - Zaps explore row (shows zap + target note as a quote)

private struct ZapsExploreRow: View {
    let damus: DamusState
    let zapping: Zapping
    @State private var targetNote: NostrEvent? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZapEvent(damus: damus, zap: zapping, is_top_zap: false)
                .padding()

            if let note = targetNote {
                EventView(damus: damus, event: note, options: .embedded)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
        }
        .task {
            guard case .note(let noteTarget) = zapping.target else { return }
            targetNote = try? damus.ndb.lookup_note_and_copy(noteTarget.note_id)
        }
    }
}

struct SearchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        SearchHomeView(damus_state: state, model: SearchHomeModel(damus_state: state))
    }
}
