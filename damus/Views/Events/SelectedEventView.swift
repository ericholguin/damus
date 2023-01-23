//
//  SelectedEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct SelectedEventView: View {
    let damus: DamusState
    let event: NostrEvent
    
    var pubkey: String {
        event.pubkey
    }
    
    var body: some View {
        HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)

            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    VStack {
                        let pmodel = ProfileModel(pubkey: pubkey, damus: damus)
                        let pv = ProfileView(damus_state: damus, profile: pmodel, followers: FollowersModel(damus_state: damus, target: pubkey))
                        
                        NavigationLink(destination: pv) {
                            ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus.profiles)
                        }
                    }
                    
                    EventProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true, size: .selected)
                }
                
                EventBody(damus_state: damus, event: event, size: .selected)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                }
                
                Text("\(format_date(event.created_at))")
                    .padding(.top, 10)
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                Divider()
                    .padding([.bottom], 4)
                
                let bar = make_actionbar_model(ev: event, damus: damus)
                
                if !bar.is_empty {
                    EventDetailBar(state: damus, target: event.id, bar: bar)
                    Divider()
                }
                
                EventActionBar(damus_state: damus, event: event, bar: bar)
                    .padding([.top], 4)

                Divider()
                    .padding([.top], 4)
            }
            .padding([.leading], 2)
        }
    }
}

struct SelectedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedEventView(damus: test_damus_state(), event: test_event)
            .padding()
    }
}
