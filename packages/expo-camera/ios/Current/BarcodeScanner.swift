import ZXingObjC
import AVFoundation

let BARCODE_TYPES_KEY = "barcodeTypes"

class BarcodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
  var onBarcodeScanned: (([String: Any]?) -> Void)?
  var onBarcodesScanned: (([String: Any]?) -> Void)?
  var isScanningBarcodes = false

  // MARK: - Properties

  private let session: AVCaptureSession
  private let sessionQueue: DispatchQueue
  private let zxingCaptureQueue = DispatchQueue(label: "com.zxing.captureQueue")

  private var metadataOutput: AVCaptureMetadataOutput?
  private var settings = BarcodeScannerUtils.getDefaultSettings()
  private var zxingBarcodeReaders: [AVMetadataObject.ObjectType: ZXReader] = [:]
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var zxingFPSProcessed = 6.0
  private var zxingEnabled = true

  init(session: AVCaptureSession, sessionQueue: DispatchQueue) {
    self.session = session
    self.sessionQueue = sessionQueue
 }

  func setSettings(_ newSettings: [String: [AVMetadataObject.ObjectType]]) {
    for (key, value) in newSettings where key == BARCODE_TYPES_KEY {
      let previousTypes = Set(settings[BARCODE_TYPES_KEY] ?? [])
      let newTypes = Set(value)
      if previousTypes != newTypes {
        settings[BARCODE_TYPES_KEY] = value
        let zxingCoveredTypes = Set(zxingBarcodeReaders.keys)
        zxingEnabled = !zxingCoveredTypes.isDisjoint(with: newTypes)
        sessionQueue.async {
          self.maybeStartBarcodeScanning()
        }
      }
    }
  }

  func setPreviewLayer(layer: AVCaptureVideoPreviewLayer) {
    self.previewLayer = layer
  }

  func setIsEnabled(_ enabled: Bool) {
    guard isScanningBarcodes != enabled else {
      return
    }

    isScanningBarcodes = enabled
    sessionQueue.async {
      if self.isScanningBarcodes {
        if self.metadataOutput != nil {
          self.setConnection(enabled: true)
        } else {
          self.maybeStartBarcodeScanning()
        }
      } else {
        self.setConnection(enabled: false)
      }
    }
  }

  func setConnection(enabled: Bool) {
    metadataOutput?.connections.forEach {
      $0.isEnabled = enabled
    }
  }

  func maybeStartBarcodeScanning() {
    guard isScanningBarcodes else {
      return
    }

    if metadataOutput == nil {
      addOutputs()
      if metadataOutput == nil {
        return
      }
    }

    let availableObjectTypes: [AVMetadataObject.ObjectType] = metadataOutput?.availableMetadataObjectTypes ?? []
    let requestedTypes = (settings[BARCODE_TYPES_KEY] ?? []).filter {
      availableObjectTypes.contains($0)
    }

    metadataOutput?.metadataObjectTypes = requestedTypes
  }

  func stopBarcodeScanning() {
    removeOutputs()
    if isScanningBarcodes {
      onBarcodeScanned?(nil)
    }
  }

  private func addOutputs() {
    session.beginConfiguration()

    if metadataOutput == nil {
      let output = AVCaptureMetadataOutput()
      output.setMetadataObjectsDelegate(self, queue: sessionQueue)
      if session.canAddOutput(output) {
        session.addOutput(output)
        metadataOutput = output
      }
    }
    session.commitConfiguration()
  }

  private func removeOutputs() {
    session.beginConfiguration()

    if let metadataOutput {
      if session.outputs.contains(metadataOutput) {
        session.removeOutput(metadataOutput)
        self.metadataOutput = nil
      }
    }

    session.commitConfiguration()
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard let settings = settings[BARCODE_TYPES_KEY] else {
      return
    }

    var scannedBarcodes: [[String: Any]] = []


    for metadata in metadataObjects {
      var codeMetadata = metadata as? AVMetadataMachineReadableCodeObject
      if let previewLayer {
        codeMetadata = previewLayer.transformedMetadataObject(for: metadata) as? AVMetadataMachineReadableCodeObject
      }

      for barcodeType in settings {
        if zxingBarcodeReaders[barcodeType] != nil {
          continue
        }

        if let codeMetadata, let stringValue = codeMetadata.stringValue, codeMetadata.type == barcodeType {
          let barcodeDict = BarcodeScannerUtils.avMetadataCodeObjectToDictionary(codeMetadata)
          scannedBarcodes.append(barcodeDict)
        }
      }
    }
    if !scannedBarcodes.isEmpty {
      let payload: [String: Any] = [
        "payload": scannedBarcodes
      ]
      onBarcodesScanned?(payload)

      onBarcodeScanned?(scannedBarcodes.first)
    }
  }
}
