//
//  Tab.swift
//  damus
//
//  Created by eric on 3/24/24.
//

import SwiftUI

struct Tab: Identifiable, Hashable {
    var id: UUID = .init()
    var title: String
    var filter: FilterState
    var width: CGFloat = 0
    var minX: CGFloat = 0
}

var tabs_: [Tab] = [
    .init(title: "Notes", filter: FilterState.posts),
    .init(title: "Notes & Replies", filter: FilterState.posts_and_replies)
]
