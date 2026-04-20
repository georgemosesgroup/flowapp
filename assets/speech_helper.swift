#!/usr/bin/swift
import Speech
import AVFoundation
import Foundation

let semaphore = DispatchSemaphore(value: 0)
var audioEngine = AVAudioEngine()

guard CommandLine.arguments.count > 1 else {
    print("Usage: speech_helper.swift <localeId>")
    exit(1)
}

let localeId = CommandLine.arguments[1]
let locale = Locale(identifier: localeId)

guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
    fputs("ERROR:Speech recognizer not available\n", stderr)
    exit(1)
}

let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true

let inputNode = audioEngine.inputNode
let recordingFormat = inputNode.outputFormat(forBus: 0)

inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
    request.append(buffer)
}

audioEngine.prepare()
do {
    try audioEngine.start()
} catch {
    fputs("ERROR:Audio engine failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Listen for SIGTERM to stop gracefully
signal(SIGTERM) { _ in
    request.endAudio()
}

// Also listen on stdin for "STOP" command
DispatchQueue.global().async {
    while let line = readLine() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines) == "STOP" {
            request.endAudio()
            break
        }
    }
}

let task = recognizer.recognitionTask(with: request) { result, error in
    if let result = result {
        let text = result.bestTranscription.formattedString
        let isFinal = result.isFinal
        // Output as JSON lines
        print("{\"text\":\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\",\"isFinal\":\(isFinal)}")
        fflush(stdout)

        if isFinal {
            semaphore.signal()
        }
    }

    if let error = error {
        fputs("ERROR:\(error.localizedDescription)\n", stderr)
        semaphore.signal()
    }
}

semaphore.wait()
audioEngine.stop()
inputNode.removeTap(onBus: 0)
