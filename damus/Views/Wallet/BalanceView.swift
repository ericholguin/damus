//
//  BalanceView.swift
//  damus
//
//  Created by eric on 1/23/25.
//

import SwiftUI

struct BalanceView: View {
    var balance: Int64?
    
    var body: some View {
        VStack(spacing: 5) {
            Text("Current balance", comment: "Label for displaying current wallet balance")
                .foregroundStyle(DamusColors.neutral6)
            if let balance {
                HStack {
                    Text("\(balance)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .font(.system(size: 70))
                        .fontWeight(.heavy)
                        .foregroundStyle(PinkGradient)
                    
                    HStack(alignment: .top) {
                        Text("SATS", comment: "Abbreviation for Satoshis, smallest bitcoin unit")
                            .font(.system(size: 12))
                            .fontWeight(.heavy)
                            .foregroundStyle(PinkGradient)
                    }
                }
                .padding(.bottom)
            }
            else {
                // Make sure we do not show any numeric value to the user when still loading (or when failed to load)
                // This is important because if we show a numeric value like "zero" when things are not loaded properly, we risk scaring the user into thinking that they have lost funds.
                HStack {
                    Text("??")
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .font(.system(size: 70))
                        .fontWeight(.heavy)
                        .foregroundStyle(PinkGradient)
                    
                    HStack(alignment: .top) {
                        Text("SATS", comment: "Abbreviation for Satoshis, smallest bitcoin unit")
                            .font(.system(size: 12))
                            .fontWeight(.heavy)
                            .foregroundStyle(PinkGradient)
                    }
                }
                .redacted(reason: .placeholder)
                .shimmer(true)
                .padding(.bottom)
            }
        }
    }
}

struct BalanceView_Previews: PreviewProvider {
    static var previews: some View {
        BalanceView(balance: 100000000)
    }
}

