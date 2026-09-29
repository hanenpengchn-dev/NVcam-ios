import UIKit
final class CameraMonitorViewController: UIViewController {
    private let source = VirtualCameraSource()
    private let previewImageView = UIImageView()
    private let statusLabel = UILabel()
    private let frameLabel = UILabel()
    private let infoTextView = UITextView()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "NVcam Monitor"
        view.backgroundColor = .systemBackground
        setupUI()
        setupSource()
    }
    
    private func setupSource() {
        source.onFrameGenerated = { [weak self] image, frameCount in
            self?.previewImageView.image = image
            self?.frameLabel.text = "Frame: \(frameCount)"
        }
    }
    
    private func setupUI() {
        previewImageView.contentMode = .scaleAspectFit
        previewImageView.backgroundColor = .secondarySystemBackground
        previewImageView.layer.cornerRadius = 12
        previewImageView.clipsToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.text = "虚拟相机已初始化"
        statusLabel.numberOfLines = 0
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        frameLabel.text = "Frame: 0"
        frameLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        frameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        infoTextView.text = "NVcam Virtual Camera Monitor\n\n用途：\n- 监控注入的虚拟相机画面\n- 测试 mediaserverd hook 功能\n- 验证 AVCapture 拦截\n- MDM 设备管理集成\n\n状态：未启动\n\n注意：此应用需要在已越狱的 iOS 设备上运行。"
        infoTextView.isEditable = false
        infoTextView.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        infoTextView.translatesAutoresizingMaskIntoConstraints = false
        
        startButton.setTitle("启动相机", for: .normal)
        startButton.addTarget(self, action: #selector(startCamera), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        
        stopButton.setTitle("停止相机", for: .normal)
        stopButton.addTarget(self, action: #selector(stopCamera), for: .touchUpInside)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        
        let buttonStack = UIStackView(arrangedSubviews: [startButton, stopButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let mainStack = UIStackView(arrangedSubviews: [previewImageView, statusLabel, frameLabel, infoTextView, buttonStack])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.alignment = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            mainStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor, multiplier: 9.0/16.0),
            infoTextView.heightAnchor.constraint(equalToConstant: 200),
            buttonStack.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    @objc private func startCamera() {
        source.start()
        statusLabel.text = "✓ 虚拟相机正在输出画面"
        statusLabel.textColor = .systemGreen
    }
    
    @objc private func stopCamera() {
        source.stop()
        statusLabel.text = "✗ 虚拟相机已停止"
        statusLabel.textColor = .systemRed
    }
}
