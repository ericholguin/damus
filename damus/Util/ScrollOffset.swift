//
//  ScrollOffset.swift
//  damus
//
//  Created by eric on 3/24/24.
//

import SwiftUI

extension View {
    @ViewBuilder
    func offsetX(completion: @escaping (CGRect) ->()) -> some View {
        self
            .overlay {
                GeometryReader { proxy in
                    let rect = proxy.frame(in: .global)
                    
                    Color.clear
                        .preference(key: XOffsetKey.self, value: rect)
                        .onPreferenceChange(XOffsetKey.self, perform: completion)
                }
            }
    }
}

struct XOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
