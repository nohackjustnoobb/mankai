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
    case blue
    case indigo
    case purple

    var id: Self { self }

    var color: Color {
        switch self { case .sakura: Color("SakuraColor") case .red: .red case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .blue: .blue
            case .indigo: .indigo
            case .purple: .purple
        }
    }
}
