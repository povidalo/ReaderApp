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

class ViewController: UIViewController, VNDocumentCameraViewControllerDelegate {

    var textRecognitionRequest = VNRecognizeTextRequest()
    @IBOutlet fileprivate weak var imageView: TouchableImageView!
    
    private let textRecognitionWorkQueue = DispatchQueue(label: "TextRecognitionQueue",
    qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private lazy var annotationOverlayView: UIView = {
        precondition(isViewLoaded)
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()
    
    private var scaledImageWidth: CGFloat = 0.0
    private var scaledImageHeight: CGFloat = 0.0
    private var latestObservations: [VNRecognizedTextObservation:Bool]?
    private var latestObservationViews: [VNRecognizedTextObservation:UIView]?
    
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
    }
    
    @IBAction func showCamera(_ sender: Any) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoPicker(sourceType: .photoLibrary)
            return
        }
        let photoSourcePicker = UIAlertController()
        let takePhoto = UIAlertAction(title: "Camera", style: .default) { [unowned self] _ in
            self.navigationController?.pushViewController(self.documentCameraViewController, animated: true)
        }
        let choosePhoto = UIAlertAction(title: "Photos Library", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .photoLibrary)
        }
        photoSourcePicker.addAction(takePhoto)
        photoSourcePicker.addAction(choosePhoto)
        photoSourcePicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(photoSourcePicker, animated: true)
    }
    
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        if scan.pageCount > 0 {
            processImage(image: scan.imageOfPage(at: 0))
            controller.navigationController?.popViewController(animated: true)
            if scan.pageCount > 1 {
                showError(message: "Selected more than 1 image. Only first one will be processed.")
            }
        } else {
            showError(message: "No images selected")
        }
    }
    
    func recognizeText(from image: CGImage) {
        let textRecognitionRequest = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let strongSelf = self else { return }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                strongSelf.latestObservations = nil
                strongSelf.showError(message: "The observations are of an unexpected type.")
                return
            }
            
            var latestObservations = [VNRecognizedTextObservation:Bool]()
            for observation in observations {
                latestObservations[observation] = false
            }
            strongSelf.latestObservations = latestObservations
        }
        textRecognitionRequest.recognitionLevel = .accurate
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try requestHandler.perform([textRecognitionRequest])
        } catch {
            showError(message: error.localizedDescription)
        }
        
        createObservationViews()
        updateObservations()
    }
    
    private func createObservationViews() {
        guard let observations = latestObservations else { return }
        
        for view in annotationOverlayView.subviews {
            view.removeFromSuperview()
        }
        var views = [VNRecognizedTextObservation:UIView]()
        for (observation, _) in observations {
            if observation.topCandidates(1).first == nil {
                continue
            }
            
            let rectangleView = UIView(frame: getObservationOnImageViewPos(observation))
            rectangleView.layer.cornerRadius = 3
            views[observation] = rectangleView
            annotationOverlayView.addSubview(rectangleView)
        }
        latestObservationViews = views
    }
    
    private func updateObservations() {
        guard let observations = latestObservations else { return }
        guard let observationViews = latestObservationViews else { return }
        
        for (observation, selected) in observations {
            guard let rectangleView = observationViews[observation] else { continue }
            if selected {
                rectangleView.alpha = 0.3
                rectangleView.backgroundColor = UIColor.red
                rectangleView.layer.borderWidth = 0
                rectangleView.layer.borderColor = UIColor.clear.cgColor
            } else {
                rectangleView.alpha = 1
                rectangleView.backgroundColor = UIColor.clear
                rectangleView.layer.borderWidth = 1
                rectangleView.layer.borderColor = UIColor.red.cgColor
            }
        }
    }
    
    private func getObservationOnImageViewPos(_ observation: VNRecognizedTextObservation) -> CGRect {
        let paddingX = (CGFloat(imageView.bounds.size.width) - CGFloat(scaledImageWidth)) / 2.0
        let paddingY = (CGFloat(imageView.bounds.size.height) - CGFloat(scaledImageHeight)) / 2.0
        
        let box = observation.boundingBox
        
        return CGRect(x: box.minX * scaledImageWidth + paddingX, y: (1 - box.maxY) * scaledImageHeight + paddingY, width: box.width * scaledImageWidth, height: box.height * scaledImageHeight)
    }
    
    private func getObservationAtPoint(_ point: CGPoint?) -> VNRecognizedTextObservation? {
        guard let observations = latestObservations else { return nil }
        
        if point != nil {
            for (observation, _) in observations {
                let box = getObservationOnImageViewPos(observation)
                if box.contains(point!) {
                    return observation
                }
            }
        }
        return nil
    }
    
    private func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
    
    private func updateImageView(with image: UIImage) {
        let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .unknown
        switch orientation {
            case .landscapeLeft, .landscapeRight:
                scaledImageHeight = imageView.bounds.size.height
                scaledImageWidth = image.size.width * scaledImageHeight / image.size.height
            default:
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
        guard let uiImage = image else {
            showError(message: "Couldn't load image!")
            return
        }
        
        guard let cgImage = uiImage.cgImage else {
            showError(message: "Couldn't retreive image!")
            return
        }
        
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
        guard var observations = latestObservations else { return }
        
        let lastObservation = getObservationAtPoint(latestTouch)
        let newObservation = getObservationAtPoint(point)
        
        if lastObservation != newObservation && newObservation != nil {
            let selectionState = latestSelectionState ?? !(observations[newObservation!] ?? false)
            if selectionState != observations[newObservation!] {
                observations[newObservation!] = selectionState
                latestObservations = observations
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

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        
        processImage(image: info[UIImagePickerController.InfoKey.originalImage] as? UIImage)
    }
}

