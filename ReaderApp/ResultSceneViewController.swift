//
//  ResultSceneViewController.swift
//  ReaderApp
//
//  Created by povidalo on 28/05/2020.
//  Copyright © 2020 Samax. All rights reserved.
//

import UIKit
import Vision
import VisionKit

class ResultSceneViewController: UIViewController {
    
    @IBOutlet fileprivate weak var textView: UITextView!
    var text: String = ""
    
    override func viewDidLoad() {
        textView.text = text
        setupKeyboardNotifications()
        copyText(text)
    }
    
    @IBAction func copyText(_ sender: Any) {
        guard let text = textView.text else { return }
        
        UIPasteboard.general.string = text
        showToast(message: "Text copied to clipboard", bottomMargin: textView.contentInset.bottom)
    }
    
    @IBAction func shareText(_ sender: Any) {
        guard let text = textView.text else { return }
        
        let activityViewController = UIActivityViewController(activityItems: [ text ], applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.view

        present(activityViewController, animated: true, completion: nil)
    }
    
    func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_ :)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc func keyboardWillShow(_ notification:NSNotification) {
        let d = notification.userInfo!
        var r = (d[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
        r = textView.convert(r, from:nil)
        textView.contentInset.bottom = r.size.height
        textView.verticalScrollIndicatorInsets.bottom = r.size.height

    }

    @objc func keyboardWillHide(_ notification:NSNotification) {
        let contentInsets = UIEdgeInsets.zero
        textView.contentInset = contentInsets
        textView.verticalScrollIndicatorInsets = contentInsets
    }
    
    @IBAction func dismiss(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
}
