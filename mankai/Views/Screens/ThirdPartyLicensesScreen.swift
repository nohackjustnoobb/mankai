//
//  ThirdPartyLicensesScreen.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import SwiftPackageListUI
import SwiftUI

struct ThirdPartyLicensesScreen: View {
    var body: some View {
        AcknowledgmentsList()
            .navigationTitle("thirdPartyLicenses")
            .navigationBarTitleDisplayMode(.inline)
    }
}
