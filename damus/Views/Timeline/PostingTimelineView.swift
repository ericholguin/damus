//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 3/21/24.
//

import SwiftUI

struct PostingTimelineView: View {
    let damus_state: DamusState
    var home: HomeModel
    @State var search: String = ""
    @State var results: [NostrEvent] = []
    @State var initialOffset: CGFloat?
    @State var offset: CGFloat?
    @State var showSearch: Bool = true
    @Binding var active_sheet: Sheets?
    @FocusState private var isSearchFocused: Bool
    @State private var currentTab: Tab = tabs_[1]
    @State private var tabs: [Tab] = tabs_
    @State private var contentOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0
    @SceneStorage("PostingTimelineView.filter_state") var filter_state : FilterState = .posts_and_replies
    
    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        VStack(spacing: 0) {
            if self.showSearch {
                PullDownSearchView(state: damus_state, search_text: $search, results: $results)
                    .focused($isSearchFocused)
            }
            if !isSearchFocused && search.isEmpty {
                TimelineView(events: home.events, loading: .constant(false), damus: damus_state, show_friend_icon: false, filter: filter) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: OffsetKey.self, value: geometry.frame(in: .global).minY)
                            .frame(height: 0)
                    }
                }
            } else {
                SearchContentView(state: damus_state, search_text: $search, results: $results)
                    .padding(.top)
                    .scrollDismissesKeyboard(.immediately)
            }
        }
        .onPreferenceChange(OffsetKey.self) {
            if self.initialOffset == nil || self.initialOffset == 0 {
                self.initialOffset = $0
            }
            
            self.offset = $0
            
            guard let initialOffset = self.initialOffset,
                  let offset = self.offset else {
                return
            }
            
            if(initialOffset > offset){
                self.showSearch = false
            } else {
                self.showSearch = true
            }
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                TabView(selection: $currentTab) {
                    ForEach(tabs) { tab in
                        GeometryReader { _ in
                            contentTimelineView(filter: content_filter(tab.filter))
                        }
                        .offsetX { rect in
                            if currentTab.title == tab.title {
                                contentOffset = rect.minX - (rect.width * CGFloat(index(of: tab)))
                            }
                            updateTabFrame(rect.width)
                            
                        }
                        .tag(tab)
                    }

                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .safeAreaInset(edge: .top, spacing: 10) {
                    if !isSearchFocused && search.isEmpty {
                        TabsView()
                    }
                }
                
                if damus_state.keypair.privkey != nil && (!isSearchFocused && search.isEmpty) {
                    PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                        active_sheet = .post(.posting(.none))
                    }
                }
            }
        }
    }
    
    func updateTabFrame(_ tabViewWidth: CGFloat) {
        let inputRange = tabs.indices.compactMap { index -> CGFloat? in
            return CGFloat(index) * tabViewWidth
        }
        
        let outputRangeForWidth = tabs.compactMap { tab -> CGFloat? in
            return tab.width
        }
        
        let outputRangeForPosition = tabs.compactMap { tab -> CGFloat? in
            return tab.minX
        }
        
        let widthInterpolation = LinearInterpolation(inputRange: inputRange, outputRange: outputRangeForWidth)
        let positionInterpolation = LinearInterpolation(inputRange: inputRange, outputRange: outputRangeForPosition)
        
        indicatorWidth = widthInterpolation.calculate(for: -contentOffset)
        indicatorPosition = positionInterpolation.calculate(for: -contentOffset)
    }
    
    func index(of tab: Tab) -> Int {
        return tabs.firstIndex(of: tab) ?? 0
    }
    
    @ViewBuilder
    func TabsView() -> some View {
        HStack(spacing: 0) {
            ForEach($tabs) { $tab in
                Spacer()
                Text(tab.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(tab == currentTab ? DamusColors.adaptableBlack : .gray)
                    .offsetX { rect in
                        tab.minX = rect.minX
                        tab.width = rect.width
                    }
                
//                if tabs.last != tab {
//                    Spacer(minLength: 0)
//                }
                
                Spacer()
            }
        }
        .padding(.top, 15)
        .overlay(alignment: .bottomLeading, content: {
            Rectangle().fill(RECTANGLE_GRADIENT)
                .cornerRadius(2.5)
                .frame(width: indicatorWidth, height: 3)
                .offset(x: indicatorPosition, y: 10)
        })
        .overlay(alignment: .bottom, content: {
            Divider()
                .frame(height: 1)
                .offset(y: 10)
        })
    }
}

struct OffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?,
                       nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

struct PostingTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let home: HomeModel = HomeModel()
        PostingTimelineView(damus_state: test_damus_state, home: home, active_sheet: .constant(.none))
    }
}
