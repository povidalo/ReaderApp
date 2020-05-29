//
//  ViewController.swift
//  ReaderApp
//
//  Created by Kirill on 18.05.2020.
//  Copyright © 2020 Samax. All rights reserved.
//

import UIKit
import Vision
import VisionKit

class ImageSceneViewController: UIViewController, VNDocumentCameraViewControllerDelegate {

    var textRecognitionRequest = VNRecognizeTextRequest()
    @IBOutlet fileprivate weak var imageView: TouchableImageView!
    @IBOutlet fileprivate weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet fileprivate weak var bigImgSelectBtn: UIButton!
    @IBOutlet fileprivate weak var doneBtn: UIButton!
    
    private lazy var annotationOverlayView: UIView = {
        precondition(isViewLoaded)
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()
    
    private var scaledImageWidth: CGFloat = 0.0
    private var scaledImageHeight: CGFloat = 0.0
    private var latestObservations: [VNRecognizedTextObservation]?
    private var latestObservationsStates: [ObservationState]?
    
    struct ObservationState {
        var selected = false
        let view: UIView!
    }
    
    let documentCameraViewController = VNDocumentCameraViewController()
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        
        documentCameraViewController.delegate = self
        
        imageView.addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
          annotationOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
          annotationOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
          annotationOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
          annotationOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
        ])
        imageView.onTounchCallback = onImageViewTouch
        imageView.onTounchCancelCallback = onImageViewCancelTouch
        
        textRecognitionRequest = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let strongSelf = self else { return }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                strongSelf.latestObservations = nil
                strongSelf.showError(message: "The observations are of an unexpected type.")
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
    
    @IBAction func showCamera(_ sender: Any) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoPicker(sourceType: .photoLibrary)
            return
        }
        
        let takePhoto = UIAlertAction(title: "Camera", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .camera)
        }
        
        let scanDocument = UIAlertAction(title: "Document scanner", style: .default) { [unowned self] _ in
            self.navigationController?.pushViewController(self.documentCameraViewController, animated: true)
        }
        
        let choosePhoto = UIAlertAction(title: "Photo Library", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .photoLibrary)
        }
        
        let photoSourcePicker = UIAlertController(title: "Choose a photo of a text",
                                                  message: "or scan it with document scanner",
                                                  preferredStyle: .actionSheet)
        photoSourcePicker.addAction(takePhoto)
        photoSourcePicker.addAction(scanDocument)
        photoSourcePicker.addAction(choosePhoto)
        photoSourcePicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(photoSourcePicker, animated: true)
    }
    
    @IBAction func done(_ sender: Any) {
        guard let observations = latestObservations else { return }
        guard let observationsStates = latestObservationsStates else { return }
        
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
        var anySelected = false
        var lastLineHadWordWrap = false
        for (index, observation) in observations.enumerated() {
            let state = observationsStates[index]
            if !state.selected { continue }
            anySelected = true
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
        
        if anySelected {
            performSegue(withIdentifier: "showResult", sender: text)
        }
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showResult", let text = sender as? String, let resultViewController = segue.destination as? ResultSceneViewController {
            resultViewController.text = text
        }
    }
    
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        if scan.pageCount > 0 {
            processImage(image: scan.imageOfPage(at: scan.pageCount-1))
            controller.navigationController?.popViewController(animated: true)
            if scan.pageCount > 1 {
                showError(message: "Selected more than 1 image. Only the last one will be processed.")
            }
        } else {
            showError(message: "No images selected")
        }
    }
    
    func recognizeText(from image: CGImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try requestHandler.perform([self.textRecognitionRequest])
            } catch {
                DispatchQueue.main.async {
                    self.showError(message: error.localizedDescription)
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
        activityIndicator.isHidden = true
    }
    
    private func updateObservations() {
        guard let observationsStates = latestObservationsStates else {
            doneBtn.isHidden = true
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
        doneBtn.isHidden = !anySelected
    }
    
    private func getObservationOnImageViewPos(_ observation: VNRecognizedTextObservation) -> CGRect {
        let paddingX = (CGFloat(imageView.bounds.size.width) - CGFloat(scaledImageWidth)) / 2.0
        let paddingY = (CGFloat(imageView.bounds.size.height) - CGFloat(scaledImageHeight)) / 2.0
        
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
    
    private func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
    
    private func updateImageView(with image: UIImage) {
        let imageViewRatio = imageView.bounds.size.width / imageView.bounds.size.height
        let imageRatio = image.size.width / image.size.height
        
        if (imageRatio < imageViewRatio) {
            scaledImageHeight = imageView.bounds.size.height
            scaledImageWidth = image.size.width * scaledImageHeight / image.size.height
        } else {
            scaledImageWidth = imageView.bounds.size.width
            scaledImageHeight = image.size.height * scaledImageWidth / image.size.width
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var scaledImage = image.scaledImage(with: CGSize(width: self.scaledImageWidth, height: self.scaledImageHeight))
            scaledImage = scaledImage ?? image
            guard let finalImage = scaledImage else { return }
            DispatchQueue.main.async {
                self.imageView.image = finalImage
            }
        }
    }
    
    private func processImage(image: UIImage?) {
        guard var uiImage = image else {
            showError(message: "Couldn't load image!")
            return
        }
        
        uiImage = uiImage.fixOrientation()
        
        guard let cgImage = uiImage.cgImage else {
            showError(message: "Couldn't retreive image!")
            return
        }
        
        imageView.isHidden = false
        bigImgSelectBtn.isHidden = true
        activityIndicator.isHidden = false
        latestObservations = nil
        latestObservationsStates = nil
        createObservationViews()
        updateImageView(with: uiImage)
        recognizeText(from: cgImage)
    }
    
    private func showError(message: String) {
        let resultsAlertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .actionSheet
        )
        resultsAlertController.addAction(
            UIAlertAction(title: "OK", style: .destructive) { _ in
                resultsAlertController.dismiss(animated: true, completion: nil)
            }
        )
        resultsAlertController.popoverPresentationController?.sourceView = self.view
        present(resultsAlertController, animated: true, completion: nil)
    }
    
    private var latestTouch: CGPoint?
    private var latestSelectionState: Bool?
    
    private func onImageViewTouch(_ point: CGPoint) {
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
    
    private func onImageViewCancelTouch() {
        latestTouch = nil
        latestSelectionState = nil
    }
}

extension ImageSceneViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        
        processImage(image: info[UIImagePickerController.InfoKey.originalImage] as? UIImage)
    }
}

