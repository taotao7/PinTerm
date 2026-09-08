import AppKit

@MainActor
final class PanelSizeDialog {
    let alert = NSAlert()
    let width: NSTextField
    let height: NSTextField
    private let maximum: NSSize

    init(size: NSSize, maximum: NSSize) {
        self.maximum = maximum
        width = NSTextField(string: String(Int(size.width)))
        height = NSTextField(string: String(Int(size.height)))
        alert.messageText = "设置当前面板宽高"
        alert.informativeText = "单位为 macOS 点数（不是终端行列）。最小 320 × 180，最大 \(Int(maximum.width)) × \(Int(maximum.height))；仅调整当前面板，不重启任务。"
        let stack = NSStackView(views: [NSTextField(labelWithString: "宽度"), width,
            NSTextField(labelWithString: "高度"), height])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 112)
        for field in [width, height] { field.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        alert.accessoryView = stack
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "取消")
    }

    func selectedSize() throws -> NSSize {
        guard let w = Double(width.stringValue), let h = Double(height.stringValue),
              w.isFinite, h.isFinite, w >= 320, h >= 180,
              w <= maximum.width, h <= maximum.height else {
            throw ConfigurationError("请输入有效宽高：至少 320 × 180，且不超过当前屏幕可用大小。")
        }
        return NSSize(width: w, height: h)
    }
}
