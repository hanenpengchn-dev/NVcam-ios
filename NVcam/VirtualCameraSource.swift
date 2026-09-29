import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import UIKit
final class VirtualCameraSource {
    private let queue = DispatchQueue(label: "com.nvcam.virtualcamera", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var frameCount: Int = 0
    var onFrameGenerated: ((UIImage, Int) -> Void)?
    
    func start() { queue.async { self.startInternal() } }
    func stop() { queue.async { self.timer?.cancel(); self.timer = nil } }
    
    private func startInternal() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in self?.generateFrame() }
        timer.resume()
        self.timer = timer
    }
    
    private func generateFrame() {
        frameCount += 1
        let image = makeTestPatternImage(frameNumber: frameCount)
        DispatchQueue.main.async { [weak self] in
            self?.onFrameGenerated?(image, self?.frameCount ?? 0)
        }
    }
    
    private func makeTestPatternImage(frameNumber: Int) -> UIImage {
        let size = CGSize(width: 1280, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors: [UIColor] = [.systemBlue, .systemPurple, .systemTeal, .systemOrange]
            for (index, color) in colors.enumerated() {
                let rect = CGRect(x: CGFloat(index) * size.width / 4, y: 0, width: size.width / 4, height: size.height)
                color.setFill()
                cg.fill(rect)
            }
            let text = "Frame: \(frameNumber)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.white]
            text.draw(at: CGPoint(x: 50, y: 50), withAttributes: attrs)
        }
    }
}
