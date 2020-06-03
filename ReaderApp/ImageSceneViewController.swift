//
//  ViewController.swift
//  ReaderApp
//
//  Created by Kirill on 18.05.2020.
//  Copyright © 2020 BOVA llc. All rights reserved.
//

import UIKit
import VisionKit

class ImageSceneViewController: UIViewController, VNDocumentCameraViewControllerDelegate {

    private let documentCameraViewController = VNDocumentCameraViewController()
    
    @IBOutlet fileprivate weak var textRecognizingImageView: TextRecognizingImageView!
    @IBOutlet fileprivate weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet fileprivate weak var bigImgSelectBtn: UIButton!
    @IBOutlet fileprivate weak var doneBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        
        documentCameraViewController.delegate = self
        
        textRecognizingImageView.initialize()
        textRecognizingImageView.selectionStateChanged = selectionStateChanged
        textRecognizingImageView.processingStateChanged = processingStateChanged
        textRecognizingImageView.onError = showError
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
        if textRecognizingImageView.hasAnySelected() {
            let sortPicker = UIAlertController(title: "Choose sort",
                                               message: "sort will affect text blocks order",
                                               preferredStyle: .actionSheet)
            
            sortPicker.addAction(UIAlertAction(title: "Line-by-line (most recent sort version)", style: .default) { [unowned self] _ in
                self.performSegue(withIdentifier: "showResult", sender:
                    self.textRecognizingImageView.getText(TextRecognizingImageView.SortType.LINEAR))
            })
            sortPicker.addAction(UIAlertAction(title: "XY sort (as in v1.0.1(4))", style: .default) { [unowned self] _ in
                self.performSegue(withIdentifier: "showResult", sender:
                    self.textRecognizingImageView.getText(TextRecognizingImageView.SortType.XY))
            })
            sortPicker.addAction(UIAlertAction(title: "Original (Vision style)", style: .default) { [unowned self] _ in
                self.performSegue(withIdentifier: "showResult", sender:
                    self.textRecognizingImageView.getText(TextRecognizingImageView.SortType.ORIGINAL))
            })
            
            sortPicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            
            present(sortPicker, animated: true)
        }
    }
    
    private func selectionStateChanged(selected: Bool) {
        doneBtn.isHidden = !selected
    }
    
    private func processingStateChanged(processing: Bool) {
        activityIndicator.isHidden = !processing
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
    
    private func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
    
    private func processImage(image: UIImage?) {
        guard let uiImage = image else {
            showError(message: "Couldn't load image!")
            return
        }
        
        textRecognizingImageView.image = uiImage
        textRecognizingImageView.isHidden = false
        bigImgSelectBtn.isHidden = true
        activityIndicator.isHidden = false
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
}

extension ImageSceneViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        
        processImage(image: info[UIImagePickerController.InfoKey.originalImage] as? UIImage)
    }
}

