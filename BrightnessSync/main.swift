import Cocoa
import Carbon.HIToolbox

// Create the application instance
let app = NSApplication.shared

// Create and set the delegate
let delegate = AppDelegate()
app.delegate = delegate

// Activate the app (important for menu bar apps)
app.setActivationPolicy(.accessory)

// Run the app
app.run()
