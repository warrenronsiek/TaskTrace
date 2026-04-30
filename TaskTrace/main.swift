import Foundation
import SwiftUI

if ProcessInfo.processInfo.arguments.contains(Vars.mcpStdioLaunchArgument) {
    TaskTraceMCPHelperLauncher.execIfTaskTraceIsRunning()
} else {
    TaskTraceApp.main()
}
