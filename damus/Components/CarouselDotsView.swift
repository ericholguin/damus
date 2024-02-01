//
//  CarouselDotsView.swift
//  damus
//
//  Created by Terry Yiu on 7/15/23.
//

import SwiftUI

struct CarouselDotsView: View {
    let pages: Int
    let maxVisibleCount: Int
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 4
    @State private var pageOffset: CGFloat = 0
    @State private var centerOffset: Int = 0
    @Binding var selectedIndex: Int

    var body: some View {
        if pages > 1 {
            GeometryReader { geometry in
                let horizontalOffset = calculateHorizontalOffset(in: geometry)
                let centerPage = 1 + pageOffset
                
                ForEach(0..<pages, id: \.self) { page in
                    DotView(
                        dotSize: dotSize,
                        isSelected: page == selectedIndex,
                        center: calculateDotCenter(for: page, with: horizontalOffset, in: geometry),
                        scale: calculateDotScale(for: page, centerPage: centerPage)
                    )
                }
            }
            .onChange(of: selectedIndex) { newValue in
                updateOffsets(for: newValue)
            }
            .frame(width: intrinsicContentSize.width, height: intrinsicContentSize.height)
        }
    }

    private func calculateHorizontalOffset(in geometry: GeometryProxy) -> CGFloat {
        return CGFloat(-pageOffset + 2) * (dotSize + spacing) + (geometry.size.width - intrinsicContentSize.width) / 2
    }

    private func calculateDotCenter(for page: Int, with horizontalOffset: CGFloat, in geometry: GeometryProxy) -> CGPoint {
        let x = horizontalOffset + geometry.frame(in: .local).minX + dotSize / 2 + (dotSize + spacing) * CGFloat(page)
        let y = geometry.frame(in: .local).midY
        return CGPoint(x: x, y: y)
    }

    private func calculateDotScale(for page: Int, centerPage: CGFloat) -> CGFloat {
        let distance = abs(page - Int(centerPage))
        switch distance {
        case 0, 1:
            return 1
        case 2:
            return 0.66
        case 3:
            return 0.33
        default:
            return 0
        }
    }

    private func updateOffsets(for newValue: Int) {
        if (0...2).contains(newValue - Int(pageOffset)) {
            centerOffset = newValue - Int(pageOffset)
        } else {
            pageOffset = CGFloat(newValue - centerOffset)
        }
    }

    var intrinsicContentSize: CGSize {
        let pages = min(maxVisibleCount, self.pages)
        let width = CGFloat(pages) * dotSize + CGFloat(pages - 1) * spacing
        let height = dotSize
        return CGSize(width: width, height: height)
    }
}

struct DotView: View {
    var dotSize: CGFloat
    var isSelected: Bool
    var center: CGPoint
    var scale: CGFloat

    var body: some View {
        Circle()
            .fill(isSelected ? Color("DamusPurple") : Color("DamusLightGrey"))
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(scale)
            .position(center)
    }
}
