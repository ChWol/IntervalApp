import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case arabic = "ar"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        case .italian: return "Italiano"
        case .arabic: return "العربية"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if code.hasPrefix("de") { return .german }
        if code.hasPrefix("fr") { return .french }
        if code.hasPrefix("es") { return .spanish }
        if code.hasPrefix("pt") { return .portuguese }
        if code.hasPrefix("it") { return .italian }
        if code.hasPrefix("ar") { return .arabic }
        if code.hasPrefix("zh") { return .chinese }
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("ko") { return .korean }
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
            .spanish: "1 HORA", .portuguese: "1 HORA", .italian: "1 ORA",
            .arabic: "ساعة واحدة", .chinese: "1小时", .japanese: "1時間", .korean: "1시간"
        ],
        "1 DAY": [
            .english: "1 DAY", .german: "1 TAG", .french: "1 JOUR",
            .spanish: "1 DÍA", .portuguese: "1 DIA", .italian: "1 GIORNO",
            .arabic: "يوم واحد", .chinese: "1天", .japanese: "1日", .korean: "1일"
        ],
        "1 WEEK": [
            .english: "1 WEEK", .german: "1 WOCHE", .french: "1 SEMAINE",
            .spanish: "1 SEMANA", .portuguese: "1 SEMANA", .italian: "1 SETTIMANA",
            .arabic: "أسبوع واحد", .chinese: "1周", .japanese: "1週間", .korean: "1주일"
        ],
        "1 MONTH": [
            .english: "1 MONTH", .german: "1 MONAT", .french: "1 MOIS",
            .spanish: "1 MES", .portuguese: "1 MÊS", .italian: "1 MESE",
            .arabic: "شهر واحد", .chinese: "1个月", .japanese: "1ヶ月", .korean: "1개월"
        ],
        "1 YEAR": [
            .english: "1 YEAR", .german: "1 JAHR", .french: "1 AN",
            .spanish: "1 AÑO", .portuguese: "1 ANO", .italian: "1 ANNO",
            .arabic: "سنة واحدة", .chinese: "1年", .japanese: "1年", .korean: "1년"
        ],
        
        // Interval Titles (for dropdown menus)
        "1 Hour": [
            .english: "1 Hour", .german: "1 Stunde", .french: "1 Heure",
            .spanish: "1 Hora", .portuguese: "1 Hora", .italian: "1 Ora",
            .arabic: "ساعة واحدة", .chinese: "1小时", .japanese: "1時間", .korean: "1시간"
        ],
        "1 Day": [
            .english: "1 Day", .german: "1 Tag", .french: "1 Jour",
            .spanish: "1 Día", .portuguese: "1 Dia", .italian: "1 Giorno",
            .arabic: "يوم واحد", .chinese: "1天", .japanese: "1日", .korean: "1일"
        ],
        "1 Week": [
            .english: "1 Week", .german: "1 Woche", .french: "1 Semaine",
            .spanish: "1 Semana", .portuguese: "1 Semana", .italian: "1 Settimana",
            .arabic: "أسبوع واحد", .chinese: "1周", .japanese: "1週間", .korean: "1주일"
        ],
        "1 Month": [
            .english: "1 Month", .german: "1 Monat", .french: "1 Mois",
            .spanish: "1 Mes", .portuguese: "1 Mês", .italian: "1 Mese",
            .arabic: "شهر واحد", .chinese: "1个月", .japanese: "1ヶ月", .korean: "1개월"
        ],
        "1 Year": [
            .english: "1 Year", .german: "1 Jahr", .french: "1 An",
            .spanish: "1 Año", .portuguese: "1 Ano", .italian: "1 Anno",
            .arabic: "سنة واحدة", .chinese: "1年", .japanese: "1年", .korean: "1년"
        ],
        
        // UI Action Labels
        "Add task...": [
            .english: "Add task...", .german: "Aufgabe hinzufügen...", .french: "Ajouter une tâche...",
            .spanish: "Añadir tarea...", .portuguese: "Adicionar tarefa...", .italian: "Aggiungi attività...",
            .arabic: "إضافة مهمة...", .chinese: "添加任务...", .japanese: "タスクを追加...", .korean: "할 일 추가..."
        ],
        "New List": [
            .english: "New List", .german: "Neue Liste", .french: "Nouvelle liste",
            .spanish: "Nueva lista", .portuguese: "Nova lista", .italian: "Nuova lista",
            .arabic: "قائمة جديدة", .chinese: "新建列表", .japanese: "新規リスト", .korean: "새 목록"
        ],
        "List name...": [
            .english: "List name...", .german: "Listenname...", .french: "Nom de la liste...",
            .spanish: "Nombre de la lista...", .portuguese: "Nome da lista...", .italian: "Nome della lista...",
            .arabic: "اسم القائمة...", .chinese: "列表名称...", .japanese: "リスト名...", .korean: "목록 이름..."
        ],
        "No custom lists created yet.": [
            .english: "No custom lists created yet.",
            .german: "Noch keine Listen erstellt.",
            .french: "Aucune liste créée.",
            .spanish: "Aún no se han creado listas.",
            .portuguese: "Nenhuma lista personalizada criada ainda.",
            .italian: "Nessuna lista personalizzata creata.",
            .arabic: "لم يتم إنشاء قوائم بعد.",
            .chinese: "暂无自定义列表。",
            .japanese: "カスタムリストがまだありません。",
            .korean: "아직 생성된 목록이 없습니다."
        ],
        "Create First List": [
            .english: "Create First List", .german: "Erste Liste erstellen", .french: "Créer la première liste",
            .spanish: "Crear primera lista", .portuguese: "Criar primeira lista", .italian: "Crea prima lista",
            .arabic: "إنشاء القائمة الأولى", .chinese: "创建第一个列表", .japanese: "最初のリストを作成", .korean: "첫 번째 목록 만들기"
        ],
        "Item...": [
            .english: "Item...", .german: "Eintrag...", .french: "Élément...",
            .spanish: "Elemento...", .portuguese: "Item...", .italian: "Elemento...",
            .arabic: "عنصر...", .chinese: "事项...", .japanese: "アイテム...", .korean: "항목..."
        ],
        "Add Item": [
            .english: "Add Item", .german: "Eintrag hinzufügen", .french: "Ajouter un élément",
            .spanish: "Añadir elemento", .portuguese: "Adicionar item", .italian: "Aggiungi elemento",
            .arabic: "إضافة عنصر", .chinese: "添加事项", .japanese: "アイテムを追加", .korean: "항목 추가"
        ],
        "ITEMS": [
            .english: "ITEMS", .german: "EINTRÄGE", .french: "ÉLÉMENTS",
            .spanish: "ELEMENTOS", .portuguese: "ITENS", .italian: "ELEMENTI",
            .arabic: "العناصر", .chinese: "事项", .japanese: "アイテム", .korean: "항목"
        ],
        "COMPLETED": [
            .english: "COMPLETED", .german: "ERLEDIGT", .french: "TERMINÉ",
            .spanish: "COMPLETADO", .portuguese: "CONCLUÍDO", .italian: "COMPLETATO",
            .arabic: "المكتملة", .chinese: "已完成", .japanese: "完了済み", .korean: "완료됨"
        ],
        "Completed": [
            .english: "Completed", .german: "Erledigt", .french: "Terminé",
            .spanish: "Completado", .portuguese: "Concluído", .italian: "Completato",
            .arabic: "المكتملة", .chinese: "已完成", .japanese: "完了済み", .korean: "완료됨"
        ],
        "RECENTLY DELETED": [
            .english: "RECENTLY DELETED", .german: "KÜRZLICH GELÖSCHT", .french: "RÉCEMMENT SUPPRIMÉ",
            .spanish: "ELIMINADO RECIENTEMENTE", .portuguese: "EXCLUÍDO RECENTEMENTE", .italian: "ELIMINATI DI RECENTE",
            .arabic: "المحذوفة مؤخراً", .chinese: "最近删除", .japanese: "最近削除した項目", .korean: "최근 삭제된 항목"
        ],
        "Recently Deleted": [
            .english: "Recently Deleted", .german: "Kürzlich gelöscht", .french: "Récemment supprimé",
            .spanish: "Eliminado recientemente", .portuguese: "Excluído recentemente", .italian: "Eliminati di recente",
            .arabic: "المحذوفة مؤخراً", .chinese: "最近删除", .japanese: "最近削除した項目", .korean: "최근 삭제된 항목"
        ],
        "Clear All": [
            .english: "Clear All", .german: "Alle löschen", .french: "Tout effacer",
            .spanish: "Borrar todo", .portuguese: "Limpar tudo", .italian: "Cancella tutto",
            .arabic: "مسح الكل", .chinese: "清空全部", .japanese: "すべて削除", .korean: "모두 지우기"
        ],
        "Clear all": [
            .english: "Clear all", .german: "Alle löschen", .french: "Tout effacer",
            .spanish: "Borrar todo", .portuguese: "Limpar tudo", .italian: "Cancella tutto",
            .arabic: "مسح الكل", .chinese: "清空全部", .japanese: "すべて削除", .korean: "모두 지우기"
        ],
        "Show Less": [
            .english: "Show Less", .german: "Weniger anzeigen", .french: "Afficher moins",
            .spanish: "Mostrar menos", .portuguese: "Mostrar menos", .italian: "Mostra meno",
            .arabic: "عرض أقل", .chinese: "收起", .japanese: "折りたたむ", .korean: "간략히 보기"
        ],
        "Show More": [
            .english: "Show More", .german: "Mehr anzeigen", .french: "Afficher plus",
            .spanish: "Mostrar más", .portuguese: "Mostrar mais", .italian: "Mostra altro",
            .arabic: "عرض المزيد", .chinese: "展开更多", .japanese: "さらに表示", .korean: "더 보기"
        ],
        "TRANSFER TO TASK": [
            .english: "TRANSFER TO TASK", .german: "IN AUFGABE UMWANDELN", .french: "TRANSFÉRER EN TÂCHE",
            .spanish: "TRANSFERIR A TAREA", .portuguese: "TRANSFERIR PARA TAREFA", .italian: "TRASFERISCI IN ATTIVITÀ",
            .arabic: "تحويل إلى مهمة", .chinese: "转换为任务", .japanese: "タスクに変換", .korean: "할 일로 전환"
        ],
        
        // Migration Modals
        "Skip": [
            .english: "Skip", .german: "Überspringen", .french: "Ignorer",
            .spanish: "Omitir", .portuguese: "Pular", .italian: "Salta",
            .arabic: "تخطي", .chinese: "跳过", .japanese: "スキップ", .korean: "건너뛰기"
        ],
        "Migrate": [
            .english: "Migrate", .german: "Übertragen", .french: "Transférer",
            .spanish: "Transferir", .portuguese: "Transferir", .italian: "Trasferisci",
            .arabic: "نقل", .chinese: "迁移", .japanese: "移行", .korean: "이동"
        ],
        "Commit": [
            .english: "Commit", .german: "Festlegen", .french: "Valider",
            .spanish: "Confirmar", .portuguese: "Confirmar", .italian: "Conferma",
            .arabic: "تأكيد", .chinese: "确定", .japanese: "確定", .korean: "확인"
        ],
        "FROM YOUR DAY": [
            .english: "FROM YOUR DAY", .german: "AUS DEINEM TAG", .french: "DE VOTRE JOURNÉE",
            .spanish: "DE TU DÍA", .portuguese: "DO SEU DIA", .italian: "DALLA TUA GIORNATA",
            .arabic: "من يومك", .chinese: "来自今日", .japanese: "本日のリストから", .korean: "오늘의 목록에서"
        ],
        "Migrate Tasks": [
            .english: "Migrate Tasks", .german: "Aufgaben übertragen", .french: "Transférer les tâches",
            .spanish: "Transferir tareas", .portuguese: "Transferir tarefas", .italian: "Trasferisci attività",
            .arabic: "نقل المهام", .chinese: "迁移任务", .japanese: "タスクを移行", .korean: "할 일 이동"
        ],
        "Nothing left in your 1 Day list.": [
            .english: "Nothing left in your 1 Day list.",
            .german: "Keine offenen Aufgaben in deiner 1-Tag-Liste.",
            .french: "Rien dans votre liste 1 Jour.",
            .spanish: "No queda nada en tu lista de 1 Día.",
            .portuguese: "Nada restante na sua lista de 1 Dia.",
            .italian: "Niente rimasto nella lista di 1 Giorno.",
            .arabic: "لا توجد مهام متبقية في قائمة اليوم.",
            .chinese: "今日列表中已无任务。",
            .japanese: "本日のリストに残っているタスクはありません。",
            .korean: "오늘 목록에 남은 할 일이 없습니다."
        ],
        "No habits left for this period.": [
            .english: "No habits left for this period.",
            .german: "Keine Gewohnheiten für diesen Zeitraum offen.",
            .french: "Aucune habitude restante pour cette période.",
            .spanish: "No quedan hábitos para este periodo.",
            .portuguese: "Nenhum hábito restante para este período.",
            .italian: "Nessuna abitudine rimasta per questo periodo.",
            .arabic: "لا توجد عادات متبقية لهذه الفترة.",
            .chinese: "本周期暂无待办习惯。",
            .japanese: "この期間に残っている習慣はありません。",
            .korean: "이 기간에 남은 습관이 없습니다."
        ],
        "No incomplete tasks available to transfer.": [
            .english: "No incomplete tasks available to transfer.",
            .german: "Keine offenen Aufgaben zum Übertragen vorhanden.",
            .french: "Aucune tâche incomplète à transférer.",
            .spanish: "No hay tareas incompletas para transferir.",
            .portuguese: "Nenhuma tarefa incompleta para transferir.",
            .italian: "Nessuna attività incompleta da trasferire.",
            .arabic: "لا توجد مهام غير مكتملة للنقل.",
            .chinese: "无未完成任务可迁移。",
            .japanese: "移行可能な未完了タスクはありません。",
            .korean: "이동할 미완료 할 일이 없습니다."
        ],
        
        // Settings & Preferences
        "SETTINGS": [
            .english: "SETTINGS", .german: "EINSTELLUNGEN", .french: "PARAMÈTRES",
            .spanish: "AJUSTES", .portuguese: "CONFIGURAÇÕES", .italian: "IMPOSTAZIONI",
            .arabic: "الإعدادات", .chinese: "设置", .japanese: "設定", .korean: "설정"
        ],
        "LANGUAGE": [
            .english: "LANGUAGE", .german: "SPRACHE", .french: "LANGUE",
            .spanish: "IDIOMA", .portuguese: "IDIOMA", .italian: "LINGUA",
            .arabic: "اللغة", .chinese: "语言", .japanese: "言語", .korean: "언어"
        ],
        "Settings": [
            .english: "Settings", .german: "Einstellungen", .french: "Paramètres",
            .spanish: "Ajustes", .portuguese: "Configurações", .italian: "Impostazioni",
            .arabic: "الإعدادات", .chinese: "设置", .japanese: "設定", .korean: "설정"
        ],
        "Language": [
            .english: "Language", .german: "Sprache", .french: "Langue",
            .spanish: "Idioma", .portuguese: "Idioma", .italian: "Lingua",
            .arabic: "اللغة", .chinese: "语言", .japanese: "言語", .korean: "언어"
        ],
        "PREFERENCES": [
            .english: "PREFERENCES", .german: "EINSTELLUNGEN", .french: "PRÉFÉRENCES",
            .spanish: "PREFERENCIAS", .portuguese: "PREFERÊNCIAS", .italian: "PREFERENZE",
            .arabic: "التفضيلات", .chinese: "偏好设置", .japanese: "環境設定", .korean: "환경설정"
        ],
        "DISPLAY": [
            .english: "DISPLAY", .german: "ANZEIGE", .french: "AFFICHAGE",
            .spanish: "PANTALLA", .portuguese: "EXIBIÇÃO", .italian: "VISUALIZZAZIONE",
            .arabic: "العرض", .chinese: "显示", .japanese: "表示", .korean: "화면 표시"
        ],
        "Show Habits Bar": [
            .english: "Show Habits Bar", .german: "Habits-Leiste anzeigen", .french: "Afficher la barre d'habitudes",
            .spanish: "Mostrar barra de hábitos", .portuguese: "Mostrar barra de hábitos", .italian: "Mostra barra delle abitudini",
            .arabic: "إظهار شريط العادات", .chinese: "显示习惯栏", .japanese: "習慣バーを表示", .korean: "습관 바 표시"
        ],
        "Sound Effects": [
            .english: "Sound Effects", .german: "Soundeffekte", .french: "Effets sonores",
            .spanish: "Efectos de sonido", .portuguese: "Efeitos sonoros", .italian: "Effetti sonori",
            .arabic: "المؤثرات الصوتية", .chinese: "音效", .japanese: "効果音", .korean: "효과음"
        ],
        "ACCOUNT": [
            .english: "ACCOUNT", .german: "KONTO", .french: "COMPTE",
            .spanish: "CUENTA", .portuguese: "CONTA", .italian: "ACCOUNT",
            .arabic: "الحساب", .chinese: "账户", .japanese: "アカウント", .korean: "계정"
        ],
        "Sign Out": [
            .english: "Sign Out", .german: "Abmelden", .french: "Se déconnecter",
            .spanish: "Cerrar sesión", .portuguese: "Sair", .italian: "Disconnettiti",
            .arabic: "تسجيل الخروج", .chinese: "退出登录", .japanese: "サインアウト", .korean: "로그아웃"
        ],
        "Delete Account": [
            .english: "Delete Account", .german: "Account löschen", .french: "Supprimer le compte",
            .spanish: "Eliminar cuenta", .portuguese: "Excluir conta", .italian: "Elimina account",
            .arabic: "حذف الحساب", .chinese: "删除账户", .japanese: "アカウントを削除", .korean: "계정 삭제"
        ],
        
        // Tooltips & Navigation
        "Switch to Scratchpad Lists": [
            .english: "Switch to Scratchpad Lists", .german: "Zu Notizlisten wechseln", .french: "Passer aux listes de notes",
            .spanish: "Cambiar a listas de notas", .portuguese: "Alternar para listas de notas", .italian: "Passa alle liste di appunti",
            .arabic: "الانتقال إلى قوائم الملاحظات", .chinese: "切换到便签列表", .japanese: "メモリストに切り替え", .korean: "메모 목록으로 전환"
        ],
        "Switch to Interval Tasks": [
            .english: "Switch to Interval Tasks", .german: "Zu Intervall-Aufgaben wechseln", .french: "Passer aux tâches d'intervalle",
            .spanish: "Cambiar a tareas de intervalos", .portuguese: "Alternar para tarefas de intervalo", .italian: "Passa alle attività a intervalli",
            .arabic: "الانتقال إلى مهام الفترات", .chinese: "切换到时间间隔任务", .japanese: "インターバルタスクに切り替え", .korean: "간격 할 일로 전환"
        ],
        "Manual Sync (⌘R)": [
            .english: "Manual Sync (⌘R)", .german: "Manuelle Synchronisation (⌘R)", .french: "Synchronisation manuelle (⌘R)",
            .spanish: "Sincronización manual (⌘R)", .portuguese: "Sincronização manual (⌘R)", .italian: "Sincronizzazione manuale (⌘R)",
            .arabic: "مزامنة يدوية (⌘R)", .chinese: "手动同步 (⌘R)", .japanese: "手動同期 (⌘R)", .korean: "수동 동기화 (⌘R)"
        ],
        "Delete List?": [
            .english: "Delete List?", .german: "Liste löschen?", .french: "Supprimer la liste ?",
            .spanish: "¿Eliminar lista?", .portuguese: "Excluir lista?", .italian: "Eliminare la lista?",
            .arabic: "حذف القائمة؟", .chinese: "删除列表？", .japanese: "リストを削除しますか？", .korean: "목록을 삭제하시겠습니까?"
        ],
        "Delete": [
            .english: "Delete", .german: "Löschen", .french: "Supprimer",
            .spanish: "Eliminar", .portuguese: "Excluir", .italian: "Elimina",
            .arabic: "حذف", .chinese: "删除", .japanese: "削除", .korean: "삭제"
        ],
        "Cancel": [
            .english: "Cancel", .german: "Abbrechen", .french: "Annuler",
            .spanish: "Cancelar", .portuguese: "Cancelar", .italian: "Annulla",
            .arabic: "إلغاء", .chinese: "取消", .japanese: "キャンセル", .korean: "취소"
        ],
        "Delete list message": [
            .english: "Are you sure you want to delete this list and all its items?",
            .german: "Möchtest du diese Liste und alle ihre Einträge wirklich löschen?",
            .french: "Voulez-vous vraiment supprimer cette liste et tous ses éléments ?",
            .spanish: "¿Seguro que quieres eliminar esta lista y todos sus elementos?",
            .portuguese: "Tem certeza de que deseja excluir esta lista e todos os seus itens?",
            .italian: "Sei sicuro di voler eliminare questa lista e tutti i suoi elementi?",
            .arabic: "هل أنت متأكد من رغبتك في حذف هذه القائمة وجميع عناصرها؟",
            .chinese: "确定要删除此列表及其所有事项吗？",
            .japanese: "このリストとすべてのアイテムを削除してもよろしいですか？",
            .korean: "이 목록과 모든 항목을 삭제하시겠습니까?"
        ],
        "Untitled List": [
            .english: "Untitled List", .german: "Unbenannte Liste", .french: "Liste sans titre",
            .spanish: "Lista sin título", .portuguese: "Lista sem título", .italian: "Lista senza titolo",
            .arabic: "قائمة بدون عنوان", .chinese: "无标题列表", .japanese: "無題のリスト", .korean: "제목 없는 목록"
        ],
        "SUPPORT & FEEDBACK": [
            .english: "SUPPORT & FEEDBACK", .german: "SUPPORT & FEEDBACK", .french: "SUPPORT ET RETOURS",
            .spanish: "SOPORTE Y COMENTARIOS", .portuguese: "SUPORTE E FEEDBACK", .italian: "SUPPORTO E FEEDBACK",
            .arabic: "الدعم والملاحظات", .chinese: "支持与反馈", .japanese: "サポートとフィードバック", .korean: "지원 및 피드백"
        ],
        "For feedback, inspiration or help:": [
            .english: "For feedback, inspiration or help:",
            .german: "Für Feedback, Inspiration oder Hilfe:",
            .french: "Pour retours, inspiration ou aide :",
            .spanish: "Para comentarios, inspiración o ayuda:",
            .portuguese: "Para feedback, inspiração ou ajuda:",
            .italian: "Per feedback, ispirazione o aiuto:",
            .arabic: "للملاحظات أو الدعم أو الاقتراحات:",
            .chinese: "获取反馈、灵感或帮助：",
            .japanese: "フィードバック、ご提案、サポート：",
            .korean: "피드백, 아이디어 또는 도움말:"
        ],
        "For feedback, inspiration or help contact:": [
            .english: "For feedback, inspiration or help contact:",
            .german: "Für Feedback, Inspiration oder Hilfe wende dich an:",
            .french: "Pour des retours, de l'inspiration ou de l'aide :",
            .spanish: "Para comentarios, inspiración o ayuda contacta con:",
            .portuguese: "Para feedback, inspiração ou ajuda entre em contato:",
            .italian: "Per feedback, ispirazione o supporto contatta:",
            .arabic: "للملاحظات أو الدعم أو المساعدة:",
            .chinese: "如需反馈、灵感或帮助请联系：",
            .japanese: "ご意見、ご要望、お問い合わせ：",
            .korean: "피드백, 문의 및 지원 연락처:"
        ],
        "Donations & Support:": [
            .english: "Donations & Support:",
            .german: "Spenden & Unterstützung:",
            .french: "Dons et soutien :",
            .spanish: "Donaciones y soporte:",
            .portuguese: "Doações e suporte:",
            .italian: "Donazioni e supporto:",
            .arabic: "التبرعات والدعم:",
            .chinese: "赞助与支持：",
            .japanese: "寄付とサポート：",
            .korean: "후원 및 지원:"
        ],
        "HABITS": [
            .english: "HABITS", .german: "GEWOHNHEITEN", .french: "HABITUDES",
            .spanish: "HÁBITOS", .portuguese: "HÁBITOS", .italian: "ABITUDINI",
            .arabic: "العادات", .chinese: "习惯", .japanese: "習慣", .korean: "습관"
        ],
        "New habit...": [
            .english: "New habit...", .german: "Neue Gewohnheit...", .french: "Nouvelle habitude...",
            .spanish: "Nuevo hábito...", .portuguese: "Novo hábito...", .italian: "Nuova abitudine...",
            .arabic: "عادة جديدة...", .chinese: "新习惯...", .japanese: "新しい習慣...", .korean: "새 습관..."
        ],
        
        // Search
        "SEARCH": [
            .english: "SEARCH", .german: "SUCHE", .french: "RECHERCHE",
            .spanish: "BÚSQUEDA", .portuguese: "BUSCA", .italian: "RICERCA",
            .arabic: "بحث", .chinese: "搜索", .japanese: "検索", .korean: "검색"
        ],
        "TASKS": [
            .english: "TASKS", .german: "AUFGABEN", .french: "TÂCHES",
            .spanish: "TAREAS", .portuguese: "TAREFAS", .italian: "ATTIVITÀ",
            .arabic: "المهام", .chinese: "任务", .japanese: "タスク", .korean: "할 일"
        ],
        "Search...": [
            .english: "Search...", .german: "Suchen...", .french: "Rechercher...",
            .spanish: "Buscar...", .portuguese: "Buscar...", .italian: "Cerca...",
            .arabic: "بحث...", .chinese: "搜索...", .japanese: "検索...", .korean: "검색..."
        ],
        "Search tasks, habits, lists...": [
            .english: "Search tasks, habits, lists...",
            .german: "Aufgaben, Habits, Listen durchsuchen...",
            .french: "Rechercher tâches, habitudes, listes...",
            .spanish: "Buscar tareas, hábitos, listas...",
            .portuguese: "Buscar tarefas, hábitos, listas...",
            .italian: "Cerca attività, abitudini, liste...",
            .arabic: "البحث في المهام والعادات والقوائم...",
            .chinese: "搜索任务、习惯、列表...",
            .japanese: "タスク、習慣、リストを検索...",
            .korean: "할 일, 습관, 목록 검색..."
        ],
        "No results found": [
            .english: "No results found",
            .german: "Keine Ergebnisse gefunden",
            .french: "Aucun résultat trouvé",
            .spanish: "No se encontraron resultados",
            .portuguese: "Nenhum resultado encontrado",
            .italian: "Nessun risultato trovato",
            .arabic: "لم يتم العثور على نتائج",
            .chinese: "未找到相关结果",
            .japanese: "結果が見つかりませんでした",
            .korean: "검색 결과가 없습니다"
        ],
        "Type to search across all intervals, habits & lists": [
            .english: "Type to search across all intervals, habits & lists",
            .german: "Tippen, um alle Intervalle, Habits & Listen zu durchsuchen",
            .french: "Tapez pour rechercher dans tous les intervalles, habitudes et listes",
            .spanish: "Escribe para buscar en todos los intervalos, hábitos y listas",
            .portuguese: "Digite para pesquisar em todos os intervalos, hábitos e listas",
            .italian: "Digita per cercare in tutti gli intervalli, abitudini e liste",
            .arabic: "اكتب للبحث في جميع الفترات والعادات والقوائم",
            .chinese: "输入以搜索所有时间段、习惯和列表",
            .japanese: "入力してすべてのインターバル、習慣、リストを検索",
            .korean: "모든 간격, 습관 및 목록을 검색하려면 입력하세요"
        ],
        
        // List Sharing
        "Share List": [
            .english: "Share List", .german: "Liste teilen", .french: "Partager la liste",
            .spanish: "Compartir lista", .portuguese: "Compartilhar lista", .italian: "Condividi lista",
            .arabic: "مشاركة القائمة", .chinese: "共享列表", .japanese: "リストを共有", .korean: "목록 공유"
        ],
        "Share": [
            .english: "Share", .german: "Teilen", .french: "Partager",
            .spanish: "Compartir", .portuguese: "Compartilhar", .italian: "Condividi",
            .arabic: "مشاركة", .chinese: "共享", .japanese: "共有", .korean: "공유"
        ],
        "Enter email address...": [
            .english: "Enter email address...", .german: "E-Mail-Adresse eingeben...", .french: "Entrez l'adresse e-mail...",
            .spanish: "Introduce el correo electrónico...", .portuguese: "Digite o endereço de e-mail...", .italian: "Inserisci l'indirizzo email...",
            .arabic: "أدخل عنوان البريد الإلكتروني...", .chinese: "输入邮箱地址...", .japanese: "メールアドレスを入力...", .korean: "이메일 주소 입력..."
        ],
        "Invite": [
            .english: "Invite", .german: "Einladen", .french: "Inviter",
            .spanish: "Invitar", .portuguese: "Convidar", .italian: "Invita",
            .arabic: "دعوة", .chinese: "邀请", .japanese: "招待", .korean: "초대"
        ],
        "Owner": [
            .english: "Owner", .german: "Eigentümer", .french: "Propriétaire",
            .spanish: "Propietario", .portuguese: "Proprietário", .italian: "Proprietario",
            .arabic: "المالك", .chinese: "所有者", .japanese: "オーナー", .korean: "소유자"
        ],
        "Member": [
            .english: "Member", .german: "Mitglied", .french: "Membre",
            .spanish: "Miembro", .portuguese: "Membro", .italian: "Membro",
            .arabic: "عضو", .chinese: "成员", .japanese: "メンバー", .korean: "멤버"
        ],
        "Remove": [
            .english: "Remove", .german: "Entfernen", .french: "Supprimer",
            .spanish: "Eliminar", .portuguese: "Remover", .italian: "Rimuovi",
            .arabic: "إزالة", .chinese: "移除", .japanese: "削除", .korean: "제거"
        ],
        "Leave List": [
            .english: "Leave List", .german: "Liste verlassen", .french: "Quitter la liste",
            .spanish: "Salir de la lista", .portuguese: "Sair da lista", .italian: "Lascia lista",
            .arabic: "مغادرة القائمة", .chinese: "离开列表", .japanese: "リストから退出", .korean: "목록에서 나가기"
        ],
        "Shared": [
            .english: "Shared", .german: "Geteilt", .french: "Partagé",
            .spanish: "Compartido", .portuguese: "Compartilhado", .italian: "Condiviso",
            .arabic: "مشترك", .chinese: "已共享", .japanese: "共有中", .korean: "공유됨"
        ],
        "MEMBERS": [
            .english: "MEMBERS", .german: "MITGLIEDER", .french: "MEMBRES",
            .spanish: "MIEMBROS", .portuguese: "MEMBROS", .italian: "MEMBRI",
            .arabic: "الأعضاء", .chinese: "成员", .japanese: "メンバー", .korean: "멤버"
        ],
        "No collaborators yet": [
            .english: "No collaborators yet", .german: "Noch keine Mitglieder", .french: "Aucun collaborateur pour l'instant",
            .spanish: "Aún no hay colaboradores", .portuguese: "Nenhum colaborador ainda", .italian: "Ancora nessun collaboratore",
            .arabic: "لا يوجد أعضاء بعد", .chinese: "暂无协作者", .japanese: "共同作業者はまだいません", .korean: "아직 협업자가 없습니다"
        ],
        "Invalid email address": [
            .english: "Invalid email address", .german: "Ungültige E-Mail-Adresse", .french: "Adresse e-mail invalide",
            .spanish: "Dirección de correo inválida", .portuguese: "Endereço de e-mail inválido", .italian: "Indirizzo email non valido",
            .arabic: "عنوان بريد إلكتروني غير صالح", .chinese: "无效的邮箱地址", .japanese: "無効なメールアドレス", .korean: "유효하지 않은 이메일 주소"
        ],
        "Already have an account?": [
            .english: "Already have an account?", .german: "Bereits ein Konto?", .french: "Vous avez déjà un compte ?",
            .spanish: "¿Ya tienes una cuenta?", .portuguese: "Já tem uma conta?", .italian: "Hai già un account?",
            .arabic: "هل لديك حساب بالفعل؟", .chinese: "已有账号？", .japanese: "すでにアカウントをお持ちですか？", .korean: "이미 계정이 있으신가요?"
        ],
        "Sign In": [
            .english: "Sign In", .german: "Anmelden", .french: "Se connecter",
            .spanish: "Iniciar sesión", .portuguese: "Entrar", .italian: "Accedi",
            .arabic: "تسجيل الدخول", .chinese: "登录", .japanese: "サインイン", .korean: "로그인"
        ],
        "No account?": [
            .english: "No account?", .german: "Noch kein Konto?", .french: "Pas de compte ?",
            .spanish: "¿No tienes cuenta?", .portuguese: "Não tem conta?", .italian: "Non hai un account?",
            .arabic: "ليس لديك حساب؟", .chinese: "没有账号？", .japanese: "アカウントをお持ちでないですか？", .korean: "계정이 없으신가요?"
        ],
        "Register": [
            .english: "Register", .german: "Registrieren", .french: "S'inscrire",
            .spanish: "Registrarse", .portuguese: "Registrar", .italian: "Registrati",
            .arabic: "تسجيل", .chinese: "注册", .japanese: "登録", .korean: "회원가입"
        ],
        "Shared List": [
            .english: "Shared List", .german: "Geteilte Liste", .french: "Liste partagée",
            .spanish: "Lista compartida", .portuguese: "Lista compartilhada", .italian: "Lista condivisa",
            .arabic: "قائمة مشتركة", .chinese: "共享列表", .japanese: "共有リスト", .korean: "공유된 목록"
        ],
        "Failed to leave list": [
            .english: "Failed to leave list", .german: "Liste konnte nicht verlassen werden", .french: "Impossible de quitter la liste",
            .spanish: "Error al salir de la lista", .portuguese: "Falha ao sair da lista", .italian: "Impossibile lasciare la lista",
            .arabic: "فشل في مغادرة القائمة", .chinese: "退出列表失败", .japanese: "リストからの退出に失敗しました", .korean: "목록 나가기에 실패했습니다"
        ],
        "Forgot password?": [
            .english: "Forgot password?", .german: "Passwort vergessen?", .french: "Mot de passe oublié ?",
            .spanish: "¿Olvidaste tu contraseña?", .portuguese: "Esqueceu a senha?", .italian: "Password dimenticata?",
            .arabic: "هل نسيت كلمة المرور؟", .chinese: "忘记密码？", .japanese: "パスワードをお忘れですか？", .korean: "비밀번호를 잊으셨나요?"
        ],
        "Reset your password": [
            .english: "Reset your password", .german: "Passwort zurücksetzen", .french: "Réinitialiser le mot de passe",
            .spanish: "Restablecer contraseña", .portuguese: "Redefinir senha", .italian: "Reimposta la password",
            .arabic: "إعادة تعيين كلمة المرور", .chinese: "重置密码", .japanese: "パスワードを再設定", .korean: "비밀번호 재설정"
        ],
        "Enter your email to receive a recovery link": [
            .english: "Enter your email to receive a recovery link", .german: "Gib deine E-Mail ein, um einen Link zu erhalten", .french: "Entrez votre e-mail pour recevoir un lien",
            .spanish: "Introduce tu correo para recibir un enlace", .portuguese: "Digite seu e-mail para receber um link", .italian: "Inserisci la tua email per ricevere un link",
            .arabic: "أدخل بريدك الإلكتروني لتلقي رابط الاسترداد", .chinese: "输入邮箱以接收重置链接", .japanese: "メールアドレスを入力して再設定リンクを受信", .korean: "복구 링크를 받을 이메일을 입력하세요"
        ],
        "SEND RESET LINK": [
            .english: "SEND RESET LINK", .german: "LINK SENDEN", .french: "ENVOYER LE LIEN",
            .spanish: "ENVIAR ENLACE", .portuguese: "ENVIAR LINK", .italian: "INVIA LINK",
            .arabic: "إرسال الرابط", .chinese: "发送重置链接", .japanese: "再設定リンクを送信", .korean: "재설정 링크 보내기"
        ],
        "Password reset link sent! Check your inbox.": [
            .english: "Password reset link sent! Check your inbox.", .german: "Reset-Link gesendet! Prüfe dein Postfach.", .french: "Lien envoyé ! Vérifiez votre boîte de réception.",
            .spanish: "¡Enlace enviado! Revisa tu bandeja de entrada.", .portuguese: "Link enviado! Verifique sua caixa de entrada.", .italian: "Link inviato! Controlla la tua casella di posta.",
            .arabic: "تم إرسال الرابط! تحقق من بريدك الوارد.", .chinese: "重置链接已发送！请查看您的收件箱。", .japanese: "リンクを送信しました！受信トレイを確認してください。", .korean: "재설정 링크가 전송되었습니다! 받은편지함을 확인하세요."
        ],
        "Back to Sign In": [
            .english: "Back to Sign In", .german: "Zurück zur Anmeldung", .french: "Retour à la connexion",
            .spanish: "Volver a iniciar sesión", .portuguese: "Voltar para o login", .italian: "Torna ad accedi",
            .arabic: "العودة لتسجيل الدخول", .chinese: "返回登录", .japanese: "サインインに戻る", .korean: "로그인으로 돌아가기"
        ],
        "Password must be at least 6 characters": [
            .english: "Password must be at least 6 characters", .german: "Passwort muss mindestens 6 Zeichen lang sein", .french: "Le mot de passe doit comporter au moins 6 caractères",
            .spanish: "La contraseña debe tener al menos 6 caracteres", .portuguese: "A senha deve ter pelo menos 6 caracteres", .italian: "La password deve contenere almeno 6 caratteri",
            .arabic: "يجب أن تتكون كلمة المرور من 6 أحرف على الأقل", .chinese: "密码长度至少为 6 个字符", .japanese: "パスワードは6文字以上である必要があります", .korean: "비밀번호는 6자 이상이어야 합니다"
        ],
        "Set New Password": [
            .english: "Set New Password", .german: "Neues Passwort festlegen", .french: "Définir un nouveau mot de passe",
            .spanish: "Establecer nueva contraseña", .portuguese: "Definir nova senha", .italian: "Imposta nuova password",
            .arabic: "تعيين كلمة مرور جديدة", .chinese: "设置新密码", .japanese: "新しいパスワードを設定", .korean: "새 비밀번호 설정"
        ],
        "Enter your new password below": [
            .english: "Enter your new password below", .german: "Gib dein neues Passwort unten ein", .french: "Entrez votre nouveau mot de passe ci-dessous",
            .spanish: "Introduce tu nueva contraseña abajo", .portuguese: "Digite sua nova senha abaixo", .italian: "Inserisci la tua nuova password qui sotto",
            .arabic: "أدخل كلمة المرور الجديدة أدناه", .chinese: "在下方输入您的新密码", .japanese: "以下に新しいパスワードを入力してください", .korean: "아래에 새 비밀번호를 입력하세요"
        ],
        "SAVE NEW PASSWORD": [
            .english: "SAVE NEW PASSWORD", .german: "NEUES PASSWORT SPEICHERN", .french: "ENREGISTRER LE MOT DE PASSE",
            .spanish: "GUARDAR NUEVA CONTRASEÑA", .portuguese: "SALVAR NOVA SENHA", .italian: "SALVA NUOVA PASSWORD",
            .arabic: "حفظ كلمة المرور الجديدة", .chinese: "保存新密码", .japanese: "新しいパスワードを保存", .korean: "새 비밀번호 저장"
        ],
        "Password updated successfully!": [
            .english: "Password updated successfully!", .german: "Passwort erfolgreich aktualisiert!", .french: "Mot de passe mis à jour avec succès !",
            .spanish: "¡Contraseña actualizada con éxito!", .portuguese: "Senha atualizada com sucesso!", .italian: "Password aggiornata con successo!",
            .arabic: "تم تحديث كلمة المرور بنجاح!", .chinese: "密码更新成功！", .japanese: "パスワードが正常に更新されました！", .korean: "비밀번호가 성공적으로 업데이트되었습니다!"
        ],
        "Passwords do not match": [
            .english: "Passwords do not match", .german: "Passwörter stimmen nicht überein", .french: "Les mots de passe ne correspondent pas",
            .spanish: "Las contraseñas no coinciden", .portuguese: "As senhas não coincidem", .italian: "Le password non corrispondono",
            .arabic: "كلمات المرور غير متطابقة", .chinese: "两次输入的密码不一致", .japanese: "パスワードが一致しません", .korean: "비밀번호가 일치하지 않습니다"
        ],
        "New Password": [
            .english: "New Password", .german: "Neues Passwort", .french: "Nouveau mot de passe",
            .spanish: "Nueva contraseña", .portuguese: "Nova senha", .italian: "Nuova password",
            .arabic: "كلمة المرور الجديدة", .chinese: "新密码", .japanese: "新しいパスワード", .korean: "새 비밀번호"
        ],
        "Confirm Password": [
            .english: "Confirm Password", .german: "Passwort bestätigen", .french: "Confirmer le mot de passe",
            .spanish: "Confirmar contraseña", .portuguese: "Confirmar senha", .italian: "Conferma password",
            .arabic: "تأكيد كلمة المرور", .chinese: "确认密码", .japanese: "パスワードの確認", .korean: "비밀번호 확인"
        ],
        "New password must be different from the old password": [
            .english: "New password must be different from the old password",
            .german: "Das neue Passwort muss sich vom alten Passwort unterscheiden",
            .french: "Le nouveau mot de passe doit être différent de l'ancien",
            .spanish: "La nueva contraseña debe ser diferente de la anterior",
            .portuguese: "A nova senha deve ser diferente da antiga",
            .italian: "La nuova password deve essere diversa da quella precedente",
            .arabic: "يجب أن تكون كلمة المرور الجديدة مختلفة عن القديمة",
            .chinese: "新密码必须与旧密码不同",
            .japanese: "新しいパスワードは古いパスワードと異なる必要があります",
            .korean: "새 비밀번호는 이전 비밀번호와 달라야 합니다"
        ],
        "SOUND LABORATORY": [
            .english: "SOUND LABORATORY", .german: "SOUND-LABOR", .french: "LABORATOIRE SONORE",
            .spanish: "LABORATORIO DE SONIDO", .portuguese: "LABORATÓRIO DE SOM", .italian: "LABORATORIO SUONI",
            .arabic: "مختبر الصوت", .chinese: "声音实验室", .japanese: "サウンドラボ", .korean: "사운드 실험실"
        ],
        "TASK COMPLETION": [
            .english: "TASK COMPLETION", .german: "AUFGABE ERLEDIGEN", .french: "TÂCHE TERMINÉE",
            .spanish: "TAREA COMPLETADA", .portuguese: "TAREFA CONCLUÍDA", .italian: "COMPITO COMPLETATO",
            .arabic: "إتمام المهمة", .chinese: "完成任务", .japanese: "タスク完了", .korean: "작업 완료"
        ],
        "TASK DELETION": [
            .english: "TASK DELETION", .german: "AUFGABE LÖSCHEN", .french: "SUPPRESSION DE TÂCHE",
            .spanish: "ELIMINAR TAREA", .portuguese: "EXCLUIR TAREFA", .italian: "ELIMINAZIONE COMPITO",
            .arabic: "حذف المهمة", .chinese: "删除任务", .japanese: "タスク削除", .korean: "작업 삭제"
        ],
        "TRANSFER & MOVE": [
            .english: "TRANSFER & MOVE", .german: "VERSCHIEBEN & TRANSFER", .french: "TRANSFÉRER & DÉPLACER",
            .spanish: "TRANSFERIR Y MOVER", .portuguese: "TRANSFERIR E MOVER", .italian: "TRASFERISCI E SPOSTA",
            .arabic: "نقل وتحريك", .chinese: "转移与移动", .japanese: "転送と移動", .korean: "전송 및 이동"
        ],
        "RESTORE & UNDO": [
            .english: "RESTORE & UNDO", .german: "WIEDERHERSTELLEN & RÜCKGÄNGIG", .french: "RESTAURER & ANNULER",
            .spanish: "RESTAURAR Y DESHACER", .portuguese: "RESTAURAR E DESFAZER", .italian: "RIPRISTINA E ANNULLA",
            .arabic: "استعادة وتراجع", .chinese: "恢复与撤销", .japanese: "復元と元に戻す", .korean: "복원 및 실행 취소"
        ],
        "TRANSITIONS & MIGRATION": [
            .english: "TRANSITIONS & MIGRATION", .german: "ÜBERGÄNGE & MIGRATION", .french: "TRANSITIONS & MIGRATION",
            .spanish: "TRANSICIONES Y MIGRACIÓN", .portuguese: "TRANSIÇÕES E MIGRAÇÃO", .italian: "TRANSIZIONI E MIGRAZIONE",
            .arabic: "الانتقالات والترحيل", .chinese: "转换与迁移", .japanese: "遷移と移行", .korean: "전환 및 마이그레이션"
        ],
        "HABIT CHECK": [
            .english: "HABIT CHECK", .german: "GEWOHNHEITEN", .french: "HABITUDE",
            .spanish: "HÁBITO", .portuguese: "HÁBITO", .italian: "ABITUDINE",
            .arabic: "العادة", .chinese: "习惯打卡", .japanese: "習慣チェック", .korean: "습관 체크"
        ],
        "Pencil Stroke": [
            .english: "Pencil Stroke", .german: "Bleistift", .french: "Crayon",
            .spanish: "Trazo de lápiz", .portuguese: "Traço de lápis", .italian: "Tratto di matita",
            .arabic: "ضربة قلم", .chinese: "铅笔划线", .japanese: "鉛筆ストローク", .korean: "연필 스트로크"
        ],
        "Wood Switch": [
            .english: "Wood Switch", .german: "Holz-Klick", .french: "Clic bois",
            .spanish: "Clic de madera", .portuguese: "Clique de madeira", .italian: "Clic in legno",
            .arabic: "نقرة خشبية", .chinese: "木质微动", .japanese: "ウッドスイッチ", .korean: "우드 스위치"
        ],
        "Crystal Ding": [
            .english: "Crystal Ding", .german: "Kristallglas", .french: "Teint de cristal",
            .spanish: "Timbre de cristal", .portuguese: "Sino de cristal", .italian: "Tintinnio cristallo",
            .arabic: "رنين بلوري", .chinese: "水晶清音", .japanese: "クリスタルリング", .korean: "크리스탈 딩"
        ],
        "Kalimba Pluck": [
            .english: "Kalimba Pluck", .german: "Kalimba", .french: "Pincement kalimba",
            .spanish: "Punteo kalimba", .portuguese: "Toque de kalimba", .italian: "Tocco kalimba",
            .arabic: "نغمة كاليمبا", .chinese: "卡林巴琴", .japanese: "カリンバ", .korean: "칼림바 플럭"
        ],
        "Deep Sub Tick": [
            .english: "Deep Sub Tick", .german: "Sub-Tick", .french: "Tic sub-basse",
            .spanish: "Sub tic profundo", .portuguese: "Sub-tick profundo", .italian: "Sub tick profondo",
            .arabic: "تكة عميقة", .chinese: "深沉微滴", .japanese: "サブティック", .korean: "딥 서브 틱"
        ],
        "Paper Sweep": [
            .english: "Paper Sweep", .german: "Papier-Wisch", .french: "Balayage papier",
            .spanish: "Barrer papel", .portuguese: "Varredura de papel", .italian: "Fruscio carta",
            .arabic: "مسح الورق", .chinese: "纸张拂动", .japanese: "ペーパースイープ", .korean: "페이퍼 스윕"
        ],
        "Velvet Poof": [
            .english: "Velvet Poof", .german: "Samt-Puff", .french: "Souffle velours",
            .spanish: "Soplo de terciopelo", .portuguese: "Sopro de veludo", .italian: "Soffio di velluto",
            .arabic: "نفخة مخملية", .chinese: "丝绒轻拂", .japanese: "ベルベットプーフ", .korean: "벨벳 푸프"
        ],
        "Parchment Flick": [
            .english: "Parchment Flick", .german: "Pergament-Flick", .french: "Piqure parchemin",
            .spanish: "Toque de pergamino", .portuguese: "Toque de pergaminho", .italian: "Tocco pergamena",
            .arabic: "نفضة رق", .chinese: "羊皮纸弹动", .japanese: "パーチメントフリック", .korean: "양피지 플릭"
        ],
        "Sub Dissolve": [
            .english: "Sub Dissolve", .german: "Sub-Auflösung", .french: "Dissolution douce",
            .spanish: "Disolución suave", .portuguese: "Dissolução suave", .italian: "Dissolvenza morbida",
            .arabic: "تلاشي هادئ", .chinese: "低频消散", .japanese: "サブディゾルブ", .korean: "서브 디졸브"
        ],
        "Velvet Glide": [
            .english: "Velvet Glide", .german: "Sanftes Gleiten", .french: "Glissement velouté",
            .spanish: "Deslizamiento suave", .portuguese: "Deslize suave", .italian: "Scorrimento vellutato",
            .arabic: "انزلاق ناعم", .chinese: "柔和滑动", .japanese: "ベルベットグライド", .korean: "벨벳 글라이드"
        ],
        "Marimba Duo": [
            .english: "Marimba Duo", .german: "Marimba-Duo", .french: "Duo marimba",
            .spanish: "Dúo de marimba", .portuguese: "Duo de marimba", .italian: "Duo marimba",
            .arabic: "ثنائي ماريمبا", .chinese: "马林巴双音", .japanese: "マリンバデュオ", .korean: "마림바 듀오"
        ],
        "Magnetic Dock": [
            .english: "Magnetic Dock", .german: "Magnet-Dock", .french: "Arrimage magnétique",
            .spanish: "Acople magnético", .portuguese: "Encaixe magnético", .italian: "Aggancio magnetico",
            .arabic: "قفل مغناطيسي", .chinese: "磁吸定位", .japanese: "マグネットドック", .korean: "마그네틱 독"
        ],
        "Air Swell": [
            .english: "Air Swell", .german: "Luft-Swell", .french: "Onde aérienne",
            .spanish: "Onda de aire", .portuguese: "Onda de ar", .italian: "Onda d'aria",
            .arabic: "تموج هوائي", .chinese: "空气涌动", .japanese: "エアスウェル", .korean: "에어 스웰"
        ],
        "Reverse Whoosh": [
            .english: "Reverse Whoosh", .german: "Rückwärts-Whoosh", .french: "Souffle inversé",
            .spanish: "Zumbido inverso", .portuguese: "Zumbido reverso", .italian: "Fruscio inverso",
            .arabic: "اندفاع عكسي", .chinese: "反向回溯", .japanese: "リバースフーシュ", .korean: "리버스 후쉬"
        ],
        "Rebound Pop": [
            .english: "Rebound Pop", .german: "Rebound-Pop", .french: "Rebondissement",
            .spanish: "Rebote ágil", .portuguese: "Ressalto ágil", .italian: "Rimbalzo pop",
            .arabic: "ارتداد خفيف", .chinese: "回弹轻音", .japanese: "リバウンドポップ", .korean: "리바운드 팝"
        ],
        "Paper Unfold": [
            .english: "Paper Unfold", .german: "Papier entfalten", .french: "Déplier papier",
            .spanish: "Desplegar papel", .portuguese: "Desdobrar papel", .italian: "Spiegare carta",
            .arabic: "فتح الورقة", .chinese: "展开纸张", .japanese: "ペーパーアンフォールド", .korean: "종이 펼치기"
        ],
        "Elastic Snap": [
            .english: "Elastic Snap", .german: "Elastischer Snap", .french: "Claquement élastique",
            .spanish: "Chasquido elástico", .portuguese: "Estalido elástico", .italian: "Scatto elastico",
            .arabic: "طقطقة مرنة", .chinese: "弹性吸附", .japanese: "エラスティックスナップ", .korean: "탄성 스냅"
        ],
        "Singing Bowl": [
            .english: "Singing Bowl", .german: "Klangschale", .french: "Bol chantant",
            .spanish: "Cuenco tibetano", .portuguese: "Taça tibetana", .italian: "Campana tibetana",
            .arabic: "وعاء الغناء", .chinese: "颂钵余音", .japanese: "シンギングボウル", .korean: "싱잉볼"
        ],
        "Kalimba Echo": [
            .english: "Kalimba Echo", .german: "Kalimba-Echo", .french: "Écho kalimba",
            .spanish: "Eco de kalimba", .portuguese: "Eco de kalimba", .italian: "Eco kalimba",
            .arabic: "صدى كاليمبا", .chinese: "卡林巴回声", .japanese: "カリンバエコー", .korean: "칼림바 에코"
        ],
        "Crystal Chime": [
            .english: "Crystal Chime", .german: "Kristall-Glocke", .french: "Carillon de cristal",
            .spanish: "Campana de cristal", .portuguese: "Sino de cristal", .italian: "Campanella cristallo",
            .arabic: "جرس بلوري", .chinese: "水晶风铃", .japanese: "クリスタルチャイム", .korean: "크리스탈 차임"
        ],
        "Bamboo Tap": [
            .english: "Bamboo Tap", .german: "Bambus-Tap", .french: "Frappe bambou",
            .spanish: "Toque de bambú", .portuguese: "Toque de bambu", .italian: "Tocco bambù",
            .arabic: "نقرة خيزران", .chinese: "竹音轻叩", .japanese: "バンブータップ", .korean: "대나무 탭"
        ],
        "Water Droplet": [
            .english: "Water Droplet", .german: "Wassertropfen", .french: "Goutte d'eau",
            .spanish: "Gota de agua", .portuguese: "Gota d'água", .italian: "Goccia d'acqua",
            .arabic: "قطرة ماء", .chinese: "清澈水滴", .japanese: "ウォータードロップ", .korean: "물방울"
        ],
        "Harmonic Bell": [
            .english: "Harmonic Bell", .german: "Harmonische Glocke", .french: "Cloche harmonique",
            .spanish: "Campana armónica", .portuguese: "Sino harmônico", .italian: "Campana armonica",
            .arabic: "جرس متناغم", .chinese: "和声铃音", .japanese: "ハーモニックベル", .korean: "하모닉 벨"
        ],
        "NOTIFICATIONS": [
            .english: "NOTIFICATIONS", .german: "MITTEILUNGEN", .french: "NOTIFICATIONS",
            .spanish: "NOTIFICACIONES", .portuguese: "NOTIFICAÇÕES", .italian: "NOTIFICHE",
            .arabic: "الإشعارات", .chinese: "通知", .japanese: "通知", .korean: "알림"
        ],
        "Migration Notifications": [
            .english: "Migration Notifications", .german: "Migrations-Mitteilungen", .french: "Notifications de migration",
            .spanish: "Notificaciones de migración", .portuguese: "Notificações de migração", .italian: "Notifiche di migrazione",
            .arabic: "إشعارات الترحيل", .chinese: "迁移提醒通知", .japanese: "移行通知", .korean: "마이그레이션 알림"
        ],
        "Notifications are disabled in System Settings.": [
            .english: "Notifications are disabled in System Settings.",
            .german: "Mitteilungen sind in den Systemeinstellungen deaktiviert.",
            .french: "Les notifications sont désactivées dans les Réglages Système.",
            .spanish: "Las notificaciones están desactivadas en Ajustes del Sistema.",
            .portuguese: "As notificações estão desativadas nos Ajustes do Sistema.",
            .italian: "Le notifiche sono disattivate nelle Impostazioni di Sistema.",
            .arabic: "تم تعطيل الإشعارات في إعدادات النظام.",
            .chinese: "通知已在系统设置中被禁用。",
            .japanese: "システム設定で通知が無効になっています。",
            .korean: "시스템 설정에서 알림이 비활성화되어 있습니다."
        ],
        "Open System Settings": [
            .english: "Open System Settings", .german: "Systemeinstellungen öffnen", .french: "Ouvrir les Réglages Système",
            .spanish: "Abrir Ajustes del Sistema", .portuguese: "Abrir Ajustes do Sistema", .italian: "Apri Impostazioni di Sistema",
            .arabic: "فتح إعدادات النظام", .chinese: "打开系统设置", .japanese: "システム設定を開く", .korean: "시스템 설정 열기"
        ],
        "Hour Migration Ready": [
            .english: "Hour Migration Ready", .german: "Stunden-Migration bereit", .french: "Migration horaire prête",
            .spanish: "Migración de hora lista", .portuguese: "Migração horária pronta", .italian: "Migrazione oraria pronta",
            .arabic: "الترحيل بالساعة جاهز", .chinese: "小时迁移已就绪", .japanese: "時間移行の準備完了", .korean: "시간 마이그레이션 준비됨"
        ],
        "Time to choose your tasks for the upcoming hour.": [
            .english: "Time to choose your tasks for the upcoming hour.",
            .german: "Zeit, deine Aufgaben für die nächste Stunde auszuwählen.",
            .french: "Il est temps de choisir vos tâches pour l'heure à venir.",
            .spanish: "Es hora de elegir tus tareas para la próxima hora.",
            .portuguese: "Hora de escolher suas tarefas para a próxima hora.",
            .italian: "È ora di scegliere i compiti per la prossima ora.",
            .arabic: "حان الوقت لاختيار مهامك للساعة القادمة.",
            .chinese: "该选择下一小时要完成的任务了。",
            .japanese: "次の1時間のタスクを選択する時間です。",
            .korean: "다음 1시간 동안 진행할 작업을 선택할 시간입니다."
        ],
        "Day Migration Ready": [
            .english: "Day Migration Ready", .german: "Tages-Migration bereit", .french: "Migration quotidienne prête",
            .spanish: "Migración diaria lista", .portuguese: "Migração diária pronta", .italian: "Migrazione giornaliera pronta",
            .arabic: "الترحيل اليومي جاهز", .chinese: "每日迁移已就绪", .japanese: "日次移行の準備完了", .korean: "일일 마이그레이션 준비됨"
        ],
        "Plan your tasks for today.": [
            .english: "Plan your tasks for today.", .german: "Plane deine Aufgaben für den heutigen Tag.", .french: "Planifiez vos tâches pour aujourd'hui.",
            .spanish: "Planifica tus tareas para hoy.", .portuguese: "Planeje suas tarefas para hoje.", .italian: "Pianifica i tuoi compiti per oggi.",
            .arabic: "خطط لمهامك لهذا اليوم.", .chinese: "规划您今天的任务。", .japanese: "今日のタスクを計画しましょう。", .korean: "오늘의 작업을 계획하세요."
        ],
        "Week Migration Ready": [
            .english: "Week Migration Ready", .german: "Wochen-Migration bereit", .french: "Migration hebdomadaire prête",
            .spanish: "Migración semanal lista", .portuguese: "Migração semanal pronta", .italian: "Migrazione settimanale pronta",
            .arabic: "الترحيل الأسبوعي جاهز", .chinese: "每周迁移已就绪", .japanese: "週次移行の準備完了", .korean: "주간 마이그레이션 준비됨"
        ],
        "Review and organize your week.": [
            .english: "Review and organize your week.", .german: "Überprüfe und plane deine neue Woche.", .french: "Passez en revue et organisez votre semaine.",
            .spanish: "Revisa y organiza tu semana.", .portuguese: "Revise e organize sua semana.", .italian: "Rivedi e organizza la tua settimana.",
            .arabic: "راجع ونظم أسبوعك.", .chinese: "回顾并规划新的一周。", .japanese: "週のタスクを確認して整理しましょう。", .korean: "한 주를 검토하고 정리하세요."
        ],
        "Month Migration Ready": [
            .english: "Month Migration Ready", .german: "Monats-Migration bereit", .french: "Migration mensuelle prête",
            .spanish: "Migración mensual lista", .portuguese: "Migração mensal pronta", .italian: "Migrazione mensile pronta",
            .arabic: "الترحيل الشهري جاهز", .chinese: "每月迁移已就绪", .japanese: "月次移行の準備完了", .korean: "월간 마이그레이션 준비됨"
        ],
        "Set your priorities for the new month.": [
            .english: "Set your priorities for the new month.", .german: "Setze deine Prioritäten für den neuen Monat.", .french: "Définissez vos priorités pour le nouveau mois.",
            .spanish: "Establece tus prioridades para el nuevo mes.", .portuguese: "Defina suas prioridades para o novo mês.", .italian: "Imposta le tue priorità per il nuovo mese.",
            .arabic: "حدد أولوياتك للشهر الجديد.", .chinese: "设定新月份的优先事项。", .japanese: "新しい月の優先順位を設定しましょう。", .korean: "새로운 달의 우선순위를 정하세요."
        ],
        "Year Migration Ready": [
            .english: "Year Migration Ready", .german: "Jahres-Migration bereit", .french: "Migration annuelle prête",
            .spanish: "Migración anual lista", .portuguese: "Migração anual pronta", .italian: "Migrazione annuale pronta",
            .arabic: "الترحيل السنوي جاهز", .chinese: "年度迁移已就绪", .japanese: "年次移行の準備完了", .korean: "연간 마이그레이션 준비됨"
        ],
        "Review your year and set new goals.": [
            .english: "Review your year and set new goals.", .german: "Blicke auf das Jahr zurück und setze neue Ziele.", .french: "Passez en revue votre année et fixez de nouveaux objectifs.",
            .spanish: "Revisa tu año y establece nuevas metas.", .portuguese: "Revise seu ano e defina novas metas.", .italian: "Rivedi il tuo anno e stabilisci nuovi obiettivi.",
            .arabic: "راجع عامك وحدد أهدافًا جديدة.", .chinese: "回顾您的一年并设定新目标。", .japanese: "1年を振り返り、新しい目標を設定しましょう。", .korean: "한 해를 돌아보고 새로운 목표를 설정하세요."
        ],
        "Migration Ready": [
            .english: "Migration Ready", .german: "Migration bereit", .french: "Migration prête",
            .spanish: "Migración lista", .portuguese: "Migração pronta", .italian: "Migrazione pronta",
            .arabic: "الترحيل جاهز", .chinese: "迁移已就绪", .japanese: "移行の準備完了", .korean: "마이그레이션 준비됨"
        ],
        "New interval migration is available.": [
            .english: "New interval migration is available.", .german: "Neue Intervall-Migration ist verfügbar.", .french: "Une nouvelle migration d'intervalle est disponible.",
            .spanish: "Nueva migración de intervalo disponible.", .portuguese: "Nova migração de intervalo disponível.", .italian: "Nuova migrazione di intervallo disponibile.",
            .arabic: "ترحيل فاصل زمني جديد متاح.", .chinese: "新的区间迁移已可用。", .japanese: "新しいインターバル移行が利用可能です。", .korean: "새로운 간격 마이그레이션을 사용할 수 있습니다."
        ]
    ]
}

extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}

extension NSNotification.Name {
    static let promptPasswordUpdate = NSNotification.Name("promptPasswordUpdate")
}
