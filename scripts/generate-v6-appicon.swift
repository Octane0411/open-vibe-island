#!/usr/bin/env swift
// Renders the v6 Open Island app icon (paper tone · Bar + Dot) at every
// size required by Assets/Brand/AppIcon.appiconset and writes the PNG
// files in place.
//
// Usage: swift scripts/generate-v6-appicon.swift
//
// Spec (from design/v6-bundle, components/logos_v7.jsx -> AppIcon_BarDot):
// - Outer squircle: corner radius = size * 0.225
// - Paper tone: background #f1ead9, mark #0d0d0f
// - Inner mark: Logo_BarDot (160×64 viewBox) scaled to size * 0.72 wide
// - Inset 1px ring at rgba(0,0,0,0.06)
// - Drop shadow: 0 size*0.015 size*0.06 rgba(0,0,0,0.2)
//   (only rendered at the higher resolutions so it doesn't smudge 16px)

import AppKit
import CoreGraphics
import Foundation

struct IconSize {
    let filename: String
    let pixels: Int
}

let outputs: [IconSize] = [
    IconSize(filename: "icon_16x16.png",       pixels: 16),
    IconSize(filename: "icon_16x16@2x.png",    pixels: 32),
    IconSize(filename: "icon_32x32.png",       pixels: 32),
    IconSize(filename: "icon_32x32@2x.png",    pixels: 64),
    IconSize(filename: "icon_128x128.png",     pixels: 128),
    IconSize(filename: "icon_128x128@2x.png",  pixels: 256),
    IconSize(filename: "icon_256x256.png",     pixels: 256),
    IconSize(filename: "icon_256x256@2x.png",  pixels: 512),
    IconSize(filename: "icon_512x512.png",     pixels: 512),
    IconSize(filename: "icon_512x512@2x.png",  pixels: 1024),
]

let paper = CGColor(red: 0xf1/255.0, green: 0xea/255.0, blue: 0xd9/255.0, alpha: 1)
let ink   = CGColor(red: 0x0d/255.0, green: 0x0d/255.0, blue: 0x0f/255.0, alpha: 1)
let ring  = CGColor(red: 0, green: 0, blue: 0, alpha: 0.06)
let shadow = CGColor(red: 0, green: 0, blue: 0, alpha: 0.2)

func render(px: Int) -> Data {
    let size = CGFloat(px)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }

    // Clear.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Squircle path — standard rounded rect per design mocks (CSS
    // border-radius, not Apple continuous squircle).
    let radius = size * 0.225
    // Inset the icon so the drop shadow has room (on larger sizes).
    let shadowY = size * 0.015
    let shadowBlur = size * 0.06
    let inset: CGFloat = px >= 64 ? (shadowBlur / 2 + shadowY) : 0
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow (only when pixels can absorb the blur without smudging).
    if px >= 64 {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -shadowY), // CG y is up — invert
            blur: shadowBlur,
            color: shadow
        )
        ctx.setFillColor(paper)
        ctx.addPath(squircle)
        ctx.fillPath()
        ctx.restoreGState()
    } else {
        ctx.setFillColor(paper)
        ctx.addPath(squircle)
        ctx.fillPath()
    }

    // Inset 1px ring.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(ring)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()

    // Clip to squircle so the mark never bleeds past the corner.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Mark: Bar + Dot in a 160×64 viewBox, scaled to 72% of outer width,
    // centered in the squircle.
    let markW = rect.width * 0.72
    let markH = markW * 64.0 / 160.0
    let markX = rect.midX - markW / 2
    let markY = rect.midY - markH / 2

    // Outer notch shape (flat top, rounded bottom). In CG coordinates the
    // origin is bottom-left, so flip the math: bottom-left of the mark in
    // CG = (markX, size - markY - markH).
    let markYCG = size - markY - markH
    let markRect = CGRect(x: markX, y: markYCG, width: markW, height: markH)
    let markRadius = markH / 2

    let markPath = CGMutablePath()
    // Build flat-top + rounded-bottom pill from scratch.
    //   CG coords: bottom-left = (markRect.minX, markRect.minY)
    //              top-left    = (markRect.minX, markRect.maxY)
    markPath.move(to: CGPoint(x: markRect.minX, y: markRect.maxY))
    markPath.addLine(to: CGPoint(x: markRect.maxX, y: markRect.maxY))
    markPath.addLine(to: CGPoint(x: markRect.maxX, y: markRect.minY + markRadius))
    markPath.addArc(
        center: CGPoint(x: markRect.maxX - markRadius, y: markRect.minY + markRadius),
        radius: markRadius,
        startAngle: 0,
        endAngle: -.pi / 2,
        clockwise: true
    )
    markPath.addLine(to: CGPoint(x: markRect.minX + markRadius, y: markRect.minY))
    markPath.addArc(
        center: CGPoint(x: markRect.minX + markRadius, y: markRect.minY + markRadius),
        radius: markRadius,
        startAngle: -.pi / 2,
        endAngle: .pi,
        clockwise: true
    )
    markPath.closeSubpath()

    ctx.setFillColor(ink)
    ctx.addPath(markPath)
    ctx.fillPath()

    // Inner bar (70×7 in viewBox, centered vertically, x=30..100).
    let barW = markW * 70.0 / 160.0
    let barH = markH * 7.0 / 64.0
    let barX = markRect.minX + markW * 30.0 / 160.0
    let barY = markRect.minY + (markH - barH) / 2
    let bar = CGPath(
        roundedRect: CGRect(x: barX, y: barY, width: barW, height: barH),
        cornerWidth: barH / 2,
        cornerHeight: barH / 2,
        transform: nil
    )
    ctx.setFillColor(paper)
    ctx.addPath(bar)
    ctx.fillPath()

    // Trailing dot (r=5 at (118, 32) in viewBox).
    let dotR = markH * 5.0 / 64.0
    let dotCX = markRect.minX + markW * 118.0 / 160.0
    let dotCY = markRect.minY + markH / 2
    ctx.setFillColor(paper)
    ctx.fillEllipse(in: CGRect(x: dotCX - dotR, y: dotCY - dotR, width: dotR * 2, height: dotR * 2))

    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return data
}

// Discover the output directory relative to the script location.
let cwd = FileManager.default.currentDirectoryPath
let targetDir = URL(fileURLWithPath: cwd)
    .appendingPathComponent("Assets/Brand/AppIcon.appiconset")

guard FileManager.default.fileExists(atPath: targetDir.path) else {
    FileHandle.standardError.write("Missing target dir: \(targetDir.path)\n".data(using: .utf8)!)
    exit(1)
}

// Cache renders per unique pixel size so we don't re-render identical images.
var cache: [Int: Data] = [:]
for output in outputs {
    if cache[output.pixels] == nil {
        cache[output.pixels] = render(px: output.pixels)
    }
    let file = targetDir.appendingPathComponent(output.filename)
    try? cache[output.pixels]!.write(to: file)
    print("wrote \(output.filename) (\(output.pixels)×\(output.pixels))")
}
