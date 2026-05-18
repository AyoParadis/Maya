import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal

final class DeviceFrameCompositionInstruction: AVMutableVideoCompositionInstruction, @unchecked Sendable {
    nonisolated(unsafe) var renderTransparent: Bool = false
    nonisolated(unsafe) var deviceFrame: DeviceFrame = .iPhone15Pro
    nonisolated(unsafe) var scale: CGFloat = 1.0
    nonisolated(unsafe) var offsetFraction: CGSize = .zero
    nonisolated(unsafe) var sourceTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    nonisolated(unsafe) var backgroundImage: CIImage?
    nonisolated(unsafe) var frameOverlay: CIImage?
    nonisolated(unsafe) var naturalHeightFraction: CGFloat = 0.9
    nonisolated(unsafe) var animations: [ZoomSegment] = []
    nonisolated(unsafe) var shadow: PhoneShadow = PhoneShadow()
    nonisolated(unsafe) var shadowColor: CIColor = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// Used when `deviceFrame.kind != .physical` to derive the screen corner
    /// radius from the user-controlled slider. Normalized to the screen's
    /// short side: 0 = sharp, 0.5 = stadium.
    nonisolated(unsafe) var bareCornerRadius: CGFloat = 0.12
    /// Generic bezel stroke width as a fraction of phone width (0 = no bezel).
    nonisolated(unsafe) var bareBezelWidth: CGFloat = 0.025
    /// Generic bezel fill color, in CIColor space (pre-converted from hex by the snapshot).
    nonisolated(unsafe) var bareBezelColor: CIColor = CIColor.black

    /// Declares which source tracks the compositor needs. Without this AVFoundation
    /// won't feed any frames into `request.sourceFrame(byTrackID:)` and the export fails
    /// with "source frame is missing". Critical for any custom AVVideoCompositing impl.
    nonisolated override var requiredSourceTrackIDs: [NSValue] {
        sourceTrackID != kCMPersistentTrackID_Invalid
            ? [NSNumber(value: sourceTrackID)]
            : []
    }

    nonisolated override var passthroughTrackID: CMPersistentTrackID {
        kCMPersistentTrackID_Invalid
    }

    nonisolated override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class DeviceFrameCompositor: NSObject, AVVideoCompositing {
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            ])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    private let renderQueue = DispatchQueue(label: "maya.compositor.render", qos: .userInitiated)
    private var renderContext: AVVideoCompositionRenderContext?

    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync { renderContext = newRenderContext }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            self?.process(request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    private func process(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? DeviceFrameCompositionInstruction,
              let context = renderContext else {
            request.finish(with: CompositorError.missingContext)
            return
        }
        guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID) else {
            request.finish(with: CompositorError.missingSource)
            return
        }

        let renderSize = context.size
        let renderRect = CGRect(origin: .zero, size: renderSize)

        // Resolve effective scale/offset: sample any active zoom segment at the current
        // composition time. Outside segments the camera holds at the instruction's base values.
        let seconds = request.compositionTime.seconds
        let sample = AnimationSampler.sample(
            at: seconds.isFinite ? seconds : 0,
            segments: instruction.animations,
            baseScale: instruction.scale,
            baseOffset: instruction.offsetFraction
        )
        let effectiveScale = sample.scale
        let effectiveOffset = CGSize(width: sample.offsetX, height: sample.offsetY)

        // Phone bounding box in render coords (CoreImage: origin bottom-left).
        // In `.none` mode the "phone" is just the bare video, so its aspect is
        // the source video's aspect rather than the device frame's.
        let source = CIImage(cvPixelBuffer: sourceBuffer)
        let sourceSize = source.extent.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            request.finish(with: CompositorError.invalidSource)
            return
        }
        let effectiveAspect: CGFloat = {
            switch instruction.deviceFrame.kind {
            case .none, .generic:
                return sourceSize.width / sourceSize.height
            case .physical:
                return instruction.deviceFrame.frameAspectRatio
            }
        }()
        // Fit the device within `naturalHeightFraction` of both axes so a
        // landscape device (MacBook, aspect > 1) does not overflow the canvas.
        // Matches `FramedDeviceView.phoneSize`.
        let maxH = renderSize.height * instruction.naturalHeightFraction
        let maxW = renderSize.width * instruction.naturalHeightFraction
        let naturalPhoneWidth = min(maxW, maxH * effectiveAspect)
        let naturalPhoneHeight = effectiveAspect > 0 ? naturalPhoneWidth / effectiveAspect : maxH
        let phoneHeight = naturalPhoneHeight * effectiveScale
        let phoneWidth = naturalPhoneWidth * effectiveScale

        // SwiftUI offset is in canvas-side fractions of the short side so the drag
        // feel matches across canvas aspects. Mirror that here.
        let offsetRef = min(renderSize.width, renderSize.height)
        let dx = effectiveOffset.width * offsetRef
        let dy = effectiveOffset.height * offsetRef
        let phoneCenter = CGPoint(
            x: renderSize.width / 2 + dx,
            y: renderSize.height / 2 - dy
        )
        let phoneOrigin = CGPoint(
            x: phoneCenter.x - phoneWidth / 2,
            y: phoneCenter.y - phoneHeight / 2
        )

        // Screen rect inside the phone, in render coords (flip y because DeviceFrame uses top-left).
        let screenRectInPhone = instruction.deviceFrame.screenRect(in: CGSize(width: phoneWidth, height: phoneHeight))
        let screenRect = CGRect(
            x: phoneOrigin.x + screenRectInPhone.minX,
            y: phoneOrigin.y + (phoneHeight - screenRectInPhone.maxY),
            width: screenRectInPhone.width,
            height: screenRectInPhone.height
        )
        let cornerRadius: CGFloat = {
            switch instruction.deviceFrame.kind {
            case .physical:
                return instruction.deviceFrame.screenCornerRadiusNormalized * phoneWidth
            case .none, .generic:
                return instruction.bareCornerRadius * min(screenRect.width, screenRect.height)
            }
        }()

        // 1. Background
        let background: CIImage
        if instruction.renderTransparent {
            background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: renderRect)
        } else if let bg = instruction.backgroundImage {
            background = scaleToFill(bg, target: renderRect)
        } else {
            background = CIImage(color: .black).cropped(to: renderRect)
        }

        // 1b. Drop shadow under the phone — blurred rounded-rect silhouette of the
        // phone bounding box, tinted with the user's shadow color and opacity.
        // Blur, offset and shape all scale with `effectiveScale` so the shadow
        // grows with the phone, matching SwiftUI's `.shadow` + `.scaleEffect` order.
        var workingBg = background
        if instruction.shadow.enabled, instruction.shadow.opacity > 0 {
            let outerCornerRadius: CGFloat = {
                if instruction.deviceFrame.kind == .none {
                    return cornerRadius
                }
                // Outer corner radius of an iPhone Pro hull is ~13.5% of width;
                // good enough across all hardware variants since the shadow is blurred.
                return phoneWidth * 0.135
            }()
            let scaledOffsetX = instruction.shadow.offsetX * effectiveScale
            let scaledOffsetY = instruction.shadow.offsetY * effectiveScale
            let scaledBlur = instruction.shadow.radius * effectiveScale

            let phoneRect = CGRect(
                x: phoneOrigin.x + scaledOffsetX,
                // SwiftUI offsetY is downward; CoreImage Y is upward.
                y: phoneOrigin.y - scaledOffsetY,
                width: phoneWidth,
                height: phoneHeight
            )

            let shadowColor = CIColor(
                red: instruction.shadowColor.red,
                green: instruction.shadowColor.green,
                blue: instruction.shadowColor.blue,
                alpha: CGFloat(instruction.shadow.opacity)
            )

            let silhouetteGen = CIFilter.roundedRectangleGenerator()
            silhouetteGen.extent = phoneRect
            silhouetteGen.radius = Float(outerCornerRadius)
            silhouetteGen.color = shadowColor

            if var silhouette = silhouetteGen.outputImage?.cropped(to: phoneRect) {
                if scaledBlur > 0.5 {
                    // Expand crop so blurred edges aren't clipped before being composited.
                    let pad = scaledBlur * 3
                    let blurExtent = phoneRect.insetBy(dx: -pad, dy: -pad)
                    silhouette = silhouette
                        .applyingGaussianBlur(sigma: scaledBlur)
                        .cropped(to: blurExtent)
                }
                workingBg = silhouette.composited(over: workingBg).cropped(to: renderRect)
            }
        }

        // 2. Source video scaled aspect-fill into screenRect (source already
        // unpacked above for aspect calculation).
        let fillScale = max(screenRect.width / sourceSize.width, screenRect.height / sourceSize.height)
        var video = source.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
        let videoCenter = CGPoint(x: video.extent.midX, y: video.extent.midY)
        video = video.transformed(by: CGAffineTransform(
            translationX: screenRect.midX - videoCenter.x,
            y: screenRect.midY - videoCenter.y
        ))
        video = video.cropped(to: screenRect)

        // 3. Rounded mask
        let rounded = CIFilter.roundedRectangleGenerator()
        rounded.extent = screenRect
        rounded.radius = Float(cornerRadius)
        rounded.color = CIColor.white
        let mask = rounded.outputImage?.cropped(to: screenRect) ?? CIImage(color: .white).cropped(to: screenRect)

        let masked = CIFilter.blendWithMask()
        masked.inputImage = video
        masked.maskImage = mask
        masked.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: screenRect)
        let maskedVideo = masked.outputImage ?? video

        // 4. Composite: video over background (with shadow already baked in)
        var result = maskedVideo.composited(over: workingBg)

        // 4b. Generic bezel: ring that grows OUTWARD from the screen edge (no
        // PNG overlay, no notch). Width and color come from the user. Skipped
        // entirely when the user dialed the width slider to 0.
        if instruction.deviceFrame.kind == .generic {
            let bezelW = phoneWidth * instruction.bareBezelWidth
            if bezelW > 0.5 {
                let outerRect = screenRect.insetBy(dx: -bezelW, dy: -bezelW)
                let outerRadius = cornerRadius + bezelW

                let outerFill = CIFilter.roundedRectangleGenerator()
                outerFill.extent = outerRect
                outerFill.radius = Float(outerRadius)
                outerFill.color = instruction.bareBezelColor

                let innerCut = CIFilter.roundedRectangleGenerator()
                innerCut.extent = screenRect
                innerCut.radius = Float(cornerRadius)
                innerCut.color = CIColor.white

                if let outerImage = outerFill.outputImage?.cropped(to: outerRect),
                   let innerImage = innerCut.outputImage?.cropped(to: screenRect) {
                    let cut = CIFilter.sourceOutCompositing()
                    cut.inputImage = outerImage
                    cut.backgroundImage = innerImage
                    if let ring = cut.outputImage?.cropped(to: outerRect) {
                        result = ring.composited(over: result)
                    }
                }
            }
        }

        // 5. Frame overlay (PNG or placeholder), fit into phone bounding box
        if let overlay = instruction.frameOverlay {
            let ovExtent = overlay.extent
            guard ovExtent.width > 0, ovExtent.height > 0 else {
                finishRender(request: request, image: result, context: context, renderRect: renderRect)
                return
            }
            let fitScale = min(phoneWidth / ovExtent.width, phoneHeight / ovExtent.height)
            var overlayScaled = overlay.transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))
            let exCenter = CGPoint(x: overlayScaled.extent.midX, y: overlayScaled.extent.midY)
            overlayScaled = overlayScaled.transformed(by: CGAffineTransform(
                translationX: phoneCenter.x - exCenter.x,
                y: phoneCenter.y - exCenter.y
            ))
            result = overlayScaled.composited(over: result)
        }

        finishRender(request: request, image: result, context: context, renderRect: renderRect)
    }

    private func finishRender(request: AVAsynchronousVideoCompositionRequest,
                              image: CIImage,
                              context: AVVideoCompositionRenderContext,
                              renderRect: CGRect) {
        guard let output = context.newPixelBuffer() else {
            request.finish(with: CompositorError.cannotAllocateBuffer)
            return
        }
        ciContext.render(image.cropped(to: renderRect),
                         to: output,
                         bounds: renderRect,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }

    private func scaleToFill(_ image: CIImage, target: CGRect) -> CIImage {
        let s = image.extent.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = max(target.width / s.width, target.height / s.height)
        var scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        scaled = scaled.transformed(by: CGAffineTransform(
            translationX: target.midX - scaled.extent.midX,
            y: target.midY - scaled.extent.midY
        ))
        return scaled.cropped(to: target)
    }
}

enum CompositorError: LocalizedError {
    case missingContext
    case missingSource
    case invalidSource
    case cannotAllocateBuffer

    var errorDescription: String? {
        switch self {
        case .missingContext: "Compositor render context is unavailable."
        case .missingSource: "Source frame is missing for the requested track."
        case .invalidSource: "Source video has invalid dimensions."
        case .cannotAllocateBuffer: "Could not allocate output pixel buffer."
        }
    }
}
