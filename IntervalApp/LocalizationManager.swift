import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case french = "fr"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        }
    }
    
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if code.hasPrefix("de") { return .german }
        if code.hasPrefix("fr") { return .french }
        return .english
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @AppStorage("appLanguage") var currentLanguage: AppLanguage = .systemDefault {
        didSet {
            objectWillChange.send()
        }
    }
    
    func string(for key: String) -> String {
        guard let dict = strings[key] else { return key }
        return dict[currentLanguage] ?? dict[.english] ?? key
    }
    
    private let strings: [String: [AppLanguage: String]] = [
        // Categories Upper
        "1 HOUR": [.english: "1 HOUR", .german: "1 STUNDE", .french: "1 HEURE"],
        "1 DAY": [.english: "1 DAY", .german: "1 TAG", .french: "1 JOUR"],
        "1 WEEK": [.english: "1 WEEK", .german: "1 WOCHE", .french: "1 SEMAINE"],
        "1 MONTH": [.english: "1 MONTH", .german: "1 MONAT", .french: "1 MOIS"],
        "1 YEAR": [.english: "1 YEAR", .german: "1 JAHR", .french: "1 AN"],
        
        // Interval Titles (for dropdown menus)
        "1 Hour": [.english: "1 Hour", .german: "1 Stunde", .french: "1 Heure"],
        "1 Day": [.english: "1 Day", .german: "1 Tag", .french: "1 Jour"],
        "1 Week": [.english: "1 Week", .german: "1 Woche", .french: "1 Semaine"],
        "1 Month": [.english: "1 Month", .german: "1 Monat", .french: "1 Mois"],
        "1 Year": [.english: "1 Year", .german: "1 Jahr", .french: "1 An"],
        
        // UI Action Labels
        "Add task...": [.english: "Add task...", .german: "Aufgabe hinzufügen...", .french: "Ajouter une tâche..."],
        "New List": [.english: "New List", .german: "Neue Liste", .french: "Nouvelle liste"],
        "List name...": [.english: "List name...", .german: "Listenname...", .french: "Nom de la liste..."],
        "No custom lists created yet.": [.english: "No custom lists created yet.", .german: "Noch keine Listen erstellt.", .french: "Aucune liste créée."],
        "Create First List": [.english: "Create First List", .german: "Erste Liste erstellen", .french: "Créer la première liste"],
        "Item...": [.english: "Item...", .german: "Eintrag...", .french: "Élément..."],
        "Add Item": [.english: "Add Item", .german: "Eintrag hinzufügen", .french: "Ajouter un élément"],
        "COMPLETED": [.english: "COMPLETED", .german: "ERLEDIGT", .french: "TERMINÉ"],
        "Clear All": [.english: "Clear All", .german: "Alle löschen", .french: "Tout effacer"],
        "TRANSFER TO TASK": [.english: "TRANSFER TO TASK", .german: "IN AUFGABE UMWANDELN", .french: "TRANSFÉRER EN TÂCHE"],
        
        // Tooltips & Dialogs
        "SETTINGS": [.english: "SETTINGS", .german: "EINSTELLUNGEN", .french: "PARAMÈTRES"],
        "LANGUAGE": [.english: "LANGUAGE", .german: "SPRACHE", .french: "LANGUE"],
        "Settings": [.english: "Settings", .german: "Einstellungen", .french: "Paramètres"],
        "Language": [.english: "Language", .german: "Sprache", .french: "Langue"],
        "Switch to Scratchpad Lists": [.english: "Switch to Scratchpad Lists", .german: "Zu Notizlisten wechseln", .french: "Passer aux listes de notes"],
        "Switch to Interval Tasks": [.english: "Switch to Interval Tasks", .german: "Zu Intervall-Aufgaben wechseln", .french: "Passer aux tâches d'intervalle"],
        "Manual Sync (⌘R)": [.english: "Manual Sync (⌘R)", .german: "Manuelle Synchronisation (⌘R)", .french: "Synchronisation manuelle (⌘R)"],
        "Delete List?": [.english: "Delete List?", .german: "Liste löschen?", .french: "Supprimer la liste ?"],
        "Delete": [.english: "Delete", .german: "Löschen", .french: "Supprimer"],
        "Cancel": [.english: "Cancel", .german: "Abbrechen", .french: "Annuler"],
        "Delete list message": [
            .english: "Are you sure you want to delete this list and all its items?",
            .german: "Möchtest du diese Liste und alle ihre Einträge wirklich löschen?",
            .french: "Voulez-vous vraiment supprimer cette liste et tous ses éléments ?"
        ],
        "Untitled List": [.english: "Untitled List", .german: "Unbenannte Liste", .french: "Liste sans titre"],
        "SUPPORT & FEEDBACK": [.english: "SUPPORT & FEEDBACK", .german: "SUPPORT & FEEDBACK", .french: "SUPPORT ET RETOURS"],
        "For feedback, inspiration or help contact:": [
            .english: "For feedback, inspiration or help contact:",
            .german: "Für Feedback, Inspiration oder Hilfe wende dich an:",
            .french: "Pour des retours, de l'inspiration ou de l'aide :"
        ],
        "Donations & Support:": [
            .english: "Donations & Support:",
            .german: "Spenden & Unterstützung:",
            .french: "Dons et soutien :"
        ],
        "HABITS": [.english: "HABITS", .german: "GEWOHNHEITEN", .french: "HABITUDES"],
        "New habit...": [.english: "New habit...", .german: "Neue Gewohnheit...", .french: "Nouvelle habitude..."]
    ]
}

extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}
