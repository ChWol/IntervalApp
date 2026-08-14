import Foundation
import AVFoundation

public enum SoundEffect: String, CaseIterable {
    // 1. Task Completion (Pencil Strikethrough variations)
    case completePencilSingle = "complete_pencil_single"
    case completePencilDouble = "complete_pencil_double"
    case completePencilSoft = "complete_pencil_soft"
    
    // 2. Task Deletion (Paper Crumple / Trash variations)
    case deletePaperCrumple = "delete_paper_crumple"
    case deleteTrashDrop = "delete_trash_drop"
    
    // 3. Milestone & Interval Transitions (Zen Chimes)
    case chimeZenBowl = "chime_zen_bowl"
    case chimeKalimba = "chime_kalimba"
    case chimeCrystal = "chime_crystal"
    
    // 4. Drag & Drop (Tactile Thocks)
    case dropWoodThock = "drop_wood_thock"
    case dropCreamySwitch = "drop_creamy_switch"
    case dropMagneticSnap = "drop_magnetic_snap"
    
    // 5. Transfer to Main / Scratchpad
    case transferPaperGlide = "transfer_paper_glide"
    
    // 6. Habit Check
    case habitCheckWood = "habit_check_wood"
    case habitCheckDroplet = "habit_check_droplet"
    
    // 7. Undo / Restore from Bin
    case undoUnfurl = "undo_unfurl"
}

@MainActor
public final class SoundManager {
    public static let shared = SoundManager()
    
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    
    private init() {
        preloadSounds()
    }
    
    public func preloadSounds() {
        for effect in SoundEffect.allCases {
            if let url = urlForSound(effect) {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    players[effect] = player
                }
            }
        }
    }
    
    private func urlForSound(_ effect: SoundEffect) -> URL? {
        // Try inside Resources/Sounds folder or top-level bundle
        if let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Resources/Sounds") {
            return url
        }
        if let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Sounds") {
            return url
        }
        return Bundle.main.url(forResource: effect.rawValue, withExtension: "wav")
    }
    
    public func play(_ effect: SoundEffect, volume: Float = 1.0) {
        // Default to enabled (true) if key not set
        let isEnabled: Bool
        if UserDefaults.standard.object(forKey: "soundEffectsEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "soundEffectsEnabled")
        } else {
            isEnabled = true
        }
        guard isEnabled else { return }
        
        if let player = players[effect] {
            player.volume = volume
            if player.isPlaying {
                player.currentTime = 0
            }
            player.play()
        } else if let url = urlForSound(effect), let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = volume
            player.prepareToPlay()
            players[effect] = player
            player.play()
        }
    }
    
    // MARK: - Semantic Action Triggers
    
    public static func playTaskCompleted() {
        SoundManager.shared.play(.completePencilSingle)
    }
    
    public static func playTaskDeleted() {
        SoundManager.shared.play(.deletePaperCrumple)
    }
    
    public static func playTransitionChime() {
        SoundManager.shared.play(.chimeZenBowl, volume: 0.85)
    }
    
    public static func playTaskDropped() {
        SoundManager.shared.play(.dropWoodThock, volume: 0.9)
    }
    
    public static func playTransfer() {
        SoundManager.shared.play(.transferPaperGlide, volume: 0.85)
    }
    
    public static func playHabitCompleted() {
        SoundManager.shared.play(.habitCheckWood, volume: 0.9)
    }
    
    public static func playUndo() {
        SoundManager.shared.play(.undoUnfurl, volume: 0.85)
    }
}
