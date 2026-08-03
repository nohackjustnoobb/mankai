//
//  ThumbnailProvider.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 16/7/2026.
//

import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ completion: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        guard let coverHandler = ThumbnailHandlers.handler(forExtension: request.fileURL.pathExtension) else {
            completion(nil, nil)
            return
        }

        do {
            guard let image = try coverHandler.coverImage(from: request.fileURL) else {
                completion(nil, nil)
                return
            }
            completion(QLThumbnailReply.aspectFit(image: image, size: request.maximumSize), nil)
        } catch {
            completion(nil, error)
        }
    }
}
