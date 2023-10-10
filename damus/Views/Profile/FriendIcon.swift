//
//  FriendIcon.swift
//  damus
//
//  Created by William Casarin on 2023-04-20.
//

import SwiftUI

struct FriendIcon: View {
    let damus_state: DamusState
    let friend: FriendType
    
    var body: some View {
        Group {
            switch friend {
            case .friend:
                LINEAR_GRADIENT
                    .mask(Image(systemName: "person.fill.checkmark")
                        .resizable()
                    ).frame(width: 20 * damus_state.settings.font_size, height: 14 * damus_state.settings.font_size)
            case .fof:
                Image(systemName: "person.fill.and.arrow.left.and.arrow.right")
                    .resizable()
                    .frame(width: 21 * damus_state.settings.font_size, height: 14 * damus_state.settings.font_size)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct FriendIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FriendIcon(damus_state: test_damus_state, friend: .friend)
            
            FriendIcon(damus_state: test_damus_state, friend: .fof)
        }
    }
}
