//
//  HighlightEvent.swift
//  damus
//
//  Created by eric on 11/26/23.
//

import SwiftUI

struct HighlightEventBody: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: HighlightEvent, options: EventViewOptions) {
        self.state = state
        self.event = ev
        self.options = options

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: ev)
        self.options = options

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
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
        VStack(alignment: .leading, spacing: 10) {
            
            var attributedString: AttributedString {
                var attributedString = AttributedString(event.context ?? "")

                if let range = attributedString.range(of: event.event.content) {
                    attributedString[range].backgroundColor = DamusColors.highlight
                }

                return attributedString
            }
            
            Text(attributedString)
                .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
                .lineSpacing(5)
                .padding(.top, 2)
                        
            if let url = event.url_ref {
                if state.settings.media_previews {
                    LinkViewRepresentable(meta: .url(url))
                        .frame(height: 50)
                } else {
                    Text(url.absoluteString)
                }
            }
        }
    }
}

struct HighlightEventView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        EventShell(state: state, event: event.event, options: options) {
            HighlightEventBody(state: state, ev: event, options: options)
        }
    }
}

struct HighlightEvent_Previews: PreviewProvider {
    static var previews: some View {
        let test_highlight_event = HighlightEvent.parse(from: NostrEvent(
            content: "you’re gonna make me code something.",
            keypair: test_keypair,
            kind: NostrKind.highlight.rawValue,
            tags: [
                ["context", "you’re gonna make me code something. make this a really long post that shows new lines for line spacing debugging. "],
                ["e", "36017b098859d62e1dbd802290d59c9de9f18bb0ca00ba4b875c2930dd5891ae"],
                ["r", "https://google.com"],
                ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
            ])!
        )
        VStack {
            HighlightEventView(state: test_damus_state, ev: test_highlight_event.event, options: [])

            HighlightEventView(state: test_damus_state, ev: test_highlight_event.event, options: [.wide])
        }
        .frame(height: 400)
    }
}
