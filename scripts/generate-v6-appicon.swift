#!/usr/bin/env swift
// Renders the canonical v6 Open Island app icon source bitmap.
//
// Produces a single 1024×1024 PNG at Assets/Brand/app-icon-v6.png. That
// image is the sole "master" — the Python pipeline
// (scripts/generate_brand_icons.py) resizes it into every
// AppIcon.appiconset slot and then composes OpenIsland.icns. Re-run this
// script after any design tweak, then run the Python pipeline.
//
// Spec (from design/v6-bundle, components/logos_v7.jsx -> AppIcon_BarDot):
// - Paper tone: background #f1ead9, mark #0d0d0f, foreground #f1ead9
// - Outer squircle: corner radius = size * 0.225 (full-bleed, no shadow
//   baked in — macOS supplies its own drop shadow)
// - Inner Bar+Dot mark (160×64 viewBox), scaled to 72% of outer width
// - 1px ink ring at rgba(0,0,0,0.06) for edge crispness

import AppKit
import CoreGraphics
import Foundation

let outputPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/Brand/app-icon-v6.png")

let paper = CGColor(red: 0xf1/255.0, green: 0xea/255.0, blue: 0xd9/255.0, alpha: 1)
let ink   = CGColor(red: 0x0d/255.0, green: 0x0d/255.0, blue: 0x0f/255.0, alpha: 1)
let ring  = CGColor(red: 0, green: 0, blue: 0, alpha: 0.06)

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

    // Transparent canvas.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Full-bleed squircle. The Python pipeline insets this to the macOS
    // icon content grid (824/1024), so no extra padding is baked in here.
    let radius = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.setFillColor(paper)
    ctx.addPath(squircle)
    ctx.fillPath()

    // 1px inset ring for edge definition at small sizes.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(ring)
    ctx.setLineWidth(size / 1024.0)
    ctx.strokePath()
    ctx.restoreGState()

    // Clip to squircle so the mark corners can't bleed.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Mark: Bar + Dot in a 160×64 viewBox, scaled to 72% of outer width,
    // centered. Flat-top + rounded-bottom pill (bottom radius = h/2).
    let markW = rect.width * 0.72
    let markH = markW * 64.0 / 160.0
    let markX = rect.midX - markW / 2
    let markYCG = rect.midY - markH / 2
    let markRect = CGRect(x: markX, y: markYCG, width: markW, height: markH)
    let markRadius = markH / 2

    let markPath = CGMutablePath()
    // CG origin is bottom-left: (markRect.minX, markRect.minY) is the
    // BOTTOM-left of the pill; we build flat-top + rounded-bottom.
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

    // Bar (70×7 in viewBox, centered vertically; 30..100 horizontally).
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

let data = render(px: 1024)
try? data.write(to: outputPath)
print("wrote \(outputPath.path) (1024×1024)")
