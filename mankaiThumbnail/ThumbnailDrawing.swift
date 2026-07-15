//
//  ThumbnailDrawing.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 16/7/2026.
//

import QuickLookThumbnailing
import UIKit

extension QLThumbnailReply {
    /// Builds a reply that draws `image` scaled to fit within `size`, preserving aspect ratio (no cropping).
    static func aspectFit(image: UIImage, size: CGSize) -> QLThumbnailReply {
        let imageSize = image.size
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let thumbnailSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return QLThumbnailReply(contextSize: thumbnailSize, currentContextDrawing: { () -> Bool in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            return true
        })
    }
}
