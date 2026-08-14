import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case arabic = "ar"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .arabic: return "العربية"
        }
    }
    
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if code.hasPrefix("de") { return .german }
        if code.hasPrefix("fr") { return .french }
        if code.hasPrefix("ar") { return .arabic }
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
        "1 HOUR": [.english: "1 HOUR", .german: "1 STUNDE", .french: "1 HEURE", .arabic: "ساعة واحدة"],
        "1 DAY": [.english: "1 DAY", .german: "1 TAG", .french: "1 JOUR", .arabic: "يوم واحد"],
        "1 WEEK": [.english: "1 WEEK", .german: "1 WOCHE", .french: "1 SEMAINE", .arabic: "أسبوع واحد"],
        "1 MONTH": [.english: "1 MONTH", .german: "1 MONAT", .french: "1 MOIS", .arabic: "شهر واحد"],
        "1 YEAR": [.english: "1 YEAR", .german: "1 JAHR", .french: "1 AN", .arabic: "سنة واحدة"],
        
        // Interval Titles (for dropdown menus)
        "1 Hour": [.english: "1 Hour", .german: "1 Stunde", .french: "1 Heure", .arabic: "ساعة واحدة"],
        "1 Day": [.english: "1 Day", .german: "1 Tag", .french: "1 Jour", .arabic: "يوم واحد"],
        "1 Week": [.english: "1 Week", .german: "1 Woche", .french: "1 Semaine", .arabic: "أسبوع واحد"],
        "1 Month": [.english: "1 Month", .german: "1 Monat", .french: "1 Mois", .arabic: "شهر واحد"],
        "1 Year": [.english: "1 Year", .german: "1 Jahr", .french: "1 An", .arabic: "سنة واحدة"],
        
        // UI Action Labels
        "Add task...": [.english: "Add task...", .german: "Aufgabe hinzufügen...", .french: "Ajouter une tâche...", .arabic: "إضافة مهمة..."],
        "New List": [.english: "New List", .german: "Neue Liste", .french: "Nouvelle liste", .arabic: "قائمة جديدة"],
        "List name...": [.english: "List name...", .german: "Listenname...", .french: "Nom de la liste...", .arabic: "اسم القائمة..."],
        "No custom lists created yet.": [
            .english: "No custom lists created yet.",
            .german: "Noch keine Listen erstellt.",
            .french: "Aucune liste créée.",
            .arabic: "لم يتم إنشاء قوائم بعد."
        ],
        "Create First List": [.english: "Create First List", .german: "Erste Liste erstellen", .french: "Créer la première liste", .arabic: "إنشاء القائمة الأولى"],
        "Item...": [.english: "Item...", .german: "Eintrag...", .french: "Élément...", .arabic: "عنصر..."],
        "Add Item": [.english: "Add Item", .german: "Eintrag hinzufügen", .french: "Ajouter un élément", .arabic: "إضافة عنصر"],
        "ITEMS": [.english: "ITEMS", .german: "EINTRÄGE", .french: "ÉLÉMENTS", .arabic: "العناصر"],
        "COMPLETED": [.english: "COMPLETED", .german: "ERLEDIGT", .french: "TERMINÉ", .arabic: "المكتملة"],
        "Completed": [.english: "Completed", .german: "Erledigt", .french: "Terminé", .arabic: "المكتملة"],
        "RECENTLY DELETED": [.english: "RECENTLY DELETED", .german: "KÜRZLICH GELÖSCHT", .french: "RÉCEMMENT SUPPRIMÉ", .arabic: "المحذوفة مؤخراً"],
        "Recently Deleted": [.english: "Recently Deleted", .german: "Kürzlich gelöscht", .french: "Récemment supprimé", .arabic: "المحذوفة مؤخراً"],
        "Clear All": [.english: "Clear All", .german: "Alle löschen", .french: "Tout effacer", .arabic: "مسح الكل"],
        "Clear all": [.english: "Clear all", .german: "Alle löschen", .french: "Tout effacer", .arabic: "مسح الكل"],
        "Show Less": [.english: "Show Less", .german: "Weniger anzeigen", .french: "Afficher moins", .arabic: "عرض أقل"],
        "Show More": [.english: "Show More", .german: "Mehr anzeigen", .french: "Afficher plus", .arabic: "عرض المزيد"],
        "TRANSFER TO TASK": [.english: "TRANSFER TO TASK", .german: "IN AUFGABE UMWANDELN", .french: "TRANSFÉRER EN TÂCHE", .arabic: "تحويل إلى مهمة"],
        
        // Migration Modals
        "Skip": [.english: "Skip", .german: "Überspringen", .french: "Ignorer", .arabic: "تخطي"],
        "Migrate": [.english: "Migrate", .german: "Übertragen", .french: "Transférer", .arabic: "نقل"],
        "Commit": [.english: "Commit", .german: "Festlegen", .french: "Valider", .arabic: "تأكيد"],
        "FROM YOUR DAY": [.english: "FROM YOUR DAY", .german: "AUS DEINEM TAG", .french: "DE VOTRE JOURNÉE", .arabic: "من يومك"],
        "Migrate Tasks": [.english: "Migrate Tasks", .german: "Aufgaben übertragen", .french: "Transférer les tâches", .arabic: "نقل المهام"],
        "Nothing left in your 1 Day list.": [
            .english: "Nothing left in your 1 Day list.",
            .german: "Keine offenen Aufgaben in deiner 1-Tag-Liste.",
            .french: "Rien dans votre liste 1 Jour.",
            .arabic: "لا توجد مهام متبقية في قائمة اليوم."
        ],
        "No habits left for this period.": [
            .english: "No habits left for this period.",
            .german: "Keine Gewohnheiten für diesen Zeitraum offen.",
            .french: "Aucune habitude restante pour cette période.",
            .arabic: "لا توجد عادات متبقية لهذه الفترة."
        ],
        "No incomplete tasks available to transfer.": [
            .english: "No incomplete tasks available to transfer.",
            .german: "Keine offenen Aufgaben zum Übertragen vorhanden.",
            .french: "Aucune tâche incomplète à transférer.",
            .arabic: "لا توجد مهام غير مكتملة للنقل."
        ],
        
        // Settings & Preferences
        "SETTINGS": [.english: "SETTINGS", .german: "EINSTELLUNGEN", .french: "PARAMÈTRES", .arabic: "الإعدادات"],
        "LANGUAGE": [.english: "LANGUAGE", .german: "SPRACHE", .french: "LANGUE", .arabic: "اللغة"],
        "Settings": [.english: "Settings", .german: "Einstellungen", .french: "Paramètres", .arabic: "الإعدادات"],
        "Language": [.english: "Language", .german: "Sprache", .french: "Langue", .arabic: "اللغة"],
        "PREFERENCES": [.english: "PREFERENCES", .german: "EINSTELLUNGEN", .french: "PRÉFÉRENCES", .arabic: "التفضيلات"],
        "DISPLAY": [.english: "DISPLAY", .german: "ANZEIGE", .french: "AFFICHAGE", .arabic: "العرض"],
        "Show Habits Bar": [.english: "Show Habits Bar", .german: "Habits-Leiste anzeigen", .french: "Afficher la barre d'habitudes", .arabic: "إظهار شريط العادات"],
        "Sound Effects": [.english: "Sound Effects", .german: "Soundeffekte", .french: "Effets sonores", .arabic: "المؤثرات الصوتية"],
        "ACCOUNT": [.english: "ACCOUNT", .german: "KONTO", .french: "COMPTE", .arabic: "الحساب"],
        "Sign Out": [.english: "Sign Out", .german: "Abmelden", .french: "Se déconnecter", .arabic: "تسجيل الخروج"],
        "Delete Account": [.english: "Delete Account", .german: "Account löschen", .french: "Supprimer le compte", .arabic: "حذف الحساب"],
        
        // Tooltips & Navigation
        "Switch to Scratchpad Lists": [.english: "Switch to Scratchpad Lists", .german: "Zu Notizlisten wechseln", .french: "Passer aux listes de notes", .arabic: "الانتقال إلى قوائم الملاحظات"],
        "Switch to Interval Tasks": [.english: "Switch to Interval Tasks", .german: "Zu Intervall-Aufgaben wechseln", .french: "Passer aux tâches d'intervalle", .arabic: "الانتقال إلى مهام الفترات"],
        "Manual Sync (⌘R)": [.english: "Manual Sync (⌘R)", .german: "Manuelle Synchronisation (⌘R)", .french: "Synchronisation manuelle (⌘R)", .arabic: "مزامنة يدوية (⌘R)"],
        "Delete List?": [.english: "Delete List?", .german: "Liste löschen?", .french: "Supprimer la liste ?", .arabic: "حذف القائمة؟"],
        "Delete": [.english: "Delete", .german: "Löschen", .french: "Supprimer", .arabic: "حذف"],
        "Cancel": [.english: "Cancel", .german: "Abbrechen", .french: "Annuler", .arabic: "إلغاء"],
        "Delete list message": [
            .english: "Are you sure you want to delete this list and all its items?",
            .german: "Möchtest du diese Liste und alle ihre Einträge wirklich löschen?",
            .french: "Voulez-vous vraiment supprimer cette liste et tous ses éléments ?",
            .arabic: "هل أنت متأكد من رغبتك في حذف هذه القائمة وجميع عناصرها؟"
        ],
        "Untitled List": [.english: "Untitled List", .german: "Unbenannte Liste", .french: "Liste sans titre", .arabic: "قائمة بدون عنوان"],
        "SUPPORT & FEEDBACK": [.english: "SUPPORT & FEEDBACK", .german: "SUPPORT & FEEDBACK", .french: "SUPPORT ET RETOURS", .arabic: "الدعم والملاحظات"],
        "For feedback, inspiration or help:": [
            .english: "For feedback, inspiration or help:",
            .german: "Für Feedback, Inspiration oder Hilfe:",
            .french: "Pour retours, inspiration ou aide :",
            .arabic: "للملاحظات أو الدعم أو الاقتراحات:"
        ],
        "For feedback, inspiration or help contact:": [
            .english: "For feedback, inspiration or help contact:",
            .german: "Für Feedback, Inspiration oder Hilfe wende dich an:",
            .french: "Pour des retours, de l'inspiration ou de l'aide :",
            .arabic: "للملاحظات أو الدعم أو المساعدة:"
        ],
        "Donations & Support:": [
            .english: "Donations & Support:",
            .german: "Spenden & Unterstützung:",
            .french: "Dons et soutien :",
            .arabic: "التبرعات والدعم:"
        ],
        "HABITS": [.english: "HABITS", .german: "GEWOHNHEITEN", .french: "HABITUDES", .arabic: "العادات"],
        "New habit...": [.english: "New habit...", .german: "Neue Gewohnheit...", .french: "Nouvelle habitude...", .arabic: "عادة جديدة..."]
    ]
}

extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}
