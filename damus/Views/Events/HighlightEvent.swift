//
//  HighlightEvent.swift
//  damus
//
//  Created by eric on 11/26/23.
//

import SwiftUI

struct HighlightEvent {
    let event: NostrEvent
    
    var event_ref: String? = nil
    var url_ref: URL? = nil
    var context: String? = nil
    
    static func parse(from ev: NostrEvent) -> HighlightEvent {
        var highlight = HighlightEvent(event: ev)
        
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "e":   highlight.event_ref = tag[1].string()
            case "a":   highlight.event_ref = tag[1].string()
            case "r":   highlight.url_ref = URL(string: tag[1].string())
            case "context": highlight.context = tag[1].string()
            default:
                break
            }
        }
        
        return highlight
    }
}

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

//    func Words(_ words: Int) -> Text {
//        let wordCount = pluralizedString(key: "word_count", count: words)
//        return Text(wordCount)
//    }

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
//            if let title = event.title {
//                Text(title)
//                    .font(.title)
//            } else {
//                Text("Untitled", comment: "Text indicating that the long-form note title is untitled.")
//                    .font(.title)
//            }
            
            var attributedString: AttributedString {
                var attributedString = AttributedString(event.context ?? "")

                if let range = attributedString.range(of: event.event.content) {
                    attributedString[range].backgroundColor = DamusColors.highlight
                }

                return attributedString
            }

//            Text(event.event.content)
//                .background(DamusColors.highlight)
            
            Text(attributedString)
                .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))

//            if case .loaded(let arts) = artifacts.state,
//               case .longform(let longform) = arts
//            {
//                Words(longform.words).font(.footnote)
//            }
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
        VStack {
            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [])

            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [.wide])
        }
        .frame(height: 400)
    }
}
