import SwiftUI

/// OS identity mark using each system's recognizable logo: bundled
/// simple-icons SVGs (CC0) for Linux distributions, SF Symbols' Apple logo
/// for macOS, and a drawn four-pane logo for Windows.
struct OSBadge: View {
  let osID: String
  var showName = false
  var size: CGFloat = 14

  var body: some View {
    if let descriptor {
      HStack(spacing: 4) {
        logo(descriptor)
        if showName {
          Text(descriptor.name).font(AsterTypography.caption)
            .foregroundStyle(descriptor.tint)
        }
      }
      .help(descriptor.name)
      .accessibilityLabel(descriptor.name)
    }
  }

  @ViewBuilder private func logo(_ descriptor: Descriptor) -> some View {
    switch descriptor.mark {
    case .asset(let assetName):
      Image(assetName)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundStyle(descriptor.tint)
    case .appleLogo:
      Image(systemName: "apple.logo")
        .font(.system(size: size - 1))
        .foregroundStyle(descriptor.tint)
    case .windowsLogo:
      WindowsLogo()
        .fill(descriptor.tint)
        .frame(width: size, height: size)
    }
  }

  private enum Mark {
    case asset(String)
    case appleLogo
    case windowsLogo
  }

  private struct Descriptor {
    let name: String
    let mark: Mark
    let tint: Color
  }

  private var descriptor: Descriptor? {
    switch osID.lowercased() {
    case "":
      nil
    case "darwin", "macos":
      Descriptor(name: "macOS", mark: .appleLogo, tint: .primary.opacity(0.75))
    case "windows":
      Descriptor(
        name: "Windows", mark: .windowsLogo, tint: Color(red: 0, green: 0.47, blue: 0.83))
    case "ubuntu":
      Descriptor(
        name: "Ubuntu", mark: .asset("os-ubuntu"), tint: Color(red: 0.91, green: 0.33, blue: 0.13))
    case "debian":
      Descriptor(
        name: "Debian", mark: .asset("os-debian"), tint: Color(red: 0.66, green: 0.11, blue: 0.2))
    case "centos":
      Descriptor(
        name: "CentOS", mark: .asset("os-centos"), tint: Color(red: 0.57, green: 0.16, blue: 0.54))
    case "fedora":
      Descriptor(
        name: "Fedora", mark: .asset("os-fedora"), tint: Color(red: 0.23, green: 0.32, blue: 0.6))
    case "alpine":
      Descriptor(
        name: "Alpine", mark: .asset("os-alpinelinux"),
        tint: Color(red: 0.05, green: 0.35, blue: 0.5))
    case "arch", "archlinux":
      Descriptor(
        name: "Arch", mark: .asset("os-archlinux"), tint: Color(red: 0.09, green: 0.57, blue: 0.82))
    case "rocky":
      Descriptor(
        name: "Rocky", mark: .asset("os-rockylinux"),
        tint: Color(red: 0.06, green: 0.71, blue: 0.51))
    case "almalinux":
      Descriptor(
        name: "Alma", mark: .asset("os-almalinux"), tint: Color(red: 0.04, green: 0.41, blue: 0.72))
    case let other:
      Descriptor(
        name: other.prefix(1).uppercased() + other.dropFirst(), mark: .asset("os-linux"),
        tint: Color(red: 0.2, green: 0.2, blue: 0.2))
    }
  }
}

/// The modern Windows logo: four panes with a thin gutter.
private struct WindowsLogo: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let gutter = rect.width * 0.08
    let pane = (rect.width - gutter) / 2
    for row in 0..<2 {
      for column in 0..<2 {
        path.addRect(
          CGRect(
            x: rect.minX + CGFloat(column) * (pane + gutter),
            y: rect.minY + CGFloat(row) * (pane + gutter),
            width: pane, height: pane))
      }
    }
    return path
  }
}

#Preview {
  HStack(spacing: 12) {
    ForEach(["ubuntu", "debian", "darwin", "windows", "alpine", "arch", "gentoo"], id: \.self) {
      OSBadge(osID: $0, showName: true)
    }
  }
  .padding()
  .background(AsterColor.background1)
}
