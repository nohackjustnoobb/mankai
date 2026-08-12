//
//  ProgressArrowView.swift
//  mankai
//
//  Created by Travis XU on 12/8/2026.
//

import SwiftUI

enum ProgressArrowDirection {
    case up
    case down
    case left
    case right

    fileprivate var systemImageName: String {
        switch self {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        }
    }
}

struct ProgressArrowView: View {
    let progress: Double
    var direction: ProgressArrowDirection = .down
    var tint: Color = .accentColor
    var completedColor: Color = .accentColor
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3
    var completionScale: CGFloat = 1.2

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var isInProgress: Bool {
        normalizedProgress > 0 && normalizedProgress < 1
    }

    private var isComplete: Bool {
        normalizedProgress >= 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(completedColor)
                .opacity(isComplete ? 1 : 0)

            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .opacity(isInProgress ? 1 : 0)

            Image(systemName: direction.systemImageName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(isComplete ? .white : tint)
        }
        .frame(width: size, height: size)
        .scaleEffect(isComplete ? completionScale : 1)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75),
            value: isComplete
        )
    }
}
