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


extension UIViewController {

    func showToast(message: String, bottomMargin: CGFloat = 0) {
        let frameWidth = self.view.frame.size.width
        let toastLabel = UILabel(frame: CGRect(x: frameWidth*0.15, y: self.view.frame.size.height-100-bottomMargin, width: frameWidth*0.60, height: 35))
        toastLabel.backgroundColor = UIColor.darkGray.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.font = UIFont.systemFont(ofSize: 14.0)
        toastLabel.textAlignment = .center;
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 4.0, delay: 0.1, options: .curveEaseOut, animations: {
             toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
    
}
