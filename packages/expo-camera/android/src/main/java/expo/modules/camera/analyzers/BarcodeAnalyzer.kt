package expo.modules.camera.analyzers

import android.util.Log
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import expo.modules.camera.CameraViewHelper
import expo.modules.camera.records.BarcodeType
import expo.modules.camera.records.CameraType
import expo.modules.interfaces.barcodescanner.BarCodeScannerResult
import java.nio.ByteBuffer

@OptIn(ExperimentalGetImage::class)
class BarcodeAnalyzer(
  private val lensFacing: CameraType,
  formats: List<BarcodeType>,
  val onComplete: (List<BarCodeScannerResult>) -> Unit
) : ImageAnalysis.Analyzer {

  private val barcodeFormats = if (formats.isEmpty()) {
    0
  } else {
    formats.map { it.mapToBarcode() }.reduce { acc, it -> acc or it }
  }

  private var barcodeScannerOptions = BarcodeScannerOptions.Builder()
    .setBarcodeFormats(barcodeFormats)
    .build()

  private var barcodeScanner = BarcodeScanning.getClient(barcodeScannerOptions)

  override fun analyze(imageProxy: ImageProxy) {
    val mediaImage = imageProxy.image

    if (mediaImage != null) {
      val rotation = CameraViewHelper.getCorrectCameraRotation(
        imageProxy.imageInfo.rotationDegrees, lensFacing
      )
      val image = InputImage.fromMediaImage(mediaImage, rotation)

      barcodeScanner.process(image)
        .addOnSuccessListener { barcodes ->
          if (barcodes.isEmpty()) {
            return@addOnSuccessListener
          }

          // Collect all barcode results into a list
          val results = barcodes.map { barcode ->
            val raw = barcode.rawValue ?: barcode.rawBytes?.let { String(it) }
            val cornerPoints = mutableListOf<Int>()

            barcode.cornerPoints?.let { points ->
              for (point in points) {
                cornerPoints.addAll(listOf(point.x, point.y))
              }
            }

            // Create a result object for each barcode
            BarCodeScannerResult(
              barcode.format,
              barcode.displayValue,
              raw,
              cornerPoints,
              image.width,
              image.height
            )
          }

          // Return the list of barcode results
          onComplete(results)
        }
        .addOnFailureListener {
          Log.d("SCANNER", it.cause?.message ?: "Barcode scanning failed")
        }
        .addOnCompleteListener {
          imageProxy.close()
        }
    }
  }
}

private fun ByteBuffer.toByteArray(): ByteArray {
  rewind()
  val data = ByteArray(remaining())
  get(data)
  return data
}

fun Array<ImageProxy.PlaneProxy>.toByteArray() = this.fold(mutableListOf<Byte>()) { acc, plane ->
  acc.addAll(plane.buffer.toByteArray().toList())
  acc
}.toByteArray()
