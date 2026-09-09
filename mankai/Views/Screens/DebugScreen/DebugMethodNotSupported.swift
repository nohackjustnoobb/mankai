//
//  DebugMethodNotSupported.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugMethodNotSupported: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("methodNotSupported")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text("methodNotSupportedDescription")
        }
    }
}
