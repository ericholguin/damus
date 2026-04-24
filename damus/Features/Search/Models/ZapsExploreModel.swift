//
//  ZapsExploreModel.swift
//  damus
//

import Foundation

class ZapsExploreModel: ObservableObject {
    let damus_state: DamusState
    @Published var zappings: [Zapping] = []
    @Published var loading: Bool = false

    private let limit: UInt32 = 100
    private let one_week: TimeInterval = 7 * 24 * 60 * 60

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    func load() async {
        DispatchQueue.main.async { self.loading = true }
        await damus_state.nostrNetwork.awaitConnection()

        let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
            .map { $0.url }
            .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }

        var filter = NostrFilter(kinds: [.zap])
        filter.limit = limit
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        filter.since = UInt32(Date.now.timeIntervalSince1970 - one_week)

        for await item in damus_state.nostrNetwork.reader.advancedStream(
            filters: [filter],
            to: to_relays,
            preloadStrategy: .preload
        ) {
            switch item {
            case .event(lender: let lender):
                await lender.justUseACopy({ ev in
                    await self.handle(ev)
                })
            case .eose:
                break
            case .ndbEose:
                DispatchQueue.main.async { self.loading = false }
            case .networkEose:
                break
            }
        }
    }

    @MainActor
    func handle(_ ev: NostrEvent) {
        guard ev.known_kind == .zap,
              let zap = Zap.from_zap_event(
                  zap_ev: ev,
                  zapper: ev.pubkey,
                  our_privkey: damus_state.keypair.privkey
              ),
              case .note = zap.target   // only show note zaps, not profile zaps
        else { return }

        let zapping = Zapping.zap(zap)

        // Deduplicate by request event id
        guard !zappings.contains(where: { $0.request.ev.id == zapping.request.ev.id }) else { return }

        // Insert in descending amount order
        let idx = zappings.firstIndex(where: { $0.amount < zapping.amount }) ?? zappings.endIndex
        zappings.insert(zapping, at: idx)

        if zappings.count > Int(limit) {
            zappings.removeLast()
        }
    }
}
