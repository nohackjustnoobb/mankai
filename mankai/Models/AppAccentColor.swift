//
//  AppAccentColor.swift
//  mankai
//
//  Created by Travis XU on 31/8/2026.
//

import SwiftUI

enum AppAccentColor: String, CaseIterable, Identifiable {
    case sakura
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case brown
    case gray

    var id: Self { self }

    var color: Color {
        switch self { case .sakura: Color("SakuraColor") case .red: .red case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .mint: .mint
            case .teal: .teal
            case .cyan: .cyan
            case .blue: .blue
            case .indigo: .indigo
            case .purple: .purple
            case .pink: .pink
            case .brown: .brown
            case .gray: .gray
        }
    }

    var localizedName: String {
        switch self { case .sakura: String(localized: "colorSakura") case .red:
            String(localized: "colorRed")
            case .orange: String(localized: "colorOrange")
            case .yellow: String(localized: "colorYellow")
            case .green: String(localized: "colorGreen")
            case .mint: String(localized: "colorMint")
            case .teal: String(localized: "colorTeal")
            case .cyan: String(localized: "colorCyan")
            case .blue: String(localized: "colorBlue")
            case .indigo: String(localized: "colorIndigo")
            case .purple: String(localized: "colorPurple")
            case .pink: String(localized: "colorPink")
            case .brown: String(localized: "colorBrown")
            case .gray: String(localized: "colorGray")
        }
    }
}
