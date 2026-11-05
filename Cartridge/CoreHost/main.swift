import Foundation

cartridge_set_log_sink { level, message in
    CoreHostLog.recordCoreLine(level: level, message: message)
}

let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
