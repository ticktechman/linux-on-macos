import Foundation
import Virtualization

let MB: UInt64 = 1024 * 1024

struct LinuxVirtualMachineProfile: Codable {
  var cpus: Int = 2
  var memory: UInt64 = 2048  // in MB
  var kernel: String = "vmlinuz"
  var initrd: String = "initrd.img"
  var storage: [String] = ["root.img"]
  var cmdline: String = "console=hvc0 root=/dev/vda rw"
  var network: Bool = false
  var uefi: Bool = false
  var shared: [String] = []
}

func logi(_ message: String) {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  let now = formatter.string(from: Date())
  print("[I|\(now)] \(message)")
}

func loge(_ message: String) {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  let now = formatter.string(from: Date())
  print("[E|\(now)] \(message)")
}

// Virtual Machine Delegate
class Delegate: NSObject {}
extension Delegate: VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    logi("The guest shut down. Exiting.")
    exit(EXIT_SUCCESS)
  }
}

func load_profile(conf_name: String) -> LinuxVirtualMachineProfile? {
  do {
    let url = URL(filePath: conf_name)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    let profile = try decoder.decode(LinuxVirtualMachineProfile.self, from: data)
    let setCurrentPath = FileManager.default.changeCurrentDirectoryPath
    _ = setCurrentPath(url.deletingLastPathComponent().path())

    return profile
  }
  catch {
    loge("fail to decode: \(error)")
    return nil
  }
}

// Creates a Linux bootloader with the given kernel and initial ramdisk.
func createBootLoader(conf: LinuxVirtualMachineProfile) -> VZBootLoader {
  if conf.uefi {
    let bootloader = VZEFIBootLoader()
    bootloader.variableStore = try! VZEFIVariableStore(
      creatingVariableStoreAt: URL(filePath: "efistore"),
      options: [.allowOverwrite]
    )
    return bootloader
  }
  else {
    let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: conf.kernel))
    if conf.initrd != "" {
      bootLoader.initialRamdiskURL = URL(fileURLWithPath: conf.initrd)
    }
    bootLoader.commandLine = conf.cmdline
    return bootLoader
  }
}

// serial port console for IO
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

func createVirtualMachineConf(conf: LinuxVirtualMachineProfile) -> VZVirtualMachineConfiguration {
  let configuration = VZVirtualMachineConfiguration()
  configuration.cpuCount = conf.cpus
  configuration.memorySize = conf.memory * MB
  configuration.serialPorts = [createConsoleConfiguration()]
  configuration.bootLoader = createBootLoader(conf: conf)
  do {
    for one in conf.storage {
      let url = URL(filePath: one)
      let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
      let device = VZVirtioBlockDeviceConfiguration(attachment: attachment)
      configuration.storageDevices.append(device)
    }

    // configure network
    if conf.network {
      let networkDevice = VZVirtioNetworkDeviceConfiguration()
      networkDevice.attachment = VZNATNetworkDeviceAttachment()
      configuration.networkDevices = [networkDevice]
    }

    // shared directories
    if conf.shared.count > 0 {
      var dirs = [String: VZSharedDirectory]()
      for one in conf.shared {
        dirs[one] = VZSharedDirectory(url: URL(fileURLWithPath: one), readOnly: false)
      }
      let sharedDirectory = VZMultipleDirectoryShare(directories: dirs)
      let sharedFileSystem = VZVirtioFileSystemDeviceConfiguration(tag: "shared")
      sharedFileSystem.share = sharedDirectory
      configuration.directorySharingDevices = [sharedFileSystem]
    }

    try configuration.validate()
  }
  catch {
    loge("configuration failed: \(error)")
    exit(EXIT_FAILURE)
  }
  return configuration
}

func main() {
  let arg = CommandLine.arguments
  if arg.count != 2 {
    print("usage: linux <xxx.json>")
    exit(EXIT_FAILURE)
  }

  guard let conf = load_profile(conf_name: arg[1]) else {
    loge("fail to load vm profile")
    exit(EXIT_FAILURE)
  }

  let configuration = createVirtualMachineConf(conf: conf)
  let vm = VZVirtualMachine(configuration: configuration)
  let delegate = Delegate()
  vm.delegate = delegate

  vm.start { (result) in
    if case let .failure(error) = result {
      loge("Failed to start the virtual machine. \(error)")
      exit(EXIT_FAILURE)
    }
  }

  RunLoop.main.run(until: Date.distantFuture)
}

//-----------------------------------
// main
//-----------------------------------
main()
