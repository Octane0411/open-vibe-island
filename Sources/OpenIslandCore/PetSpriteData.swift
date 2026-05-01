// Sources/OpenIslandCore/PetSpriteData.swift
import Foundation

public enum PetSpriteData {
    public static func frames(for pet: CompanionPet, state: CompanionState) -> [PixelPetGrid] {
        switch pet {
        case .cat:
            return CatSprites.frames(for: state)
        case .ghost:
            return GhostSprites.frames(for: state)
        case .robot:
            return RobotSprites.frames(for: state)
        }
    }
}

// MARK: - Cat

private enum CatSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:        return idleFrames
        case .working:     return workingFrames
        case .waiting:     return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        .XXXX.
        .X..X.
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        .XXXX.
        ..X.X.
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X..--X
        XXXXXX
        .XXXX.
        .X.XX.
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X-X-XX
        XXXXXX
        .XXXX.
        .XXX..
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XXX-XX
        XXXXXX
        .XXXX.
        ..XX.X
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X??X?X
        XXXXXX
        .XXXX.
        .X..X.
        """),
        PixelPetSprite.parseGrid("""
        ..X.X.
        .XXXXX
        .X??X?
        .XXXXX
        ..XXXX
        ..X..X
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XX..
        XXXXXX
        XOOOOO
        XXXXXX
        XXXXXX
        X.XX.X
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X*XX*X
        XXXXXX
        .XXXX.
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        ..XX..
        .XXXX.
        .X**X.
        .XXXX.
        ..XX..
        ..XX..
        """),
    ]
}

// MARK: - Ghost

private enum GhostSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:        return idleFrames
        case .working:     return workingFrames
        case .waiting:     return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOXXOXX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOXXOXX
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX-XX-XX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX--XXXX
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXXX--XX
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX??XX?X
        XXXXXXXX
        XXXXXXXX
        X.X.X.X.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        X??XX??X
        XXXXXXXX
        XXXXXXXX
        .X.X.X.X
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XX**XX**
        XXXXXXXX
        XXXXXXXX
        XX.XX.XX
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .X****X.
        X*XX*XXX
        X**XX**X
        XXXXXXXX
        X.XX.XX.
        """),
        PixelPetSprite.parseGrid("""
        ..XXXX..
        .XXXXXX.
        XXOOOOXX
        XXXXXXXX
        XXXXXXXX
        XX.XX.XX
        """),
    ]
}

// MARK: - Robot

private enum RobotSprites {
    static func frames(for state: CompanionState) -> [PixelPetGrid] {
        switch state {
        case .idle:        return idleFrames
        case .working:     return workingFrames
        case .waiting:     return waitingFrames
        case .celebrating: return celebratingFrames
        }
    }

    static let idleFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X.XX.X
        XXXXXX
        XX..XX
        """),
    ]

    static let workingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX*-XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX-*XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        XOXXOX
        XXXXXX
        XX**XX
        """),
    ]

    static let waitingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X?XX?X
        XXXXXX
        XX..XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X.XX.X
        XXXXXX
        XX..XX
        """),
    ]

    static let celebratingFrames: [PixelPetGrid] = [
        PixelPetSprite.parseGrid("""
        XX..XX
        XXXXXX
        X*XX*X
        XXXXXX
        XX**XX
        """),
        PixelPetSprite.parseGrid("""
        .X..X.
        XXXXXX
        X**X**
        XXXXXX
        X*..*X
        """),
        PixelPetSprite.parseGrid("""
        XX..XX
        .XXXX.
        XO**OX
        .XXXX.
        XX..XX
        """),
    ]
}
