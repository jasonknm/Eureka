//  ImageRow.swift
//  Eureka ( https://github.com/xmartlabs/Eureka )
//
//  Copyright (c) 2016 Xmartlabs SRL ( http://xmartlabs.com )
//
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Eureka
import Foundation
import UIKit
import OSLog

struct HLAError: Codable, Error {
  
}

extension CharacterSet {
  static let idAllowedCharacters = CharacterSet(charactersIn: "1234567890-")
  static let alphabetsCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
  static let numericAlphabetsCharacters = alphabetsCharacters.union(idAllowedCharacters)
}

enum IdentityDocumentType: String, Codable {
  case nric = "NRIC", passport = "PP", birthcert = "BC", foreignBirthCert = "FBC", foreignID = "FID", permanentResident = "PR"
  case coy = "COY"

  static let idOptions: [IdentityDocumentType] = [.birthcert, .foreignBirthCert, .foreignID, .nric, .passport, .permanentResident]

  static let thirdPartyPayorOptions: [IdentityDocumentType] = [.birthcert, .foreignBirthCert, .coy, .foreignID, .nric, .passport, .permanentResident]

  var description: String {
    switch self {
    case .coy:
      "COMPANY REGISTRATION NO."

    case .nric:
      "NEW IDENTIFICATION NO."

    case .passport:
      "PASSPORT"

    case .birthcert:
      "BIRTH CERTIFICATE"

    case .foreignBirthCert:
      "FOREIGN BIRTH CERTIFICATE"

    case .foreignID:
      "FOREIGN IDENTIFICATION NO."

    case .permanentResident:
      "PERMANENT RESIDENT"
    }
  }

  init?(description: String?) {
    switch description?.uppercased() {
    case IdentityDocumentType.coy.description.uppercased():
      self = .coy

    case IdentityDocumentType.nric.description.uppercased():
      self = .nric

    case IdentityDocumentType.passport.description.uppercased():
      self = .passport

    case IdentityDocumentType.birthcert.description.uppercased():
      self = .birthcert

    case IdentityDocumentType.foreignBirthCert.description.uppercased():
      self = .foreignBirthCert

    case IdentityDocumentType.foreignID.description.uppercased():
      self = .foreignID

    case IdentityDocumentType.permanentResident.description.uppercased():
      self = .permanentResident

    default:
      return nil
    }
  }

  var keyboardType: UIKeyboardType {
    switch self {
    case .nric:
      .numberPad

    case .passport, .birthcert:
      .asciiCapable

    default:
      .asciiCapableNumberPad
    }
  }

  var characterSetType: CharacterSet {
    switch self {
    case .nric:
      .idAllowedCharacters

    default:
      .numericAlphabetsCharacters
    }
  }

  var requiredBackID: Bool {
    switch self {
    case .birthcert, .foreignBirthCert, .passport:
      false

    default:
      true
    }
  }

  var isForeigner: Bool {
    self == .passport || self == .foreignBirthCert || self == .foreignID || self == .permanentResident
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer().decode(String.self).uppercased()

    if let id = IdentityDocumentType(rawValue: container) {
      self = id
    } else {
      throw HLAError()
    }
  }
}

struct ImageRowSourceTypes: OptionSet {
  let rawValue: Int
  var imagePickerControllerSourceTypeRawValue: Int { self.rawValue >> 1 }

  init(rawValue: Int) { self.rawValue = rawValue }
  init(_ sourceType: UIImagePickerController.SourceType) { self.init(rawValue: 1 << sourceType.rawValue) }

  static let PhotoLibrary = ImageRowSourceTypes(.photoLibrary)
  static let Camera = ImageRowSourceTypes(.camera)
  static let SavedPhotosAlbum = ImageRowSourceTypes(.savedPhotosAlbum)
  static let All: ImageRowSourceTypes = [Camera, PhotoLibrary, SavedPhotosAlbum]
}

extension ImageRowSourceTypes {
  // MARK: Helpers

  var localizedString: String {
    switch self {
    case ImageRowSourceTypes.Camera:
      "TAKE_PHOTO_TEXT"
    case ImageRowSourceTypes.PhotoLibrary:
      "PHOTO_LIBRARY_TEXT"
    case ImageRowSourceTypes.SavedPhotosAlbum:
      "SAVED_PHOTOS_TEXT"
    default:
      ""
    }
  }
}

enum ImageClearAction {
  case no
  case yes(style: UIAlertAction.Style)
}

// MARK: Row

class _ImageRow<Cell: CellType>: OptionsRow<Cell>, PresenterRowType where Cell: BaseCell, Cell.Value == UIImage {
  typealias PresenterRow = ImagePickerController
  var imageType: IdentityDocumentType?
  var viewOnly = false
  var hasOnClickAlertBox = false
  var action: ((String?) -> ())?
  /// Defines how the view controller will be presented, pushed, etc.
  open var presentationMode: PresentationMode<PresenterRow>?

  /// Will be called before the presentation occurs.
  open var onPresentCallback: ((FormViewController, PresenterRow) -> Void)?

  open var onView: ((UIImage) -> Void)?

  open var sourceTypes: ImageRowSourceTypes
  open internal(set) var imageURL: URL?
  open var clearAction = ImageClearAction.yes(style: .destructive)

  private var _sourceType = UIImagePickerController.SourceType.camera

  required init(tag: String?) {
    sourceTypes = .All
    super.init(tag: tag)
    presentationMode = .presentModally(controllerProvider: ControllerProvider.callback {
      ImagePickerController()
    }, onDismiss: { [weak self] vc in
      Task { @MainActor in
        self?.select()
        vc.dismiss(animated: true)
      }
    })
    self.displayValueFor = nil
  }

  // copy over the existing logic from the SelectorRow
  @MainActor
  func displayImagePickerController(_ sourceType: UIImagePickerController.SourceType) {
    if hasOnClickAlertBox {
      displayAppealAlertBox(sourceType)
    } else {
      presentationController(sourceType)
    }
  }

  @MainActor
  func displayAppealAlertBox(_ sourceType: UIImagePickerController.SourceType?) {
    let alert = UIAlertController(title: "GENDER_ACK_TITLE_ACKNOWLEDGEMENT", message: "POIV_UNAPPEAL_ACKNOWLEDGEMENT", preferredStyle: .alert)
    let cancel = UIAlertAction(title: "CANCEL", style: .cancel, handler: nil)
    let okAction = UIAlertAction(title: "I_CONFIRM", style: .default) { [weak self] _ in
      guard let sourceType else {
        self?.value = nil
        self?.imageURL = nil

        self?.updateCell()

        self?.action?(nil)

        return
      }

      self?.presentationController(sourceType)
    }

    alert.addAction(cancel)
    alert.addAction(okAction)

    cell.formViewController()?.present(alert, animated: true, completion: nil)
  }

  @MainActor
  func presentationController(_ sourceType: UIImagePickerController.SourceType) {
    guard let presentationMode, !isDisabled else { return }

    if let controller = presentationMode.makeController() {
      controller.row = self
      controller.sourceType = sourceType

      onPresentCallback?(cell.formViewController()!, controller)
      presentationMode.present(controller, row: self, presentingController: cell.formViewController()!)
    } else {
      _sourceType = sourceType

      presentationMode.present(nil, row: self, presentingController: cell.formViewController()!)
    }
  }

  /// Extends `didSelect` method
  /// Selecting the Image Row cell will open a popup to choose where to source the photo from,
  /// based on the `sourceTypes` configured and the available sources.
  open override func customDidSelect() {
    guard !isDisabled else {
      super.customDidSelect()
      return
    }
    deselect()

    Task { @MainActor in
      var availableSources: ImageRowSourceTypes = []

      #if DEBUG
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
          _ = availableSources.insert(.PhotoLibrary)
        }
        if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
          _ = availableSources.insert(.SavedPhotosAlbum)
        }
      #endif
      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        let _ = availableSources.insert(.Camera)
      }

      sourceTypes.formIntersection(availableSources)

      if sourceTypes.isEmpty {
        super.customDidSelect()
        guard let presentationMode else { return }
        if let controller = presentationMode.makeController() {
          controller.row = self
          controller.title = selectorTitle ?? controller.title
          onPresentCallback?(cell.formViewController()!, controller)
          presentationMode.present(controller, row: self, presentingController: self.cell.formViewController()!)
        } else {
          presentationMode.present(nil, row: self, presentingController: self.cell.formViewController()!)
        }
        return
      }

      // Now that we know the number of sources aren't empty, let the user select the source
      let sourceActionSheet = UIAlertController(title: nil, message: selectorTitle, preferredStyle: .actionSheet)
      guard let tableView = cell.formViewController()?.tableView else { fatalError() }
      if let popView = sourceActionSheet.popoverPresentationController {
        popView.sourceView = tableView
        popView.sourceRect = tableView.convert(cell.accessoryView?.frame ?? cell.contentView.frame, from: cell)
      }
      createOptionsForAlertController(sourceActionSheet)

      if let img = value, let watermarked = addWatermark("WATERMARK_TEXT", to: img) {
        let viewOption = UIAlertAction(title: "VIEW_IMAGE_TITLE", style: .default) { [weak self] _ in
          self?.onView?(watermarked)
        }

        sourceActionSheet.addAction(viewOption)
      }

      if case .yes(let style) = clearAction, value != nil, !viewOnly {
        let clearPhotoOption = UIAlertAction(title: NSLocalizedString("CLEAR_PHOTO_TITLE", comment: ""), style: style, handler: { [weak self] _ in
          if self?.hasOnClickAlertBox == true {
            self?.displayAppealAlertBox(nil)
          } else {
            self?.value = nil
            self?.imageURL = nil

            self?.updateCell()
          }
        })
        sourceActionSheet.addAction(clearPhotoOption)
      }

      if sourceActionSheet.actions.count == 1, !viewOnly {
        if let imagePickerSourceType = UIImagePickerController.SourceType(rawValue: sourceTypes.imagePickerControllerSourceTypeRawValue) {
          displayImagePickerController(imagePickerSourceType)
        }
      } else {
        let cancelOption = UIAlertAction(title: "CANCEL", style: .cancel, handler: nil)
        sourceActionSheet.addAction(cancelOption)
        if let presentingViewController = cell.formViewController() {
          presentingViewController.present(sourceActionSheet, animated: true)
        }
      }
    }
  }

  /**
   Prepares the pushed row setting its title and completion callback.
   */
  open override func prepare(for segue: UIStoryboardSegue) {
    super.prepare(for: segue)
    Task { @MainActor in
      guard let rowVC = segue.destination as? PresenterRow else { return }
      rowVC.title = selectorTitle ?? rowVC.title
      rowVC.onDismissCallback = presentationMode?.onDismissCallback ?? rowVC.onDismissCallback
      onPresentCallback?(cell.formViewController()!, rowVC)
      rowVC.row = self
      rowVC.sourceType = _sourceType
    }
  }

  open override func customUpdateCell() {
    super.customUpdateCell()
    Task { @MainActor in
      cell.accessoryType = .none
      cell.editingAccessoryView = .none

      if let image = self.value {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        imageView.contentMode = .scaleAspectFill
        imageView.image = image
        imageView.clipsToBounds = true

        cell.accessoryView = imageView
        cell.editingAccessoryView = imageView
      } else {
        cell.accessoryView = nil
        cell.editingAccessoryView = nil
      }
    }    
  }
}

extension _ImageRow {
  // MARK: Helpers
  @MainActor
  func createOptionForAlertController(_ alertController: UIAlertController, sourceType: ImageRowSourceTypes) {
    guard let pickerSourceType = UIImagePickerController.SourceType(rawValue: sourceType.imagePickerControllerSourceTypeRawValue), sourceTypes.contains(sourceType) else { return }
    let option = UIAlertAction(title: NSLocalizedString(sourceType.localizedString, comment: ""), style: .default, handler: { [weak self] _ in
      self?.displayImagePickerController(pickerSourceType)
    })
    alertController.addAction(option)
  }

  @MainActor
  func createOptionsForAlertController(_ alertController: UIAlertController) {
    guard !viewOnly else { return }

    createOptionForAlertController(alertController, sourceType: .Camera)
    createOptionForAlertController(alertController, sourceType: .PhotoLibrary)
    createOptionForAlertController(alertController, sourceType: .SavedPhotosAlbum)
  }
}

/// A selector row where the user can pick an image
final class ImageRow: _ImageRow<PushSelectorCell<UIImage>>, RowType {
  required init(tag: String?) {
    super.init(tag: tag)
  }
}

@MainActor
private func addWatermark(_ text: String, to image: UIImage) -> UIImage? {
  let renderer = UIGraphicsImageRenderer(size: image.size)

  let watermarked = renderer.image { context in
    image.draw(at: .zero)

    let centerPoint = CGPoint(x: image.size.width / 2, y: image.size.height / 2)

    context.cgContext.translateBy(x: centerPoint.x, y: centerPoint.y)
    context.cgContext.rotate(by: .pi / 5)
    context.cgContext.translateBy(x: -centerPoint.x, y: -centerPoint.y)

    let label = UILabel(frame: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
    label.adjustsFontSizeToFitWidth = true
    label.backgroundColor = .clear
    label.numberOfLines = 1

    label.text = text
    label.textAlignment = .center
    label.textColor = .red.withAlphaComponent(0.5)
    label.font = .systemFont(ofSize: 1000, weight: .medium)

    label.draw(label.frame)
  }

  return watermarked
}
