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
    @IBOutlet weak var text: UITextView!
    var recognizedText: String!
    
    private let textRecognitionWorkQueue = DispatchQueue(label: "TextRecognitionQueue",
    qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    let documentCameraViewController = VNDocumentCameraViewController()
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        self.title = "Text"
        
        documentCameraViewController.delegate = self
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
        var images = [CGImage]()
        for pageIndex in 0 ..< scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            if let cgImage = image.cgImage {
                images.append(cgImage)
            }
        }
        recognizeText(from: images)
        controller.navigationController?.popViewController(animated: true)
    }
    
    func recognizeText(from images: [CGImage]) {
        self.recognizedText = ""
        var tmp = ""
        let textRecognitionRequest = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("The observations are of an unexpected type.")
                return
            }
            // Concatenate the recognised text from all the observations.
            let maximumCandidates = 1
            for observation in observations {
                guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                tmp += candidate.string + "\n"
            }
        }
        textRecognitionRequest.recognitionLevel = .accurate
        for image in images {
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try requestHandler.perform([textRecognitionRequest])
            } catch {
                print(error)
            }
            tmp += "\n\n"
        }
        self.text.text = tmp
    }
    
    private func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        
        guard let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            fatalError("Error!")
        }
        
        recognizeText(from: [uiImage.cgImage!])
    }
}

