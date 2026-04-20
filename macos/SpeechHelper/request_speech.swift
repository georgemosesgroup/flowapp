import Speech
import Foundation

let semaphore = DispatchSemaphore(value: 0)

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "request"

switch command {
case "check":
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: print("granted")
    case .denied: print("denied")
    case .restricted: print("denied")
    case .notDetermined: print("notDetermined")
    @unknown default: print("notDetermined")
    }
case "request":
    SFSpeechRecognizer.requestAuthorization { status in
        switch status {
        case .authorized: print("granted")
        case .denied: print("denied")
        case .restricted: print("denied")
        case .notDetermined: print("notDetermined")
        @unknown default: print("notDetermined")
        }
        semaphore.signal()
    }
    semaphore.wait()
default:
    print("Usage: request_speech [check|request]")
}
