import Cocoa
import Virtualization

let MB: UInt64 = 1024 * 1024

struct LinuxVirtualMachineProfile: Codable {
  var cpus: Int
  var memory: UInt64
  var kernel: String
  var initrd: String
  var storage: [String]
  var cmdline: String
  var network: Bool
  var uefi: Bool
  var shared: [String]
}

// MARK: - 日志
func logi(_ message: String) {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  print("[I|\(formatter.string(from: Date()))] \(message)")
}

func loge(_ message: String) {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  print("[E|\(formatter.string(from: Date()))] \(message)")
}
func createGraphicsDeviceConfiguration() -> VZVirtioGraphicsDeviceConfiguration {
  let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
  graphicsDevice.scanouts = [
    VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 720)
  ]

  return graphicsDevice
}

// MARK: - Delegate
class Delegate: NSObject, VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    logi("虚拟机已退出")
    DispatchQueue.main.async {
      NSApp.terminate(nil)
    }
  }
}

// MARK: - 虚拟机配置加载
func load_profile(from url: URL) -> LinuxVirtualMachineProfile? {
  do {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(LinuxVirtualMachineProfile.self, from: data)
  }
  catch {
    loge("加载配置失败: \(error)")
    return nil
  }
}

// MARK: - 虚拟机配置生成
func createBootLoader(conf: LinuxVirtualMachineProfile) -> VZBootLoader {
  if conf.uefi {
    let bootloader = VZEFIBootLoader()
    do {
      bootloader.variableStore = try VZEFIVariableStore(
        creatingVariableStoreAt: URL(
          fileURLWithPath: "/Users/ticktech/usr/project/github/linux-on-macos/efistore"
        ),
        options: [.allowOverwrite]
      )
    }
    catch {
      fatalError("无法创建 EFI 存储: \(error)")
    }
    return bootloader
  }
  else {
    let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: conf.kernel))
    if conf.initrd != "" {
      boot.initialRamdiskURL = URL(fileURLWithPath: conf.initrd)
    }
    boot.commandLine = conf.cmdline
    return boot
  }
}

func createConsoleConfiguration() -> VZSerialPortConfiguration {
  let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()
  let inputFileHandle = FileHandle.standardInput
  let outputFileHandle = FileHandle.standardOutput
  var attributes = termios()
  tcgetattr(inputFileHandle.fileDescriptor, &attributes)
  attributes.c_iflag &= ~tcflag_t(ICRNL)
  attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
  tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

  let stdioAttachment = VZFileHandleSerialPortAttachment(
    fileHandleForReading: inputFileHandle,
    fileHandleForWriting: outputFileHandle
  )

  consoleConfiguration.attachment = stdioAttachment
  return consoleConfiguration
}
func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration {
  let consoleDevice = VZVirtioConsoleDeviceConfiguration()

  let spiceAgentPort = VZVirtioConsolePortConfiguration()
  spiceAgentPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
  spiceAgentPort.attachment = VZSpiceAgentPortAttachment()
  consoleDevice.ports[0] = spiceAgentPort

  return consoleDevice
}

func createVirtualMachineConf(conf: LinuxVirtualMachineProfile) -> VZVirtualMachineConfiguration {
  let configuration = VZVirtualMachineConfiguration()
  configuration.cpuCount = conf.cpus
  configuration.memorySize = conf.memory * MB
  configuration.bootLoader = createBootLoader(conf: conf)
  // configuration.serialPorts = [createConsoleConfiguration()]
  // configuration.consoleDevices = [createSpiceAgentConsoleDeviceConfiguration()]
  configuration.graphicsDevices = [createGraphicsDeviceConfiguration()]
  configuration.keyboards = [VZUSBKeyboardConfiguration()]
  configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

  do {
    for disk in conf.storage {
      let url = URL(fileURLWithPath: disk)
      let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
      let device = VZVirtioBlockDeviceConfiguration(attachment: attachment)
      configuration.storageDevices.append(device)
    }

    if conf.network {
      let networkDevice = VZVirtioNetworkDeviceConfiguration()
      networkDevice.attachment = VZNATNetworkDeviceAttachment()
      configuration.networkDevices = [networkDevice]
    }

    if !conf.shared.isEmpty {
      var dirs = [String: VZSharedDirectory]()
      for path in conf.shared {
        dirs[path] = VZSharedDirectory(url: URL(fileURLWithPath: path), readOnly: false)
      }
      let share = VZMultipleDirectoryShare(directories: dirs)
      let fs = VZVirtioFileSystemDeviceConfiguration(tag: "shared")
      fs.share = share
      configuration.directorySharingDevices = [fs]
    }

    try configuration.validate()
  }
  catch {
    fatalError("配置验证失败: \(error)")
  }

  return configuration
}

// MARK: - GUI 控制器
class VMViewController: NSViewController {

  let vmView = VZVirtualMachineView()
  let statusLabel = NSTextField(labelWithString: "等待启动虚拟机")
  let startButton = NSButton(title: "启动虚拟机", target: nil, action: nil)
  let chooseButton = NSButton(title: "选择配置文件", target: nil, action: nil)
  var delegateInstance: Delegate?

  var selectedConfigURL: URL?
  var virtualMachine: VZVirtualMachine?

  override func loadView() {
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    vmView.wantsLayer = true
    vmView.layer?.cornerRadius = 8
    vmView.layer?.masksToBounds = true
    vmView.layer?.borderWidth = 2
    vmView.layer?.borderColor = NSColor.darkGray.cgColor
    vmView.layer?.backgroundColor = NSColor.black.cgColor

    // 关闭 autoresizing 转换为约束
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    startButton.translatesAutoresizingMaskIntoConstraints = false
    chooseButton.translatesAutoresizingMaskIntoConstraints = false
    vmView.translatesAutoresizingMaskIntoConstraints = false

    // 添加视图
    view.addSubview(statusLabel)
    view.addSubview(startButton)
    view.addSubview(chooseButton)
    view.addSubview(vmView)

    // 配置按钮行为
    startButton.title = "启动虚拟机"
    startButton.target = self
    startButton.action = #selector(startVM)
    startButton.isEnabled = false

    chooseButton.title = "选择配置文件"
    chooseButton.target = self
    chooseButton.action = #selector(selectConfig)

    // 添加 Auto Layout 约束
    NSLayoutConstraint.activate([
      // 状态标签，左上角
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),

      // 启动按钮，右上角
      startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      startButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
      startButton.widthAnchor.constraint(equalToConstant: 150),
      startButton.heightAnchor.constraint(equalToConstant: 32),

      // 选择按钮，启动按钮左侧
      chooseButton.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -10),
      chooseButton.topAnchor.constraint(equalTo: startButton.topAnchor),
      chooseButton.widthAnchor.constraint(equalToConstant: 120),
      chooseButton.heightAnchor.constraint(equalToConstant: 32),

      // 虚拟机视图，填充主区域
      vmView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      vmView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      vmView.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 10),
      vmView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  @objc func selectConfig() {
    let dialog = NSOpenPanel()
    dialog.title = "选择配置文件"
    dialog.allowedContentTypes = [.json]
    dialog.allowsMultipleSelection = false

    if dialog.runModal() == .OK, let url = dialog.url {
      selectedConfigURL = url
      statusLabel.stringValue = "已选择配置文件：\(url.lastPathComponent)"
      startButton.isEnabled = true
      let path = url.deletingLastPathComponent().path()
      FileManager.default.changeCurrentDirectoryPath(path)
    }
  }

  @objc func startVM() {
    guard let url = selectedConfigURL,
      let profile = load_profile(from: url)
    else {
      statusLabel.stringValue = "配置加载失败"
      return
    }

    statusLabel.stringValue = "虚拟机启动中..."

    let config = createVirtualMachineConf(conf: profile)
    let vm = VZVirtualMachine(configuration: config)
    self.delegateInstance = Delegate()
    vm.delegate = self.delegateInstance
    vmView.virtualMachine = vm
    virtualMachine = vm

    vm.start { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          self.statusLabel.stringValue = "虚拟机已启动"
        case .failure(let error):
          self.statusLabel.stringValue = "启动失败: \(error)"
        }
      }
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_ notification: Notification) {
    // 设置主菜单（启用 Cmd + Q）
    setupMainMenu()

    // 创建窗口
    let windowSize = NSRect(x: 0, y: 0, width: 1280, height: 720)
    window = NSWindow(
      contentRect: windowSize,
      styleMask: [.titled, .resizable, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.minSize = NSSize(width: 800, height: 480)
    window.title = "Linux 虚拟机管理器"
    window.center()
    window.contentViewController = VMViewController()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App 菜单
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    let quitTitle = "退出 \(ProcessInfo.processInfo.processName)"
    let quitMenuItem = NSMenuItem(
      title: quitTitle,
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenu.addItem(quitMenuItem)
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    NSApp.mainMenu = mainMenu
  }
}

// 启动
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
