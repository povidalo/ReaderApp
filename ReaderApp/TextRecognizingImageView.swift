//
//  TextRecognizingImageView.swift
//  ReaderApp
//
//  Created by povidalo on 29/05/2020.
//  Copyright © 2020 BOVA llc. All rights reserved.
//

import UIKit
import Vision
import VisionKit

class TextRecognizingImageView : UIImageView {
    public var selectionStateChanged: ((Bool)->Void)?
    public var processingStateChanged: ((Bool)->Void)?
    public var onError: ((String)->Void)?
    
    private var textRecognitionRequest = VNRecognizeTextRequest()
    
    private var latestTouch: CGPoint?
    private var latestSelectionState: Bool?
    
    private var scaledImageWidth: CGFloat = 0.0
    private var scaledImageHeight: CGFloat = 0.0
    private var latestObservations: [VNRecognizedTextObservation]?
    private var latestObservationsStates: [ObservationState]?
    
    override var image: UIImage? {
        get {
            return super.image
        }
        set {
            if let uiImage = newValue?.fixOrientation() {
                guard let cgImage = uiImage.cgImage else {
                    onError?("Couldn't update image!")
                    return
                }
                
                latestObservations = nil
                latestObservationsStates = nil
                createObservationViews()
                updateImageView(with: uiImage)
                recognizeText(from: cgImage)
            } else {
                super.image = newValue
            }
        }
    }
    
    private struct ObservationState {
        var selected = false
        let view: UIView!
    }
    
    private lazy var annotationOverlayView: UIView = {
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()
    
    public func initialize() {
        addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
          annotationOverlayView.topAnchor.constraint(equalTo: topAnchor),
          annotationOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
          annotationOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
          annotationOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        textRecognitionRequest = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let strongSelf = self else { return }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                strongSelf.latestObservations = nil
                strongSelf.onError?("The observations are of an unexpected type.")
                return
            }

            var validObservations = [VNRecognizedTextObservation]()
            for observation in observations {
                if observation.topCandidates(1).first == nil {
                    continue
                }
                validObservations.append(observation)
            }

            strongSelf.latestObservations = validObservations
        }
        textRecognitionRequest.recognitionLevel = .accurate
    }
    
    public func getText() -> String {
        guard let observations = latestObservations else { return "" }
        guard let observationsStates = latestObservationsStates else { return "" }
        
        var leftBorder: CGFloat? = nil
        var rightBorder: CGFloat? = nil
        var minSymbWidth: CGFloat? = nil
        for (index, observation) in observations.enumerated() {
            let state = observationsStates[index]
            if !state.selected { continue }
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            let box = observation.boundingBox
            let symbWidth = box.width / CGFloat(candidate.string.count)
            
            if leftBorder == nil || leftBorder! > box.minX {
                leftBorder = box.minX
            }
            if rightBorder == nil || rightBorder! < box.maxX {
                rightBorder = box.maxX
            }
            if minSymbWidth == nil || minSymbWidth! > symbWidth {
                minSymbWidth = symbWidth
            }
        }
        
        var text = ""
        var lastLineHadWordWrap = false
        for (index, observation) in observations.enumerated() {
            let state = observationsStates[index]
            if !state.selected { continue }
            let box = observation.boundingBox
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            let ogigLine = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = ogigLine
            
            var hasWordWrap = false
            if observationAtRight(index) == nil {
                if line[(line.count-1)...(line.count-1)] == "-" {
                    hasWordWrap = true
                    line = line[0...(line.count-2)]
                }
                if box.maxX < rightBorder! - minSymbWidth! * 3 {
                    line += "\n\n"
                }
            }
            if text != "" {
                if observationAtLeft(index) == nil {
                    if text[(text.count-1)...(text.count-1)] != "\n" {
                        if box.minX > leftBorder! + minSymbWidth! * 3 {
                            text += "\n\n"
                        } else if !lastLineHadWordWrap {
                            text += " "
                        }
                    }
                } else {
                    text += " "
                }
            }
            
            lastLineHadWordWrap = hasWordWrap
            text += line
        }
        
        return text
    }
    
    public func hasAnySelected() -> Bool {
        guard let observationsStates = latestObservationsStates else { return false }
        
        for state in observationsStates {
            if state.selected {
                return true
            }
        }
        return false
    }
    
    private func updateImageView(with image: UIImage) {
        let imageViewRatio = bounds.size.width / bounds.size.height
        let imageRatio = image.size.width / image.size.height
        
        if (imageRatio < imageViewRatio) {
            scaledImageHeight = bounds.size.height
            scaledImageWidth = image.size.width * scaledImageHeight / image.size.height
        } else {
            scaledImageWidth = bounds.size.width
            scaledImageHeight = image.size.height * scaledImageWidth / image.size.width
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var scaledImage = image.scaledImage(with: CGSize(width: self.scaledImageWidth, height: self.scaledImageHeight))
            scaledImage = scaledImage ?? image
            guard let finalImage = scaledImage else { return }
            DispatchQueue.main.async {
                super.image = finalImage
            }
        }
    }
    
    private func recognizeText(from image: CGImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try requestHandler.perform([self.textRecognitionRequest])
            } catch {
                DispatchQueue.main.async {
                    self.onError?(error.localizedDescription)
                }
            }
            
            DispatchQueue.main.async {
                self.createObservationViews()
                self.updateObservations()
            }
        }
    }
    
    private func createObservationViews() {
        for view in annotationOverlayView.subviews {
            view.removeFromSuperview()
        }
        
        guard let observations = latestObservations else { return }
        
        var states = [ObservationState]()
        for observation in observations {
            if observation.topCandidates(1).first == nil {
                continue
            }
            
            let rectangleView = UIView(frame: getObservationOnImageViewPos(observation))
            rectangleView.layer.cornerRadius = 3
            states.append(ObservationState(view: rectangleView))
            annotationOverlayView.addSubview(rectangleView)
        }
        latestObservationsStates = states
        processingStateChanged?(false)
    }
    
    private func updateObservations() {
        guard let observationsStates = latestObservationsStates else {
            selectionStateChanged?(false)
            return
        }
        
        var anySelected = false
        for state in observationsStates {
            if state.selected {
                anySelected = true
                state.view.alpha = 0.3
                state.view.backgroundColor = UIColor.blue
                state.view.layer.borderWidth = 0
                state.view.layer.borderColor = UIColor.clear.cgColor
            } else {
                state.view.alpha = 0.8
                state.view.backgroundColor = UIColor.clear
                state.view.layer.borderWidth = 1
                state.view.layer.borderColor = UIColor.blue.cgColor
            }
        }
        
        selectionStateChanged?(anySelected)
    }
    
    private func observationAtRight(_ index: Int) -> VNRecognizedTextObservation? {
        guard let observations = latestObservations else { return nil }
        guard let observationsStates = latestObservationsStates else { return nil }
        
        if index >= observations.count-1 { return nil }
        
        let observedBox = observations[index].boundingBox
        
        for i in index+1..<observations.count {
            let observation = observations[i]
            let state = observationsStates[i]
            if !state.selected { continue }
            let box = observation.boundingBox
            if observation.topCandidates(1).first == nil { continue }
            
            if box.minX >= observedBox.maxX && ((observedBox.minY > box.minY && observedBox.minY < box.maxY) || (observedBox.maxY > box.minY && observedBox.maxY < box.maxY) || (box.minY < observedBox.maxY && box.minY > observedBox.minY)) {
                return observation
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    private func observationAtLeft(_ index: Int) -> VNRecognizedTextObservation? {
        if index <= 0 { return nil }
        
        guard let observations = latestObservations else { return nil }
        guard let observationsStates = latestObservationsStates else { return nil }
        
        let observedBox = observations[index].boundingBox
        
        for i in (0...(index-1)).reversed() {
            let observation = observations[i]
            let state = observationsStates[i]
            if !state.selected { continue }
            let box = observation.boundingBox
            if observation.topCandidates(1).first == nil { continue }
            
            if box.maxX <= observedBox.minX && ((observedBox.minY > box.minY && observedBox.minY < box.maxY) || (observedBox.maxY > box.minY && observedBox.maxY < box.maxY) || (box.minY < observedBox.maxY && box.minY > observedBox.minY)) {
                return observation
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    private func getObservationOnImageViewPos(_ observation: VNRecognizedTextObservation) -> CGRect {
        let paddingX = (CGFloat(bounds.size.width) - CGFloat(scaledImageWidth)) / 2.0
        let paddingY = (CGFloat(bounds.size.height) - CGFloat(scaledImageHeight)) / 2.0
        
        let box = observation.boundingBox
        
        return CGRect(x: box.minX * scaledImageWidth + paddingX, y: (1 - box.maxY) * scaledImageHeight + paddingY, width: box.width * scaledImageWidth, height: box.height * scaledImageHeight)
    }
    
    private func getObservationsAtPoint(_ point: CGPoint?) -> [Int] {
        var res = [Int]()
        
        guard let observations = latestObservations else { return res }
        
        if point != nil {
            for (index, observation) in observations.enumerated() {
                let box = getObservationOnImageViewPos(observation)
                if box.contains(point!) {
                    res.append(index)
                }
            }
        }
        return res
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTouch(point)
        }
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTouch(point)
        }
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onCancelTouch()
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onCancelTouch()
        super.touchesEnded(touches, with: event)
    }
    
    private func onTouch(_ point: CGPoint) {
        guard var observationsStates = latestObservationsStates else { return }
        
        let lastObservations = getObservationsAtPoint(latestTouch)
        let newObservations = getObservationsAtPoint(point)
        
        if lastObservations != newObservations && newObservations.count > 0 {
            let selectionState = latestSelectionState ?? !observationsStates[newObservations[0]].selected
            var updatedObservations = false
            for index in newObservations {
                if selectionState != observationsStates[index].selected {
                    observationsStates[index].selected = selectionState
                    updatedObservations = true
                }
            }
            if updatedObservations {
                latestObservationsStates = observationsStates
                updateObservations()
            }
            latestSelectionState = selectionState
        }
        
        latestTouch = point
    }
    
    private func onCancelTouch() {
        latestTouch = nil
        latestSelectionState = nil
    }
}
