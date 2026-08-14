import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case arabic = "ar"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .arabic: return "العربية"
        }
    }
    
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if code.hasPrefix("de") { return .german }
        if code.hasPrefix("fr") { return .french }
        if code.hasPrefix("es") { return .spanish }
        if code.hasPrefix("it") { return .italian }
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
        "1 HOUR": [
            .english: "1 HOUR", .german: "1 STUNDE", .french: "1 HEURE",
            .spanish: "1 HORA", .italian: "1 ORA", .arabic: "ساعة واحدة"
        ],
        "1 DAY": [
            .english: "1 DAY", .german: "1 TAG", .french: "1 JOUR",
            .spanish: "1 DÍA", .italian: "1 GIORNO", .arabic: "يوم واحد"
        ],
        "1 WEEK": [
            .english: "1 WEEK", .german: "1 WOCHE", .french: "1 SEMAINE",
            .spanish: "1 SEMANA", .italian: "1 SETTIMANA", .arabic: "أسبوع واحد"
        ],
        "1 MONTH": [
            .english: "1 MONTH", .german: "1 MONAT", .french: "1 MOIS",
            .spanish: "1 MES", .italian: "1 MESE", .arabic: "شهر واحد"
        ],
        "1 YEAR": [
            .english: "1 YEAR", .german: "1 JAHR", .french: "1 AN",
            .spanish: "1 AÑO", .italian: "1 ANNO", .arabic: "سنة واحدة"
        ],
        
        // Interval Titles (for dropdown menus)
        "1 Hour": [
            .english: "1 Hour", .german: "1 Stunde", .french: "1 Heure",
            .spanish: "1 Hora", .italian: "1 Ora", .arabic: "ساعة واحدة"
        ],
        "1 Day": [
            .english: "1 Day", .german: "1 Tag", .french: "1 Jour",
            .spanish: "1 Día", .italian: "1 Giorno", .arabic: "يوم واحد"
        ],
        "1 Week": [
            .english: "1 Week", .german: "1 Woche", .french: "1 Semaine",
            .spanish: "1 Semana", .italian: "1 Settimana", .arabic: "أسبوع واحد"
        ],
        "1 Month": [
            .english: "1 Month", .german: "1 Monat", .french: "1 Mois",
            .spanish: "1 Mes", .italian: "1 Mese", .arabic: "شهر واحد"
        ],
        "1 Year": [
            .english: "1 Year", .german: "1 Jahr", .french: "1 An",
            .spanish: "1 Año", .italian: "1 Anno", .arabic: "سنة واحدة"
        ],
        
        // UI Action Labels
        "Add task...": [
            .english: "Add task...", .german: "Aufgabe hinzufügen...", .french: "Ajouter une tâche...",
            .spanish: "Añadir tarea...", .italian: "Aggiungi attività...", .arabic: "إضافة مهمة..."
        ],
        "New List": [
            .english: "New List", .german: "Neue Liste", .french: "Nouvelle liste",
            .spanish: "Nueva lista", .italian: "Nuova lista", .arabic: "قائمة جديدة"
        ],
        "List name...": [
            .english: "List name...", .german: "Listenname...", .french: "Nom de la liste...",
            .spanish: "Nombre de la lista...", .italian: "Nome della lista...", .arabic: "اسم القائمة..."
        ],
        "No custom lists created yet.": [
            .english: "No custom lists created yet.",
            .german: "Noch keine Listen erstellt.",
            .french: "Aucune liste créée.",
            .spanish: "Aún no se han creado listas.",
            .italian: "Nessuna lista personalizzata creata.",
            .arabic: "لم يتم إنشاء قوائم بعد."
        ],
        "Create First List": [
            .english: "Create First List", .german: "Erste Liste erstellen", .french: "Créer la première liste",
            .spanish: "Crear primera lista", .italian: "Crea prima lista", .arabic: "إنشاء القائمة الأولى"
        ],
        "Item...": [
            .english: "Item...", .german: "Eintrag...", .french: "Élément...",
            .spanish: "Elemento...", .italian: "Elemento...", .arabic: "عنصر..."
        ],
        "Add Item": [
            .english: "Add Item", .german: "Eintrag hinzufügen", .french: "Ajouter un élément",
            .spanish: "Añadir elemento", .italian: "Aggiungi elemento", .arabic: "إضافة عنصر"
        ],
        "ITEMS": [
            .english: "ITEMS", .german: "EINTRÄGE", .french: "ÉLÉMENTS",
            .spanish: "ELEMENTOS", .italian: "ELEMENTI", .arabic: "العناصر"
        ],
        "COMPLETED": [
            .english: "COMPLETED", .german: "ERLEDIGT", .french: "TERMINÉ",
            .spanish: "COMPLETADO", .italian: "COMPLETATO", .arabic: "المكتملة"
        ],
        "Completed": [
            .english: "Completed", .german: "Erledigt", .french: "Terminé",
            .spanish: "Completado", .italian: "Completato", .arabic: "المكتملة"
        ],
        "RECENTLY DELETED": [
            .english: "RECENTLY DELETED", .german: "KÜRZLICH GELÖSCHT", .french: "RÉCEMMENT SUPPRIMÉ",
            .spanish: "ELIMINADO RECIENTEMENTE", .italian: "ELIMINATI DI RECENTE", .arabic: "المحذوفة مؤخراً"
        ],
        "Recently Deleted": [
            .english: "Recently Deleted", .german: "Kürzlich gelöscht", .french: "Récemment supprimé",
            .spanish: "Eliminado recientemente", .italian: "Eliminati di recente", .arabic: "المحذوفة مؤخراً"
        ],
        "Clear All": [
            .english: "Clear All", .german: "Alle löschen", .french: "Tout effacer",
            .spanish: "Borrar todo", .italian: "Cancella tutto", .arabic: "مسح الكل"
        ],
        "Clear all": [
            .english: "Clear all", .german: "Alle löschen", .french: "Tout effacer",
            .spanish: "Borrar todo", .italian: "Cancella tutto", .arabic: "مسح الكل"
        ],
        "Show Less": [
            .english: "Show Less", .german: "Weniger anzeigen", .french: "Afficher moins",
            .spanish: "Mostrar menos", .italian: "Mostra meno", .arabic: "عرض أقل"
        ],
        "Show More": [
            .english: "Show More", .german: "Mehr anzeigen", .french: "Afficher plus",
            .spanish: "Mostrar más", .italian: "Mostra altro", .arabic: "عرض المزيد"
        ],
        "TRANSFER TO TASK": [
            .english: "TRANSFER TO TASK", .german: "IN AUFGABE UMWANDELN", .french: "TRANSFÉRER EN TÂCHE",
            .spanish: "TRANSFERIR A TAREA", .italian: "TRASFERISCI IN ATTIVITÀ", .arabic: "تحويل إلى مهمة"
        ],
        
        // Migration Modals
        "Skip": [
            .english: "Skip", .german: "Überspringen", .french: "Ignorer",
            .spanish: "Omitir", .italian: "Salta", .arabic: "تخطي"
        ],
        "Migrate": [
            .english: "Migrate", .german: "Übertragen", .french: "Transférer",
            .spanish: "Transferir", .italian: "Trasferisci", .arabic: "نقل"
        ],
        "Commit": [
            .english: "Commit", .german: "Festlegen", .french: "Valider",
            .spanish: "Confirmar", .italian: "Conferma", .arabic: "تأكيد"
        ],
        "FROM YOUR DAY": [
            .english: "FROM YOUR DAY", .german: "AUS DEINEM TAG", .french: "DE VOTRE JOURNÉE",
            .spanish: "DE TU DÍA", .italian: "DALLA TUA GIORNATA", .arabic: "من يومك"
        ],
        "Migrate Tasks": [
            .english: "Migrate Tasks", .german: "Aufgaben übertragen", .french: "Transférer les tâches",
            .spanish: "Transferir tareas", .italian: "Trasferisci attività", .arabic: "نقل المهام"
        ],
        "Nothing left in your 1 Day list.": [
            .english: "Nothing left in your 1 Day list.",
            .german: "Keine offenen Aufgaben in deiner 1-Tag-Liste.",
            .french: "Rien dans votre liste 1 Jour.",
            .spanish: "No queda nada en tu lista de 1 Día.",
            .italian: "Niente rimasto nella lista di 1 Giorno.",
            .arabic: "لا توجد مهام متبقية في قائمة اليوم."
        ],
        "No habits left for this period.": [
            .english: "No habits left for this period.",
            .german: "Keine Gewohnheiten für diesen Zeitraum offen.",
            .french: "Aucune habitude restante pour cette période.",
            .spanish: "No quedan hábitos para este periodo.",
            .italian: "Nessuna abitudine rimasta per questo periodo.",
            .arabic: "لا توجد عادات متبقية لهذه الفترة."
        ],
        "No incomplete tasks available to transfer.": [
            .english: "No incomplete tasks available to transfer.",
            .german: "Keine offenen Aufgaben zum Übertragen vorhanden.",
            .french: "Aucune tâche incomplète à transférer.",
            .spanish: "No hay tareas incompletas para transferir.",
            .italian: "Nessuna attività incompleta da trasferire.",
            .arabic: "لا توجد مهام غير مكتملة للنقل."
        ],
        
        // Settings & Preferences
        "SETTINGS": [
            .english: "SETTINGS", .german: "EINSTELLUNGEN", .french: "PARAMÈTRES",
            .spanish: "AJUSTES", .italian: "IMPOSTAZIONI", .arabic: "الإعدادات"
        ],
        "LANGUAGE": [
            .english: "LANGUAGE", .german: "SPRACHE", .french: "LANGUE",
            .spanish: "IDIOMA", .italian: "LINGUA", .arabic: "اللغة"
        ],
        "Settings": [
            .english: "Settings", .german: "Einstellungen", .french: "Paramètres",
            .spanish: "Ajustes", .italian: "Impostazioni", .arabic: "الإعدادات"
        ],
        "Language": [
            .english: "Language", .german: "Sprache", .french: "Langue",
            .spanish: "Idioma", .italian: "Lingua", .arabic: "اللغة"
        ],
        "PREFERENCES": [
            .english: "PREFERENCES", .german: "EINSTELLUNGEN", .french: "PRÉFÉRENCES",
            .spanish: "PREFERENCIAS", .italian: "PREFERENZE", .arabic: "التفضيلات"
        ],
        "DISPLAY": [
            .english: "DISPLAY", .german: "ANZEIGE", .french: "AFFICHAGE",
            .spanish: "PANTALLA", .italian: "VISUALIZZAZIONE", .arabic: "العرض"
        ],
        "Show Habits Bar": [
            .english: "Show Habits Bar", .german: "Habits-Leiste anzeigen", .french: "Afficher la barre d'habitudes",
            .spanish: "Mostrar barra de hábitos", .italian: "Mostra barra delle abitudini", .arabic: "إظهار شريط العادات"
        ],
        "Sound Effects": [
            .english: "Sound Effects", .german: "Soundeffekte", .french: "Effets sonores",
            .spanish: "Efectos de sonido", .italian: "Effetti sonori", .arabic: "المؤثرات الصوتية"
        ],
        "ACCOUNT": [
            .english: "ACCOUNT", .german: "KONTO", .french: "COMPTE",
            .spanish: "CUENTA", .italian: "ACCOUNT", .arabic: "الحساب"
        ],
        "Sign Out": [
            .english: "Sign Out", .german: "Abmelden", .french: "Se déconnecter",
            .spanish: "Cerrar sesión", .italian: "Disconnettiti", .arabic: "تسجيل الخروج"
        ],
        "Delete Account": [
            .english: "Delete Account", .german: "Account löschen", .french: "Supprimer le compte",
            .spanish: "Eliminar cuenta", .italian: "Elimina account", .arabic: "حذف الحساب"
        ],
        
        // Tooltips & Navigation
        "Switch to Scratchpad Lists": [
            .english: "Switch to Scratchpad Lists", .german: "Zu Notizlisten wechseln", .french: "Passer aux listes de notes",
            .spanish: "Cambiar a listas de notas", .italian: "Passa alle liste di appunti", .arabic: "الانتقال إلى قوائم الملاحظات"
        ],
        "Switch to Interval Tasks": [
            .english: "Switch to Interval Tasks", .german: "Zu Intervall-Aufgaben wechseln", .french: "Passer aux tâches d'intervalle",
            .spanish: "Cambiar a tareas de intervalos", .italian: "Passa alle attività a intervalli", .arabic: "الانتقال إلى مهام الفترات"
        ],
        "Manual Sync (⌘R)": [
            .english: "Manual Sync (⌘R)", .german: "Manuelle Synchronisation (⌘R)", .french: "Synchronisation manuelle (⌘R)",
            .spanish: "Sincronización manual (⌘R)", .italian: "Sincronizzazione manuale (⌘R)", .arabic: "مزامنة يدوية (⌘R)"
        ],
        "Delete List?": [
            .english: "Delete List?", .german: "Liste löschen?", .french: "Supprimer la liste ?",
            .spanish: "¿Eliminar lista?", .italian: "Eliminare la lista?", .arabic: "حذف القائمة؟"
        ],
        "Delete": [
            .english: "Delete", .german: "Löschen", .french: "Supprimer",
            .spanish: "Eliminar", .italian: "Elimina", .arabic: "حذف"
        ],
        "Cancel": [
            .english: "Cancel", .german: "Abbrechen", .french: "Annuler",
            .spanish: "Cancelar", .italian: "Annulla", .arabic: "إلغاء"
        ],
        "Delete list message": [
            .english: "Are you sure you want to delete this list and all its items?",
            .german: "Möchtest du diese Liste und alle ihre Einträge wirklich löschen?",
            .french: "Voulez-vous vraiment supprimer cette liste et tous ses éléments ?",
            .spanish: "¿Seguro que quieres eliminar esta lista y todos sus elementos?",
            .italian: "Sei sicuro di voler eliminare questa lista e tutti i suoi elementi?",
            .arabic: "هل أنت متأكد من رغبتك في حذف هذه القائمة وجميع عناصرها؟"
        ],
        "Untitled List": [
            .english: "Untitled List", .german: "Unbenannte Liste", .french: "Liste sans titre",
            .spanish: "Lista sin título", .italian: "Lista senza titolo", .arabic: "قائمة بدون عنوان"
        ],
        "SUPPORT & FEEDBACK": [
            .english: "SUPPORT & FEEDBACK", .german: "SUPPORT & FEEDBACK", .french: "SUPPORT ET RETOURS",
            .spanish: "SOPORTE Y COMENTARIOS", .italian: "SUPPORTO E FEEDBACK", .arabic: "الدعم والملاحظات"
        ],
        "For feedback, inspiration or help:": [
            .english: "For feedback, inspiration or help:",
            .german: "Für Feedback, Inspiration oder Hilfe:",
            .french: "Pour retours, inspiration ou aide :",
            .spanish: "Para comentarios, inspiración o ayuda:",
            .italian: "Per feedback, ispirazione o aiuto:",
            .arabic: "للملاحظات أو الدعم أو الاقتراحات:"
        ],
        "For feedback, inspiration or help contact:": [
            .english: "For feedback, inspiration or help contact:",
            .german: "Für Feedback, Inspiration oder Hilfe wende dich an:",
            .french: "Pour des retours, de l'inspiration ou de l'aide :",
            .spanish: "Para comentarios, inspiración o ayuda contacta con:",
            .italian: "Per feedback, ispirazione o supporto contatta:",
            .arabic: "للملاحظات أو الدعم أو المساعدة:"
        ],
        "Donations & Support:": [
            .english: "Donations & Support:",
            .german: "Spenden & Unterstützung:",
            .french: "Dons et soutien :",
            .spanish: "Donaciones y soporte:",
            .italian: "Donazioni e supporto:",
            .arabic: "التبرعات والدعم:"
        ],
        "HABITS": [
            .english: "HABITS", .german: "GEWOHNHEITEN", .french: "HABITUDES",
            .spanish: "HÁBITOS", .italian: "ABITUDINI", .arabic: "العادات"
        ],
        "New habit...": [
            .english: "New habit...", .german: "Neue Gewohnheit...", .french: "Nouvelle habitude...",
            .spanish: "Nuevo hábito...", .italian: "Nuova abitudine...", .arabic: "عادة جديدة..."
        ]
    ]
}

extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}
