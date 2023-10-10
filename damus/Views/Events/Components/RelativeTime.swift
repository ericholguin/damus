//
//  RelativeTime.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct RelativeTime: View {
    @ObservedObject var time: RelativeTimeModel
    let state: DamusState
    
    var body: some View {
        Text(verbatim: "\(time.value)")
            .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
            .foregroundColor(.gray)
    }
}


struct RelativeTime_Previews: PreviewProvider {
    static var previews: some View {
        RelativeTime(time: RelativeTimeModel(), state: test_damus_state)
    }
}
