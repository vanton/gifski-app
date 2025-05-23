import SwiftUI
import AVFoundation

struct CropToolbarItems: View {
	@State private var showCropTooltip = false

	@Binding var isCropActive: Bool
	let metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	var body: some View {
		if isCropActive {
			AspectRatioPicker(
				metadata: metadata,
				outputCropRect: $outputCropRect
			)
		}
		Toggle("Crop", systemImage: "crop", isOn: $isCropActive)
			.onChange(of: isCropActive) {
				guard isCropActive else {
					return
				}

				SSApp.runOnce(identifier: "showCropTooltip") {
					showCropTooltip = true
				}
			}
			.popover(isPresented: $showCropTooltip) {
				TipsView(title: "Crop Tips", tips: Self.tips)
			}
	}

	private static let tips = [
		"• Hold Shift to scale both sides.",
		"• Hold Option to resize from the center.",
		"• Hold both to keep aspect ratio and resize from center."
	]
}

/**
The range of valid numbers for the aspect ratio.
*/
private let aspectRatioNumberRange = 1...99

private enum CustomFieldType {
	case pixel
	case aspect
}

private struct AspectRatioPicker: View {
	@State private var showEnterCustomAspectRatio = false
	@State private var customAspectRatio: PickerAspectRatio?
	@State private var customPixelSize = CGSize.zero
	@State private var modifiedCustomField: CustomFieldType?

	let metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	var body: some View {
		Menu(selectionText) {
			presetSection
			customSection
			otherSections
		}
		.onChange(of: customAspectRatio) {
			guard let customAspectRatio else {
				return
			}

			outputCropRect = outputCropRect.withAspectRatio(
				for: customAspectRatio,
				forDimensions: metadata.dimensions
			)
		}
		.staticPopover(isPresented: $showEnterCustomAspectRatio) {
			CustomAspectRatioView(
				cropRect: $outputCropRect,
				customAspectRatio: $customAspectRatio,
				customPixelSize: $customPixelSize,
				modifiedCustomField: $modifiedCustomField,
				dimensions: metadata.dimensions
			)
		}
	}

	private var selectionText: String {
		PickerAspectRatio.selectionText(for: aspect, customAspectRatio: customAspectRatio, videoDimensions: metadata.dimensions, cropRect: outputCropRect)
	}

	private var presetSection: some View {
		Section("Presets") {
			ForEach(PickerAspectRatio.presets, id: \.self) { aspectRatio in
				AspectToggle(
					aspectRatio: aspectRatio,
					outputCropRect: $outputCropRect,
					customAspectRatio: $customAspectRatio,
					currentAspect: aspect,
					dimensions: metadata.dimensions
				)
			}
		}
	}

	@ViewBuilder
	private var customSection: some View {
		if
			let customAspectRatio,
			!customAspectRatio.matchesPreset()
		{
			Section("Custom") {
				AspectToggle(
					aspectRatio: customAspectRatio,
					outputCropRect: $outputCropRect,
					customAspectRatio: $customAspectRatio,
					currentAspect: aspect,
					dimensions: metadata.dimensions
				)
			}
		}
	}

	@ViewBuilder
	private var otherSections: some View {
		Section {
			Button("Custom") {
				handleCustomAspectButton()
			}
		}
		Section {
			Button("Reset") {
				resetAspectRatio()
			}
		}
	}

	private var aspect: Double {
		let cropRectInPixels = outputCropRect.unnormalize(forDimensions: metadata.dimensions)
		return cropRectInPixels.width / cropRectInPixels.height
	}

	private func handleCustomAspectButton() {
		let cropSizeRightNow = outputCropRect.unnormalize(forDimensions: metadata.dimensions).size

		customAspectRatio = PickerAspectRatio.closestAspectRatio(
			for: cropSizeRightNow,
			within: aspectRatioNumberRange
		)

		customPixelSize = cropSizeRightNow
		modifiedCustomField = nil
		showEnterCustomAspectRatio = true
	}

	private func resetAspectRatio() {
		customAspectRatio = nil
		outputCropRect = .initialCropRect
	}
}

private struct AspectToggle: View {
	var aspectRatio: PickerAspectRatio
	@Binding var outputCropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	var currentAspect: Double
	var dimensions: CGSize

	var body: some View {
		Toggle(aspectRatio.description, isOn: .init(
			get: {
				aspectRatio.aspectRatio.isAlmostEqual(to: currentAspect)
			},
			set: { _ in
				outputCropRect = outputCropRect.withAspectRatio(for: aspectRatio, forDimensions: dimensions)
			}
		))
	}
}

private struct CustomAspectRatioView: View {
	@Binding var cropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	@Binding var customPixelSize: CGSize
	@Binding var modifiedCustomField: CustomFieldType?
	var dimensions: CGSize

	var body: some View {
		VStack(spacing: 10) {
			HStack(spacing: 4) {
				CustomAspectField(
					customAspectRatio: $customAspectRatio,
					modifiedCustomField: $modifiedCustomField,
					side: \.width
				)
				Text(":")
					.foregroundStyle(.secondary)
				CustomAspectField(
					customAspectRatio: $customAspectRatio,
					modifiedCustomField: $modifiedCustomField,
					side: \.height
				)
			}
			.frame(width: 90)
			.opacity(modifiedCustomField == .pixel ? 0.7 : 1)
			HStack(spacing: 4) {
				CustomPixelField(
					customPixelSize: $customPixelSize,
					cropRect: $cropRect,
					modifiedCustomField: $modifiedCustomField,
					dimensions: dimensions,
					side: \.width
				)
				Text("x")
					.foregroundStyle(.secondary)
				CustomPixelField(
					customPixelSize: $customPixelSize,
					cropRect: $cropRect,
					modifiedCustomField: $modifiedCustomField,
					dimensions: dimensions,
					side: \.height
				)
			}
			.opacity(modifiedCustomField == .aspect ? 0.7 : 1)
		}
		.padding()
		.frame(width: 135)
	}
}

private struct CustomPixelField: View {
	@Binding var customPixelSize: CGSize
	@Binding var cropRect: CropRect
	@Binding var modifiedCustomField: CustomFieldType?

	var dimensions: CGSize
	// swiftlint:disable:next no_cgfloat
	let side: WritableKeyPath<CGSize, CGFloat>
	@State private var showWarning = false

	static let minValue = 100
	var body: some View {
		IntTextField(
			value: .init(
				get: {
					value
				},
				set: {
					let newValue = $0.clamped(to: Self.minValue...Int(dimensions[keyPath: side]))

					var newSize = cropRect.size
					newSize[keyPath: unitSizeSide] = Double(newValue) / dimensions[keyPath: side]
					cropRect = cropRect.centeredRectWith(size: newSize, minSize: CropRect.minSize(videoSize: dimensions))

					if value != $0 {
						modifiedCustomField = .pixel
					}

					customPixelSize[keyPath: side] = Double($0)
					showWarning = $0 < Self.minValue
				}
			),
			minMax: Self.minValue...Int(dimensions[keyPath: side]),
			alignment: isWidth ? .right : .left,
			font: .fieldFont
		)
		.frame(width: 42.0)
		.popover2(isPresented: $showWarning) {
			VStack {
				Text("Value is too small")
				Text("\(value) < \(Self.minValue)")
			}
			.padding()
		}
	}

	var value: Int {
		Int(customPixelSize[keyPath: side].rounded())
	}

	var isWidth: Bool {
		side == \.width
	}

	var unitSizeSide: WritableKeyPath<UnitSize, Double> {
		isWidth ? \.width : \.height
	}
}

private struct CustomAspectField: View {
	@Binding var customAspectRatio: PickerAspectRatio?
	@Binding var modifiedCustomField: CustomFieldType?
	let side: WritableKeyPath<PickerAspectRatio, Int>

	var body: some View {
		IntTextField(
			value: .init(
				get: {
					customAspectRatio?[keyPath: side] ?? 1
				},
				set: {
					guard
						var customAspectRatioCopy = customAspectRatio,
						$0 > 0
					else {
						return
					}

					if customAspectRatioCopy[keyPath: side] != $0 {
						modifiedCustomField = .aspect
					}

					customAspectRatioCopy[keyPath: side] = $0
					customAspectRatio = customAspectRatioCopy
				}
			),
			minMax: aspectRatioNumberRange,
			alignment: side == \.width ? .right : .left,
			font: .fieldFont
		)
		.frame(width: 26.0)
	}
}

private struct TipsView: View {
	let title: String
	let tips: [String]

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.headline)
			ForEach(tips, id: \.self) { tip in
				Text(tip)
			}
		}
		.padding()
		.fixedSize()
	}
}

extension NSFont {
	fileprivate static let fieldFont = monospacedDigitSystemFont(ofSize: 12, weight: .regular)
}
