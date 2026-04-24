//  SearchHomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import Foundation


/// The data model for the SearchHome view, typically something global-like
class SearchHomeModel: ObservableObject {
    var events: EventHolder
    var followPackEvents: EventHolder
    @Published var loading: Bool = false
    @Published var reactionCounts: [NoteId: Int] = [:]
    @Published var repostCounts: [NoteId: Int] = [:]
    @Published var topEngagedEvents: [NoteId: NostrEvent] = [:]

    var seen_pubkey: Set<Pubkey> = Set()
    var follow_pack_seen_pubkey: Set<Pubkey> = Set()
    let damus_state: DamusState
    let base_subid = UUID().description
    let follow_pack_subid = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 200
    private let one_week: TimeInterval = 7 * 24 * 60 * 60
    //let multiple_events_per_pubkey: Bool = false
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
        self.followPackEvents = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }
    
    func get_base_filter() -> NostrFilter {
        var filter = NostrFilter(kinds: [.text, .chat])
        filter.limit = self.limit
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        return filter
    }

    func get_engagement_filter() -> NostrFilter {
        var filter = NostrFilter(kinds: [.like, .boost])
        filter.limit = 500
        filter.since = UInt32(Date.now.timeIntervalSince1970 - one_week)
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        return filter
    }
    
    @MainActor
    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }
    
    @MainActor
    func reload() async {
        self.events.reset()
        await self.load()
    }
    
    func load() async {
        DispatchQueue.main.async {
            self.loading = true
        }
        await damus_state.nostrNetwork.awaitConnection()
        
        let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
            .map { $0.url }
            .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }
        
        var follow_list_filter = NostrFilter(kinds: [.follow_list])
        follow_list_filter.until = UInt32(Date.now.timeIntervalSince1970)
        
        for await item in damus_state.nostrNetwork.reader.advancedStream(filters: [get_base_filter(), follow_list_filter, get_engagement_filter()], to: to_relays, preloadStrategy: .preload) {
            switch item {
            case .event(lender: let lender):
                await lender.justUseACopy({ event in
                    await self.handleFollowPackEvent(event)
                    await self.handleEvent(event)
                    await self.handleEngagementEvent(event)
                })
            case .eose:
                break
            case .ndbEose:
                DispatchQueue.main.async {
                    self.loading = false
                }
                Task { await self.loadTopEngagedNotes(to: to_relays) }
            case .networkEose:
                break
            }
        }
    }

    func loadTopEngagedNotes(to relays: [RelayURL]) async {
        let topIds: [NoteId] = await MainActor.run {
            let topReactionIds = reactionCounts.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
            let topRepostIds = repostCounts.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
            return Array(Set(topReactionIds + topRepostIds))
        }
        guard !topIds.isEmpty else { return }

        var missing: [NoteId] = []
        for id in topIds {
            if let note = try? damus_state.ndb.lookup_note_and_copy(id) {
                await MainActor.run { self.topEngagedEvents[id] = note }
            } else {
                missing.append(id)
            }
        }

        guard !missing.isEmpty else {
            await MainActor.run { self.objectWillChange.send() }
            return
        }

        let filter = NostrFilter(ids: missing)
        for await item in damus_state.nostrNetwork.reader.advancedStream(
            filters: [filter],
            to: relays,
            preloadStrategy: .noPreloading
        ) {
            switch item {
            case .event(lender: let lender):
                await lender.justUseACopy { ev in
                    await MainActor.run {
                        self.topEngagedEvents[ev.id] = ev
                        self.objectWillChange.send()
                    }
                }
            case .networkEose:
                return
            default:
                break
            }
        }
    }
    
    @MainActor
    func handleEvent(_ ev: NostrEvent) {
        if ev.is_textlike && should_show_event(state: damus_state, ev: ev) && !ev.is_reply() {
            if !damus_state.settings.multiple_events_per_pubkey && seen_pubkey.contains(ev.pubkey) {
                return
            }
            seen_pubkey.insert(ev.pubkey)
            
            if self.events.insert(ev) {
                self.objectWillChange.send()
            }
        }
    }
    
    @MainActor
    func handleEngagementEvent(_ ev: NostrEvent) {
        guard let target_id = ev.referenced_ids.first else { return }
        switch ev.known_kind {
        case .like:
            reactionCounts[target_id, default: 0] += 1
        case .boost:
            repostCounts[target_id, default: 0] += 1
        default:
            return
        }
        self.objectWillChange.send()
    }

    @MainActor
    func handleFollowPackEvent(_ ev: NostrEvent) {
        if ev.known_kind == .follow_list && should_show_event(state: damus_state, ev: ev) && !ev.is_reply() {
            if !damus_state.settings.multiple_events_per_pubkey && follow_pack_seen_pubkey.contains(ev.pubkey) {
                return
            }
            follow_pack_seen_pubkey.insert(ev.pubkey)
            
            if self.followPackEvents.insert(ev) {
                self.objectWillChange.send()
            }
        }
    }
}

func find_profiles_to_fetch(profiles: Profiles, load: PubkeysToLoad, cache: EventCache) -> [Pubkey] {
    switch load {
    case .from_events(let events):
        return find_profiles_to_fetch_from_events(profiles: profiles, events: events, cache: cache)
    case .from_keys(let pks):
        return find_profiles_to_fetch_from_keys(profiles: profiles, pks: pks)
    }
}

func find_profiles_to_fetch_from_keys(profiles: Profiles, pks: [Pubkey]) -> [Pubkey] {
    Array(Set(pks.filter { pk in
        let has_fresh_profile = (try? profiles.has_fresh_profile(id: pk)) ?? false
        return !has_fresh_profile
    }))
}

func find_profiles_to_fetch_from_events(profiles: Profiles, events: [NostrEvent], cache: EventCache) -> [Pubkey] {
    var pubkeys = Set<Pubkey>()

    for ev in events {
        // lookup profiles from boosted events
        if ev.known_kind == .boost,
            let bev = ev.get_inner_event(cache: cache),
            let has_fresh_profiles = try? profiles.has_fresh_profile(id: bev.pubkey),
            !has_fresh_profiles {
            pubkeys.insert(bev.pubkey)
        }
        
        if let has_fresh_profiles = try? profiles.has_fresh_profile(id: ev.pubkey), !has_fresh_profiles {
            pubkeys.insert(ev.pubkey)
        }
    }
    
    return Array(pubkeys)
}

enum PubkeysToLoad {
    case from_events([NostrEvent])
    case from_keys([Pubkey])
}
