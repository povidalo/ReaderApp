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
    
    public enum SortType {
        case ORIGINAL, XY, LINEAR, XY_LINEAR
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
    
    public func getText(_ sort: SortType) -> String {
        guard let observations = latestObservations else { return "" }
        guard let observationsStates = latestObservationsStates else { return "" }
        
        var leftBorder: CGFloat? = nil
        var rightBorder: CGFloat? = nil
        var minSymbWidth: CGFloat? = nil
        var selectedIndicies = [Int]()
        for (index, observation) in observations.enumerated() {
            let state = observationsStates[index]
            if !state.selected { continue }
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            selectedIndicies.append(index)
            
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
        
        selectedIndicies = tryReorderObservations(selectedIndicies, sort)
        
        var text = ""
        var lastLineHadWordWrap = false
        for (i, index) in selectedIndicies.enumerated() {
            let observation = observations[index]
            let box = observation.boundingBox
            guard let candidate = observation.topCandidates(1).first else { continue }
            let nextCandidate = i < selectedIndicies.count-1 ? observations[selectedIndicies[i+1]].topCandidates(1).first : nil
            
            
            let ogigLine = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = ogigLine
            let nextLine = nextCandidate != nil ? nextCandidate!.string.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            
            var hasWordWrap = false
            if observationAtRight(i, selectedIndicies) == nil {
                let lastSymbol = line[(line.count-1)...(line.count-1)]
                if lastSymbol == "-" {
                    hasWordWrap = true
                    line = line[0...(line.count-2)]
                }
                
                if box.maxX < rightBorder! - minSymbWidth! * 3 && (lastSymbol == "." || lastSymbol == "?" || lastSymbol == "!" || (nextLine.count > 0 && nextLine.first!.isUppercase)) {
                    line += "\n\n"
                }
            }
            if text != "" {
                if observationAtLeft(i, selectedIndicies) == nil {
                    let lastSymbol = text[(text.count-1)...(text.count-1)]
                    if lastSymbol != "\n" {
                        if box.minX > leftBorder! + minSymbWidth! * 3 && (lastSymbol == "." || lastSymbol == "?" || lastSymbol == "!" || (line.count > 0 && line.first!.isUppercase)) {
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
    
    private func tryReorderObservations(_ indicies: [Int], _ sort: SortType) -> [Int] {
        guard let observations = latestObservations else { return indicies }
        
        switch sort {
        case .XY:
            return indicies.sorted(by: { (lhs, rhs) -> Bool in
                let lBox = observations[lhs].boundingBox
                let rBox = observations[rhs].boundingBox
                
                if (lBox.minX > rBox.minX && lBox.minX < rBox.maxX) || (lBox.maxX > rBox.minX && lBox.maxX < rBox.maxX) || (rBox.minX < lBox.maxX && rBox.minX > lBox.minX) {
                    return lBox.maxY > rBox.maxY
                } else {
                    if (lBox.minY > rBox.minY && lBox.minY < rBox.maxY) || (lBox.maxY > rBox.minY && lBox.maxY < rBox.maxY) || (rBox.minY < lBox.maxY && rBox.minY > lBox.minY) {
                        let intersectionHeight = min(lBox.maxY, rBox.maxY) - max(lBox.minY, rBox.minY)
                        let intersectionPercent = min(intersectionHeight / lBox.height, intersectionHeight / rBox.height)
                        if intersectionPercent > 0.15 {
                            return lBox.minX < rBox.minX
                        } else {
                            return lBox.maxY > rBox.maxY
                        }
                    } else {
                        return lBox.maxY > rBox.maxY
                    }
                }
            })
        case .LINEAR:
            var sorted = [Int]()
            var modifiedIndicies = indicies
            var nextIndex = 0
            while (modifiedIndicies.count > 0) {
                let newBox = observations[modifiedIndicies[nextIndex]].boundingBox
                var trueNextIndexDist = CGFloat(10.0)
                var trueNextIndex = nextIndex
                let combinedIndicies = modifiedIndicies + sorted
                for (i, index) in combinedIndicies.enumerated() {
                    if i == nextIndex { continue }
                    let prevBox = observations[index].boundingBox
                    let dist = newBox.minX - prevBox.maxX
                    let symbWidth = getSymbWidth(observations[index], observations[modifiedIndicies[nextIndex]])
                    if dist >= -symbWidth && abs(dist) < abs(trueNextIndexDist) && ((newBox.minY > prevBox.minY && newBox.minY < prevBox.maxY) || (newBox.maxY > prevBox.minY && newBox.maxY < prevBox.maxY) || (prevBox.minY < newBox.maxY && prevBox.minY > newBox.minY)) {
                        trueNextIndexDist = dist
                        trueNextIndex = i
                    }
                }
                if trueNextIndex >= modifiedIndicies.count {
                    trueNextIndex = nextIndex
                }
                
                sorted.append(modifiedIndicies[trueNextIndex])
                modifiedIndicies.remove(at: trueNextIndex)
                
                let lastBox = observations[sorted[sorted.count-1]].boundingBox
                nextIndex = 0
                var nextIndexDist = CGFloat(10.0)
                for (i, index) in modifiedIndicies.enumerated() {
                    let nextBox = observations[index].boundingBox
                    let dist = nextBox.minX - lastBox.maxX
                    let symbWidth = getSymbWidth(observations[index], observations[sorted[sorted.count-1]])
                    if dist >= -symbWidth && abs(dist) < abs(nextIndexDist) && ((lastBox.minY > nextBox.minY && lastBox.minY < nextBox.maxY) || (lastBox.maxY > nextBox.minY && lastBox.maxY < nextBox.maxY) || (nextBox.minY < lastBox.maxY && nextBox.minY > lastBox.minY)) {
                        nextIndexDist = dist
                        nextIndex = i
                    }
                }
            }
            return sorted
        case .XY_LINEAR:
            return tryReorderObservations(tryReorderObservations(indicies, .XY), .LINEAR)
        default:
            return indicies
        }
    }
    
    private func getSymbWidth(_ observations: VNRecognizedTextObservation...) -> CGFloat {
        var width = CGFloat(0)
        var foundValid = false
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if candidate.string.count <= 0 { continue }
            let w = observation.boundingBox.width / CGFloat(candidate.string.count)
            if !foundValid || width < w {
                width = w
                foundValid = true
            }
        }
        return width > 0 ? width : CGFloat(0)
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
    
    private func observationAtRight(_ indexI: Int, _ selectedIndicies: [Int]) -> VNRecognizedTextObservation? {
        guard let observations = latestObservations else { return nil }
        
        if indexI >= selectedIndicies.count-1 { return nil }
        
        let observedBox = observations[selectedIndicies[indexI]].boundingBox
        
        for i in indexI+1..<selectedIndicies.count {
            let observation = observations[selectedIndicies[i]]
            let box = observation.boundingBox
            
            if box.minX >= observedBox.maxX && ((observedBox.minY > box.minY && observedBox.minY < box.maxY) || (observedBox.maxY > box.minY && observedBox.maxY < box.maxY) || (box.minY < observedBox.maxY && box.minY > observedBox.minY)) {
                return observation
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    private func observationAtLeft(_ indexI: Int, _ selectedIndicies: [Int]) -> VNRecognizedTextObservation? {
        if indexI <= 0 { return nil }
        
        guard let observations = latestObservations else { return nil }
        
        let observedBox = observations[selectedIndicies[indexI]].boundingBox
        
        for i in (0...(indexI-1)).reversed() {
            let observation = observations[selectedIndicies[i]]
            let box = observation.boundingBox
            
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
