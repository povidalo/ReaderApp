//
//  Extensions.swift
//  ReaderApp
//
//  Created by povidalo on 27/05/2020.
//  Copyright © 2020 Samax. All rights reserved.
//

import CoreGraphics
import UIKit

extension UIImage {

    /// Creates and returns a new image scaled to the given size. The image preserves its original PNG
    /// or JPEG bitmap info.
    ///
    /// - Parameter size: The size to scale the image to.
    /// - Returns: The scaled image or `nil` if image could not be resized.
    public func scaledImage(with size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()?.data.flatMap(UIImage.init)
    }
    
    // MARK: - Private

    /// The PNG or JPEG data representation of the image or `nil` if the conversion failed.
    private var data: Data? {
        #if swift(>=4.2)
        return self.pngData() ?? self.jpegData(compressionQuality: 0.8)
        #else
        return self.pngData() ?? self.jpegData(compressionQuality: 0.8)
        #endif  // swift(>=4.2)
    }
}
