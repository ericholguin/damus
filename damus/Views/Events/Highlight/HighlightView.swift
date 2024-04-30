//
//  HighlightView.swift
//  damus
//
//  Created by eric on 4/22/24.
//

import SwiftUI
import Kingfisher

struct HighlightBodyView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions

    init(state: DamusState, ev: HighlightEvent, options: EventViewOptions) {
        self.state = state
        self.event = ev
        self.options = options
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: ev)
        self.options = options
    }

    var body: some View {
        Group {
            if options.contains(.wide) {
                Main.padding(.horizontal)
            } else {
                Main
            }
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                var attributedString: AttributedString {
                    var attributedString = AttributedString(event.context ?? event.event.content)
                    
                    if let range = attributedString.range(of: event.event.content) {
                        attributedString[range].backgroundColor = DamusColors.highlight
                    }
                    
                    return attributedString
                }
                
                Text(attributedString)
                    .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
                    .lineSpacing(5)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 25).fill(DamusColors.highlight).frame(width: 4),
                alignment: .leading
            )
            .padding(.bottom, 10)
            
            if let url = event.url_ref {
                HighlightLink(state: state, url: url, content: event.event.content)
            } else {
                if let evRef = event.event_ref {
                    if let eventHex = hex_decode_id(evRef) {
                        HighlightEventRef(damus_state: state, event_ref: NoteId(eventHex))
                            .padding(.top, 5)
                    }
                }
            }

        }
    }
}

struct HighlightView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions
    
    init(state: DamusState, event: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: event)
        self.options = options.union(.no_mentions)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            EventShell(state: state, event: event.event, options: options) {
                HighlightBodyView(state: state, ev: event, options: options)
            }
        }
    }
}

struct HighlightView_Previews: PreviewProvider {
    static var previews: some View {
        
        let content = "Nostr, a decentralized and open social network protocol. Without ads, toxic algorithms, or censorship"
        let context = "Damus is built on Nostr, a decentralized and open social network protocol. Without ads, toxic algorithms, or censorship, Damus gives you access to the social network that a truly free and healthy society needs — and deserves."

        let test_highlight_event = HighlightEvent.parse(from: NostrEvent(
            content: content,
            keypair: test_keypair,
            kind: NostrKind.highlight.rawValue,
            tags: [
                ["context", context],
                ["r", "https://damus.io"],
                ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
            ])!
        )
        
        let test_highlight_event2 = HighlightEvent.parse(from: NostrEvent(
            content: content,
            keypair: test_keypair,
            kind: NostrKind.highlight.rawValue,
            tags: [
                ["context", context],
                ["e", "36017b098859d62e1dbd802290d59c9de9f18bb0ca00ba4b875c2930dd5891ae"],
                ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
            ])!
        )
        VStack {
            HighlightView(state: test_damus_state, event: test_highlight_event.event, options: [])
            
            HighlightView(state: test_damus_state, event: test_highlight_event2.event, options: [.wide])
        }
    }
}
