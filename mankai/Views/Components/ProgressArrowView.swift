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
        switch self { case .up: return "arrow.up" case .down: return "arrow.down" case .left:
            return "arrow.left"
            case .right: return "arrow.right"
        }
    }

    fileprivate var progressStartAngle: Angle {
        switch self { case .up: return .degrees(-90) case .down: return .degrees(90) case .left:
            return .degrees(180)
            case .right: return .zero
        }
    }
}

struct ProgressArrowView: View {
    let progress: Double
    var direction: ProgressArrowDirection = .down
    var strokeColor: Color = Color(uiColor: .secondaryLabel)
    var completedColor: Color = .accentColor
    var uncompletedStrokeColor: Color = Color(uiColor: .quaternaryLabel)
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3
    var completionScale: CGFloat = 1.2

    private var normalizedProgress: Double { min(max(progress, 0), 1) }

    private var isInProgress: Bool { normalizedProgress > 0 && normalizedProgress < 1 }

    private var isComplete: Bool { normalizedProgress >= 1 }

    private var strokeProgress: Double { normalizedProgress / 2 }

    private var progressStrokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    }

    private var hapticProgressStep: Int { Int(normalizedProgress * 10) }

    var body: some View {
        ZStack {
            Circle().fill(completedColor).opacity(isComplete ? 1 : 0)

            Circle().stroke(uncompletedStrokeColor, style: progressStrokeStyle)
                .opacity(isInProgress ? 1 : 0)

            Circle().trim(from: 0.5 - strokeProgress, to: 0.5 + strokeProgress)
                .stroke(strokeColor, style: progressStrokeStyle)
                .rotationEffect(direction.progressStartAngle).opacity(isInProgress ? 1 : 0)

            Image(systemName: direction.systemImageName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(isComplete ? .white : strokeColor)
        }
        .frame(width: size, height: size).scaleEffect(isComplete ? completionScale : 1)
        .animation(.bouncy(duration: 0.5, extraBounce: 0.3), value: isComplete)
        .sensoryFeedback(.increase, trigger: hapticProgressStep) { oldStep, newStep in
            newStep > oldStep
        }
        .sensoryFeedback(.success, trigger: isComplete) { oldValue, newValue in
            !oldValue && newValue
        }
    }
}
