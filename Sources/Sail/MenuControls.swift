import AppKit

/// One menu row: title, slider snapping to `step`, value label. Laid out to match the
/// text column of regular menu items (left of the checkmark column) and stretched to the
/// menu's full width. The label updates live; `onCommit` fires when the mouse is released.
final class SliderRow: NSView {
    static let minWidth: CGFloat = 300
    static let height: CGFloat = 24
    /// Where regular menu item text starts (after the checkmark column).
    private static let leftInset: CGFloat = 29
    /// Right padding, lines up with the key-equivalent column of regular items.
    private static let rightInset: CGFloat = 20
    private static let labelWidth: CGFloat = 118
    private static let valueWidth: CGFloat = 50

    private let title = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private let step: Int
    private let format: (Int) -> String
    var onCommit: ((Int) -> Void)?
    private(set) var value: Int

    init(title text: String, min: Int, max: Int, step: Int, value: Int, format: @escaping (Int) -> String) {
        self.step = step
        self.format = format
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.height))
        autoresizingMask = [.width]

        title.stringValue = text
        title.font = NSFont.menuFont(ofSize: 0)
        title.lineBreakMode = .byTruncatingTail

        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.integerValue = value
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed)

        valueLabel.font = NSFont.menuFont(ofSize: 0)
        valueLabel.alignment = .right
        valueLabel.stringValue = format(value)

        addSubview(title)
        addSubview(slider)
        addSubview(valueLabel)
        layoutRow()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutRow()
    }

    private func layoutRow() {
        let w = bounds.width
        let textY = (Self.height - 17) / 2
        title.frame = NSRect(x: Self.leftInset, y: textY, width: Self.labelWidth, height: 17)
        valueLabel.frame = NSRect(x: w - Self.rightInset - Self.valueWidth, y: textY, width: Self.valueWidth, height: 17)
        let sliderX = Self.leftInset + Self.labelWidth + 8
        let sliderW = max(60, valueLabel.frame.minX - 8 - sliderX)
        slider.frame = NSRect(x: sliderX, y: (Self.height - 16) / 2, width: sliderW, height: 16)
    }

    var isEnabled: Bool {
        get { slider.isEnabled }
        set {
            slider.isEnabled = newValue
            title.textColor = newValue ? .labelColor : .disabledControlTextColor
            valueLabel.textColor = newValue ? .labelColor : .disabledControlTextColor
        }
    }

    func set(_ v: Int) {
        value = v
        slider.integerValue = v
        valueLabel.stringValue = format(v)
    }

    @objc private func changed() {
        let snapped = Int((slider.doubleValue / Double(step)).rounded()) * step
        slider.integerValue = snapped
        value = snapped
        valueLabel.stringValue = format(snapped)
        if NSApp.currentEvent?.type != .leftMouseDragged {
            onCommit?(snapped)
        }
    }
}
