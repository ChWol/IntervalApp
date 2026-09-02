import Foundation
import AVFoundation

public enum SoundEffect: String, CaseIterable {
    // 1. Task Completion (Clean graphite, tactile wood, crystal ding, kalimba, sub tick)
    case completePencilSingle = "complete_pencil_single"
    case completeClickWood = "complete_click_wood"
    case completeDingGlass = "complete_ding_glass"
    case completeKalimbaPop = "complete_kalimba_pop"
    case completeSubThud = "complete_sub_thud"
    case completePencilDouble = "complete_pencil_double"
    case completePencilSoft = "complete_pencil_soft"
    
    // 2. Task Deletion (Silky paper sweep, velvet poof, leaf flick, sub dissolve, crumple)
    case deletePaperSweep = "delete_paper_sweep"
    case deleteVelvetPoof = "delete_velvet_poof"
    case deleteLeafFlick = "delete_leaf_flick"
    case deleteDropSub = "delete_drop_sub"
    case deletePaperCrumple = "delete_paper_crumple"
    case deleteTrashDrop = "delete_trash_drop"
    
    // 3. Milestone & Interval Transitions (Zen Chimes)
    case chimeZenBowl = "chime_zen_bowl"
    case chimeKalimba = "chime_kalimba"
    case chimeCrystal = "chime_crystal"
    
    // 4. Drag & Drop
    case dropWoodThock = "drop_wood_thock"
    case dropCreamySwitch = "drop_creamy_switch"
    case dropMagneticSnap = "drop_magnetic_snap"
    
    // 5. Transfer to Main / Scratchpad
    case transferVelvetGlide = "transfer_velvet_glide"
    case transferWoodChime = "transfer_wood_chime"
    case transferMagneticSlide = "transfer_magnetic_slide"
    case transferAirSwell = "transfer_air_swell"
    case transferPaperGlide = "transfer_paper_glide"
    
    // 6. Habit Check
    case habitCheckWood = "habit_check_wood"
    case habitCheckDroplet = "habit_check_droplet"
    case habitCheckBell = "habit_check_bell"
    
    // 7. Undo / Restore from Bin
    case undoReverseWhoosh = "undo_reverse_whoosh"
    case undoReboundPop = "undo_rebound_pop"
    case undoPaperUnfold = "undo_paper_unfold"
    case undoElasticThud = "undo_elastic_thud"
    case undoUnfurl = "undo_unfurl"
}

// MARK: - Sound Option Enums for Customization

public enum SoundCompleteOption: String, CaseIterable, Identifiable {
    case pencilSingle = "complete_pencil_single"
    case clickWood = "complete_click_wood"
    case dingGlass = "complete_ding_glass"
    case kalimbaPop = "complete_kalimba_pop"
    case subThud = "complete_sub_thud"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .pencilSingle: return "Pencil Stroke".localized
        case .clickWood: return "Wood Switch".localized
        case .dingGlass: return "Crystal Ding".localized
        case .kalimbaPop: return "Kalimba Pluck".localized
        case .subThud: return "Deep Sub Tick".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .completePencilSingle
    }
}

public enum SoundDeleteOption: String, CaseIterable, Identifiable {
    case paperSweep = "delete_paper_sweep"
    case velvetPoof = "delete_velvet_poof"
    case leafFlick = "delete_leaf_flick"
    case dropSub = "delete_drop_sub"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .paperSweep: return "Paper Sweep".localized
        case .velvetPoof: return "Velvet Poof".localized
        case .leafFlick: return "Parchment Flick".localized
        case .dropSub: return "Sub Dissolve".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .deletePaperSweep
    }
}

public enum SoundTransferOption: String, CaseIterable, Identifiable {
    case velvetGlide = "transfer_velvet_glide"
    case woodChime = "transfer_wood_chime"
    case magneticSlide = "transfer_magnetic_slide"
    case airSwell = "transfer_air_swell"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .velvetGlide: return "Velvet Glide".localized
        case .woodChime: return "Marimba Duo".localized
        case .magneticSlide: return "Magnetic Dock".localized
        case .airSwell: return "Air Swell".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .transferVelvetGlide
    }
}

public enum SoundRestoreOption: String, CaseIterable, Identifiable {
    case reverseWhoosh = "undo_reverse_whoosh"
    case reboundPop = "undo_rebound_pop"
    case paperUnfold = "undo_paper_unfold"
    case elasticThud = "undo_elastic_thud"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .reverseWhoosh: return "Reverse Whoosh".localized
        case .reboundPop: return "Rebound Pop".localized
        case .paperUnfold: return "Paper Unfold".localized
        case .elasticThud: return "Elastic Snap".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .undoReverseWhoosh
    }
}

public enum SoundTransitionOption: String, CaseIterable, Identifiable {
    case zenBowl = "chime_zen_bowl"
    case kalimba = "chime_kalimba"
    case crystal = "chime_crystal"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .zenBowl: return "Singing Bowl".localized
        case .kalimba: return "Kalimba Echo".localized
        case .crystal: return "Crystal Chime".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .chimeZenBowl
    }
}

public enum SoundHabitOption: String, CaseIterable, Identifiable {
    case wood = "habit_check_wood"
    case droplet = "habit_check_droplet"
    case bell = "habit_check_bell"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .wood: return "Bamboo Tap".localized
        case .droplet: return "Water Droplet".localized
        case .bell: return "Harmonic Bell".localized
        }
    }
    
    public var effect: SoundEffect {
        SoundEffect(rawValue: rawValue) ?? .habitCheckWood
    }
}

// MARK: - Main Audio Player & Manager

@MainActor
public final class SoundManager {
    public static let shared = SoundManager()
    
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    
    private init() {
        configureAudioSession()
        preloadSounds()
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[SoundManager] Audio session setup error: \(error)")
        }
        #endif
    }
    
    public func preloadSounds() {
        configureAudioSession()
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
        let name = effect.rawValue
        
        // 1. Check direct bundle
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return url
        }
        // 2. Check subdirectories
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Resources/Sounds") {
            return url
        }
        // 3. Fallback filesystem path in resource bundle
        if let resURL = Bundle.main.resourceURL {
            let p1 = resURL.appendingPathComponent("Sounds/\(name).wav")
            if FileManager.default.fileExists(atPath: p1.path) { return p1 }
            let p2 = resURL.appendingPathComponent("Resources/Sounds/\(name).wav")
            if FileManager.default.fileExists(atPath: p2.path) { return p2 }
            let p3 = resURL.appendingPathComponent("\(name).wav")
            if FileManager.default.fileExists(atPath: p3.path) { return p3 }
        }
        return nil
    }
    
    public func play(_ effect: SoundEffect, volume: Float = 1.0, ignoreMute: Bool = false) {
        if !ignoreMute {
            let isEnabled: Bool
            if UserDefaults.standard.object(forKey: "soundEffectsEnabled") != nil {
                isEnabled = UserDefaults.standard.bool(forKey: "soundEffectsEnabled")
            } else {
                isEnabled = true
            }
            guard isEnabled else { return }
        }
        
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
        SoundManager.shared.play(.completePencilSingle, volume: 0.95)
    }
    
    public static func playTaskDeleted() {
        SoundManager.shared.play(.deleteVelvetPoof, volume: 0.9)
    }
    
    public static func playTransitionChime() {
        SoundManager.shared.play(.chimeZenBowl, volume: 0.85)
    }
    
    public static func playTaskDropped() {
        SoundManager.shared.play(.dropWoodThock, volume: 0.9)
    }
    
    public static func playTransfer() {
        SoundManager.shared.play(.transferVelvetGlide, volume: 0.85)
    }
    
    public static func playHabitCompleted() {
        SoundManager.shared.play(.habitCheckWood, volume: 0.9)
    }
    
    public static func playUndo() {
        SoundManager.shared.play(.undoReverseWhoosh, volume: 0.85)
    }
}
