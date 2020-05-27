//
//  TouchableImageView.swift
//  ReaderApp
//
//  Created by povidalo on 27/05/2020.
//  Copyright © 2020 Samax. All rights reserved.
//

import UIKit


class TouchableImageView : UIImageView {
    public var onTounchCallback: ((CGPoint) -> Void)?
    public var onTounchCancelCallback: (() -> Void)?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTounchCallback?(point)
        }
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTounchCallback?(point)
        }
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTounchCancelCallback?()
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTounchCancelCallback?()
        super.touchesEnded(touches, with: event)
    }
}
