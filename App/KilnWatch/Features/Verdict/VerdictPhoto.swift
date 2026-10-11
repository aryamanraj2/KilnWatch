import ImageIO
import KilnWatchCore
import SwiftUI
import UIKit

struct VerdictPhoto: Identifiable {
    let record: Photo
    let jpeg: Data
    var id: UUID { record.id }
}

/// Creates a new JPEG from pixels only; source EXIF/GPS and other metadata are not copied.
enum VerdictJPEG {
    @concurrent static func prepare(_ data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

struct VerdictCamera: UIViewControllerRepresentable {
    let captured: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(captured: captured) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let captured: (Data?) -> Void
        init(captured: @escaping (Data?) -> Void) { self.captured = captured }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { captured(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { captured(nil); return }
            let scale = min(1, 2048 / max(image.size.width * image.scale, image.size.height * image.scale))
            let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let output = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            captured(output.jpegData(compressionQuality: 0.7))
        }
    }
}
