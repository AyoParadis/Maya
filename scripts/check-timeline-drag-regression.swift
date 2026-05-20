#!/usr/bin/env swift

import Foundation

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = repositoryRoot.appendingPathComponent("Maya/Views/Timeline/AnimationsTrack.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let lines = source.components(separatedBy: .newlines)

struct ClosureBody {
    let startLine: Int
    let text: String
}

func closureBody(startingAt startIndex: Int) -> ClosureBody? {
    var depth = 0
    var started = false
    var bodyLines: [String] = []

    for index in startIndex..<lines.count {
        let line = lines[index]
        if started {
            bodyLines.append(line)
        }
        for scalar in line.unicodeScalars {
            if scalar == "{" {
                depth += 1
                started = true
            } else if scalar == "}" {
                depth -= 1
                if started, depth == 0 {
                    return ClosureBody(startLine: startIndex + 1, text: bodyLines.joined(separator: "\n"))
                }
            }
        }
    }

    return nil
}

let liveDragClosures = lines.enumerated().compactMap { index, line -> ClosureBody? in
    line.contains(".onChanged") ? closureBody(startingAt: index) : nil
}

if liveDragClosures.isEmpty {
    fputs("No live drag .onChanged handlers found in AnimationsTrack.swift\n", stderr)
    exit(1)
}

let gridSnappingClosures = liveDragClosures.filter { $0.text.contains("AnimationsTrack.snap(") }
if !gridSnappingClosures.isEmpty {
    let locations = gridSnappingClosures.map { "\($0.startLine)" }.joined(separator: ", ")
    fputs(
        "Timeline drag regression: live .onChanged handlers must not use grid snapping. " +
            "Use snapToPlayhead while dragging and snap to grid only in .onEnded. Lines: \(locations)\n",
        stderr
    )
    exit(1)
}

let projectCommittingClosures = liveDragClosures.filter { $0.text.contains("onChange(") }
if !projectCommittingClosures.isEmpty {
    let locations = projectCommittingClosures.map { "\($0.startLine)" }.joined(separator: ", ")
    fputs(
        "Timeline drag regression: live .onChanged handlers must render local previews, " +
            "not commit Project.animations updates. Lines: \(locations)\n",
        stderr
    )
    exit(1)
}

let projectResolvingClosures = liveDragClosures.filter { $0.text.contains("resolveChange(") }
if !projectResolvingClosures.isEmpty {
    let locations = projectResolvingClosures.map { "\($0.startLine)" }.joined(separator: ", ")
    fputs(
        "Timeline drag regression: live .onChanged handlers must not resolve model placement. " +
            "Clamp locally while dragging and resolve only on release. Lines: \(locations)\n",
        stderr
    )
    exit(1)
}

let usesRenderOffsetForDrag = source.contains(".offset(x: startX, y: 6)")
if !usesRenderOffsetForDrag {
    fputs(
        "Timeline drag regression: segment movement should use render offset, not center-position layout.\n",
        stderr
    )
    exit(1)
}

let preservesContinuousResize =
    source.contains("resize(.leading, translation: translation, snapToGrid: false)") &&
    source.contains("resize(.trailing, translation: translation, snapToGrid: false)") &&
    source.contains("resize(.leading, translation: translation, snapToGrid: true)") &&
    source.contains("resize(.trailing, translation: translation, snapToGrid: true)")

if !source.contains("snapToPlayhead") || !preservesContinuousResize {
    fputs(
        "Timeline drag regression: expected live handlers to preserve playhead-only snapping and release-only grid snapping.\n",
        stderr
    )
    exit(1)
}

print("Timeline drag snapping regression check passed.")
