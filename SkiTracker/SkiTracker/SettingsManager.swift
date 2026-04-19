import Foundation
import Combine

// MARK: - Language

enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case chinese = "zh"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case italian = "it"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        }
    }
}

// MARK: - Unit System

enum UnitSystem: String, CaseIterable, Codable {
    case metric = "metric"
    case imperial = "imperial"

    var displayName: String {
        switch self {
        case .metric: return "Metric (km/h, m)"
        case .imperial: return "Imperial (mph, ft)"
        }
    }

    var speedUnit: String {
        switch self {
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }

    var distanceUnit: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    var altitudeUnit: String {
        switch self {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }
}

// MARK: - Localized Strings

struct LocalizedStrings {
    let language: AppLanguage

    private func tr(
        en: String,
        zh: String,
        es: String,
        ja: String,
        ko: String,
        fr: String,
        de: String,
        it: String
    ) -> String {
        switch language {
        case .english: return en
        case .chinese: return zh
        case .spanish: return es
        case .japanese: return ja
        case .korean: return ko
        case .french: return fr
        case .german: return de
        case .italian: return it
        }
    }

    // Navigation & Titles
    var appTitle: String {
        tr(en: "Ski Tracker", zh: "滑雪追踪器", es: "Rastreador de Esqui", ja: "スキートラッカー", ko: "스키 트래커", fr: "Suivi Ski", de: "Ski-Tracker", it: "Tracciatore Sci")
    }

    var history: String {
        tr(en: "History", zh: "历史记录", es: "Historial", ja: "履歴", ko: "기록", fr: "Historique", de: "Verlauf", it: "Cronologia")
    }

    var settings: String {
        tr(en: "Settings", zh: "设置", es: "Configuracion", ja: "設定", ko: "설정", fr: "Reglages", de: "Einstellungen", it: "Impostazioni")
    }

    // Permissions
    var locationPermissionNeeded: String {
        language == .chinese ? "需要定位权限才能记录滑雪轨迹" : "Location permission required to track skiing"
    }

    var authorizeLocation: String {
        language == .chinese ? "授权定位" : "Authorize Location"
    }

    var locationPermissionSectionTitle: String {
        tr(en: "Location Permission", zh: "定位权限", es: "Permiso de ubicacion", ja: "位置情報の許可", ko: "위치 권한", fr: "Autorisation de localisation", de: "Standortberechtigung", it: "Permesso posizione")
    }

    var requestAlwaysAccess: String {
        tr(en: "Request Always Access", zh: "申请“始终允许”", es: "Solicitar acceso siempre", ja: "常に許可をリクエスト", ko: "항상 허용 요청", fr: "Demander acces permanent", de: "Immer-Zugriff anfordern", it: "Richiedi accesso sempre")
    }

    var goToSettings: String {
        language == .chinese ? "前往设置开启定位" : "Go to Settings to Enable Location"
    }

    var locationServicesDisabled: String {
        language == .chinese ? "系统定位服务已关闭。请在系统设置中开启定位服务。" : "Location Services are turned off. Enable them in iPhone Settings."
    }

    var locationTrackingDenied: String {
        language == .chinese ? "定位权限不可用，已停止记录。请前往系统设置开启定位权限。" : "Location access was denied and tracking has stopped. Enable location permission in Settings."
    }

    var locationBackgroundAccessRecommended: String {
        language == .chinese ? "当前仅“使用期间”允许定位。若切到后台或锁屏可能停止记录，建议在设置中开启“始终允许”。" : "Location is set to While Using. Tracking may stop in background or when locked. Enable Always access in Settings."
    }

    // Auth Status
    var authNotRequested: String {
        language == .chinese ? "未请求" : "Not Requested"
    }

    var authRestricted: String {
        language == .chinese ? "受限" : "Restricted"
    }

    var authDenied: String {
        language == .chinese ? "已拒绝" : "Denied"
    }

    var authWhenInUse: String {
        language == .chinese ? "使用时允许" : "When In Use"
    }

    var authAlways: String {
        language == .chinese ? "始终允许" : "Always"
    }

    var authUnknown: String {
        language == .chinese ? "未知" : "Unknown"
    }

    // Tracking
    var startSkiing: String {
        tr(en: "Start Recording", zh: "开始记录", es: "Iniciar grabacion", ja: "記録開始", ko: "기록 시작", fr: "Demarrer l'enregistrement", de: "Aufzeichnung starten", it: "Avvia registrazione")
    }

    var stopRecording: String {
        tr(en: "Stop Recording", zh: "停止录制", es: "Detener grabacion", ja: "記録停止", ko: "기록 중지", fr: "Arreter l'enregistrement", de: "Aufzeichnung stoppen", it: "Ferma registrazione")
    }

    var pauseRecording: String {
        tr(en: "Pause Recording", zh: "暂停录制", es: "Pausar grabacion", ja: "記録一時停止", ko: "기록 일시정지", fr: "Mettre en pause", de: "Aufzeichnung pausieren", it: "Metti in pausa")
    }

    var resumeRecording: String {
        tr(en: "Resume Recording", zh: "继续录制", es: "Reanudar grabacion", ja: "記録再開", ko: "기록 재개", fr: "Reprendre l'enregistrement", de: "Aufzeichnung fortsetzen", it: "Riprendi registrazione")
    }

    var paused: String {
        tr(en: "Paused", zh: "已暂停", es: "Pausado", ja: "一時停止", ko: "일시정지", fr: "En pause", de: "Pausiert", it: "In pausa")
    }

    var recording: String {
        tr(en: "Recording", zh: "录制中", es: "Grabando", ja: "記録中", ko: "기록 중", fr: "Enregistrement", de: "Aufnahme", it: "Registrazione")
    }

    var points: String {
        language == .chinese ? "点" : "pts"
    }

    // Stop Confirmation
    var stopConfirmTitle: String {
        tr(en: "Stop Recording?", zh: "停止录制？", es: "¿Detener grabacion?", ja: "記録を停止しますか？", ko: "기록을 중지할까요?", fr: "Arreter l'enregistrement ?", de: "Aufzeichnung beenden?", it: "Interrompere la registrazione?")
    }

    var stopConfirmMessage: String {
        tr(en: "Current track will be saved. You can review it in history.", zh: "当前轨迹将被保存，你可以在历史记录中回看。", es: "El recorrido actual se guardara. Puedes revisarlo en el historial.", ja: "現在の軌跡は保存され、履歴で確認できます。", ko: "현재 트랙이 저장되며 기록에서 확인할 수 있습니다.", fr: "La trace actuelle sera enregistree. Vous pourrez la consulter dans l'historique.", de: "Die aktuelle Strecke wird gespeichert. Du kannst sie im Verlauf ansehen.", it: "La traccia corrente verra salvata. Potrai rivederla nella cronologia.")
    }

    var continueRecording: String {
        tr(en: "Continue", zh: "继续录制", es: "Continuar", ja: "続ける", ko: "계속", fr: "Continuer", de: "Fortsetzen", it: "Continua")
    }

    var stopAndSave: String {
        tr(en: "Stop & Save", zh: "停止并保存", es: "Detener y guardar", ja: "停止して保存", ko: "중지하고 저장", fr: "Arreter et enregistrer", de: "Stoppen und speichern", it: "Ferma e salva")
    }

    // Stats
    var duration: String {
        tr(en: "Duration", zh: "时长", es: "Duracion", ja: "時間", ko: "시간", fr: "Duree", de: "Dauer", it: "Durata")
    }

    var distance: String {
        tr(en: "Distance", zh: "距离", es: "Distancia", ja: "距離", ko: "거리", fr: "Distance", de: "Distanz", it: "Distanza")
    }

    var maxSpeed: String {
        tr(en: "Max Speed", zh: "最高速度", es: "Velocidad maxima", ja: "最高速度", ko: "최고 속도", fr: "Vitesse max", de: "Max. Geschwindigkeit", it: "Velocita massima")
    }

    var avgSpeed: String {
        tr(en: "Avg Speed", zh: "平均速度", es: "Velocidad media", ja: "平均速度", ko: "평균 속도", fr: "Vitesse moyenne", de: "Durchschnittsgeschwindigkeit", it: "Velocita media")
    }

    var maxAltitude: String {
        tr(en: "Max Altitude", zh: "最高海拔", es: "Altitud maxima", ja: "最高高度", ko: "최고 고도", fr: "Altitude max", de: "Maximale Hohe", it: "Altitudine massima")
    }

    var elevationDrop: String {
        tr(en: "Elevation Drop", zh: "海拔落差", es: "Desnivel", ja: "標高差", ko: "고도 하강", fr: "Denivele", de: "Hohenunterschied", it: "Dislivello")
    }

    var trackPoints: String {
        tr(en: "Track Points", zh: "轨迹点数", es: "Puntos de traza", ja: "トラックポイント", ko: "트랙 포인트", fr: "Points de trace", de: "Track-Punkte", it: "Punti traccia")
    }

    // History
    var close: String {
        tr(en: "Close", zh: "关闭", es: "Cerrar", ja: "閉じる", ko: "닫기", fr: "Fermer", de: "Schliessen", it: "Chiudi")
    }

    var noHistory: String {
        language == .chinese ? "暂无历史记录" : "No History"
    }

    var noHistoryMessage: String {
        language == .chinese ? "完成一次滑雪录制后，数据将自动保存在此处" : "Complete a skiing session to see it here"
    }

    var currentLocation: String {
        language == .chinese ? "当前位置" : "Current Location"
    }

    var deleteAll: String {
        language == .chinese ? "删除全部" : "Delete All"
    }

    var delete: String {
        tr(en: "Delete", zh: "删除", es: "Eliminar", ja: "削除", ko: "삭제", fr: "Supprimer", de: "Loschen", it: "Elimina")
    }

    var deleteConfirmTitle: String {
        language == .chinese ? "删除此记录？" : "Delete this record?"
    }

    var deleteAllConfirmTitle: String {
        language == .chinese ? "删除全部记录？" : "Delete all records?"
    }

    var deleteConfirmMessage: String {
        language == .chinese ? "此操作无法撤销" : "This action cannot be undone"
    }

    var cancel: String {
        tr(en: "Cancel", zh: "取消", es: "Cancelar", ja: "キャンセル", ko: "취소", fr: "Annuler", de: "Abbrechen", it: "Annulla")
    }

    // Settings
    var languageLabel: String {
        tr(en: "Language", zh: "语言", es: "Idioma", ja: "言語", ko: "언어", fr: "Langue", de: "Sprache", it: "Lingua")
    }

    var unitsLabel: String {
        tr(en: "Units", zh: "单位", es: "Unidades", ja: "単位", ko: "단위", fr: "Unites", de: "Einheiten", it: "Unita")
    }

    var metricLabel: String {
        tr(en: "Metric", zh: "公制", es: "Metrico", ja: "メートル法", ko: "미터법", fr: "Metrique", de: "Metrisch", it: "Metrico")
    }

    var imperialLabel: String {
        tr(en: "Imperial", zh: "英制", es: "Imperial", ja: "ヤード・ポンド法", ko: "야드파운드법", fr: "Imperial", de: "Imperial", it: "Imperiale")
    }

    var performanceModeTitle: String {
        tr(
            en: "Faster Sampling",
            zh: "更快采样",
            es: "Muestreo rapido",
            ja: "高速サンプリング",
            ko: "고속 샘플링",
            fr: "Echantillonnage rapide",
            de: "Schnelleres Sampling",
            it: "Campionamento rapido"
        )
    }

    var performanceModeDescription: String {
        tr(
            en: "Capture location updates more frequently to better catch speed peaks (uses more battery).",
            zh: "更频繁采集定位更新，更容易捕捉速度峰值（更耗电）。",
            es: "Captura ubicaciones con mayor frecuencia para detectar mejor los picos de velocidad (consume mas bateria).",
            ja: "位置更新をより高頻度で取得し、速度ピークを捉えやすくします（バッテリー消費増）。",
            ko: "위치 업데이트 빈도를 높여 속도 피크를 더 잘 포착합니다(배터리 사용 증가).",
            fr: "Capture les positions plus frequemment pour mieux detecter les pics de vitesse (consomme plus de batterie).",
            de: "Erfasst Standortdaten haufiger, um Geschwindigkeits-Spitzen besser zu erkennen (hoherer Akkuverbrauch).",
            it: "Acquisisce la posizione piu spesso per rilevare meglio i picchi di velocita (consuma piu batteria)."
        )
    }

    var performanceSection: String {
        tr(en: "Performance", zh: "性能", es: "Rendimiento", ja: "パフォーマンス", ko: "성능", fr: "Performance", de: "Leistung", it: "Prestazioni")
    }

    var supportTitle: String {
        tr(en: "Support the Developer", zh: "支持开发者", es: "Apoya al desarrollador", ja: "開発者をサポート", ko: "개발자 후원", fr: "Soutenir le developpeur", de: "Entwickler unterstutzen", it: "Supporta lo sviluppatore")
    }

    var supportHeadline: String {
        tr(en: "If this app made your ski day better, buy me a coffee.", zh: "如果这个 App 很有用，请请我喝杯咖啡。", es: "Si esta app mejoro tu dia de ski, invitame un cafe.", ja: "このアプリが役立ったら、コーヒーで応援してください。", ko: "이 앱이 유용했다면 커피 한 잔으로 응원해 주세요.", fr: "Si cette app a ameliore votre journee de ski, offrez-moi un cafe.", de: "Wenn diese App deinen Skitag verbessert hat, spendiere mir einen Kaffee.", it: "Se questa app ha migliorato la tua giornata sugli sci, offrimi un caffe.")
    }

    var supportFootnote: String {
        tr(en: "One-time tip. No subscription.", zh: "一次性打赏，无订阅。", es: "Propina unica. Sin suscripcion.", ja: "1回のみの支援。サブスクなし。", ko: "일회성 후원입니다. 구독 없음.", fr: "Pourboire unique. Pas d'abonnement.", de: "Einmaliges Trinkgeld. Kein Abo.", it: "Mancia una tantum. Nessun abbonamento.")
    }

    var supportSmallTip: String {
        tr(en: "Black Coffee", zh: "美式咖啡", es: "Cafe negro", ja: "ブラックコーヒー", ko: "블랙 커피", fr: "Cafe noir", de: "Schwarzer Kaffee", it: "Caffe nero")
    }

    var supportLargeTip: String {
        tr(en: "Cappuccino", zh: "卡布奇诺", es: "Capuchino", ja: "カプチーノ", ko: "카푸치노", fr: "Cappuccino", de: "Cappuccino", it: "Cappuccino")
    }

    var supportThankYou: String {
        tr(en: "Thanks for the support. It helps me keep improving the app.", zh: "感谢支持，这会帮助我继续改进这个 App。", es: "Gracias por el apoyo. Me ayuda a mejorar la app.", ja: "ご支援ありがとうございます。アプリ改善の励みになります。", ko: "후원 감사합니다. 앱을 계속 개선하는 데 큰 도움이 됩니다.", fr: "Merci pour votre soutien. Cela m'aide a ameliorer l'app.", de: "Danke fur die Unterstutzung. Das hilft mir, die App weiter zu verbessern.", it: "Grazie per il supporto. Mi aiuta a migliorare continuamente l'app.")
    }

    var supportPending: String {
        tr(en: "Payment is pending.", zh: "付款正在处理中。", es: "Pago pendiente.", ja: "支払い処理中です。", ko: "결제가 처리 중입니다.", fr: "Paiement en attente.", de: "Zahlung ausstehend.", it: "Pagamento in attesa.")
    }

    var supportUnavailable: String {
        tr(en: "Tips are unavailable right now. Try again later.", zh: "打赏暂不可用。请稍后再试。", es: "Las propinas no estan disponibles ahora. Intenta mas tarde.", ja: "現在はチップをご利用いただけません。後でお試しください。", ko: "지금은 후원을 사용할 수 없습니다. 나중에 다시 시도해 주세요.", fr: "Les pourboires sont indisponibles pour le moment. Reessayez plus tard.", de: "Trinkgelder sind derzeit nicht verfugbar. Bitte spater erneut versuchen.", it: "Le mance non sono disponibili ora. Riprova piu tardi.")
    }

    var supportPurchaseFailed: String {
        tr(en: "Purchase did not complete.", zh: "支付未完成。", es: "La compra no se completo.", ja: "購入は完了しませんでした。", ko: "구매가 완료되지 않았습니다.", fr: "L'achat n'a pas abouti.", de: "Kauf wurde nicht abgeschlossen.", it: "L'acquisto non e stato completato.")
    }

    // Day Summary
    var daySummary: String {
        tr(en: "Day Summary", zh: "当日总结", es: "Resumen del dia", ja: "1日のサマリー", ko: "일일 요약", fr: "Resume du jour", de: "Tageszusammenfassung", it: "Riepilogo giornata")
    }

    var runs: String {
        tr(en: "Runs", zh: "趟数", es: "Bajadas", ja: "ラン数", ko: "런 수", fr: "Descentes", de: "Abfahrten", it: "Discese")
    }

    var totalDistance: String {
        tr(en: "Total Distance", zh: "总距离", es: "Distancia total", ja: "総距離", ko: "총 거리", fr: "Distance totale", de: "Gesamtdistanz", it: "Distanza totale")
    }

    var totalDuration: String {
        tr(en: "Total Duration", zh: "总时长", es: "Duracion total", ja: "総時間", ko: "총 시간", fr: "Duree totale", de: "Gesamtdauer", it: "Durata totale")
    }

    var totalDescent: String {
        tr(en: "Total Descent", zh: "总下降", es: "Descenso total", ja: "総下降", ko: "총 하강", fr: "Denivele total", de: "Gesamtabfahrt", it: "Discesa totale")
    }

    var maxDescentRun: String {
        tr(en: "Max Descent (Single Run)", zh: "单趟最大落差", es: "Max descenso (una bajada)", ja: "最大落差（単一ラン）", ko: "최대 낙차(단일 런)", fr: "Denivele max (une descente)", de: "Max. Hohenunterschied (eine Abfahrt)", it: "Dislivello max (singola discesa)")
    }

    var fastestRun: String {
        tr(en: "Fastest Run", zh: "最快一趟", es: "Bajada mas rapida", ja: "最速ラン", ko: "가장 빠른 런", fr: "Descente la plus rapide", de: "Schnellste Abfahrt", it: "Discesa piu veloce")
    }

    var avgSpeedDay: String {
        tr(en: "Avg Speed", zh: "平均速度", es: "Velocidad media", ja: "平均速度", ko: "평균 속도", fr: "Vitesse moyenne", de: "Durchschnittsgeschwindigkeit", it: "Velocita media")
    }

    var maxSpeedDay: String {
        tr(en: "Max Speed", zh: "最高速度", es: "Velocidad maxima", ja: "最高速度", ko: "최고 속도", fr: "Vitesse max", de: "Max. Geschwindigkeit", it: "Velocita massima")
    }

    var longestRun: String {
        tr(en: "Longest Run", zh: "最长一趟", es: "Bajada mas larga", ja: "最長ラン", ko: "최장 런", fr: "Plus longue descente", de: "Langste Abfahrt", it: "Discesa piu lunga")
    }

    var avgRunDistance: String {
        tr(en: "Avg Distance/Run", zh: "平均每趟距离", es: "Distancia media/bajada", ja: "平均距離/ラン", ko: "런당 평균 거리", fr: "Distance moy./descente", de: "Durchschnittsdistanz/Abfahrt", it: "Distanza media/discesa")
    }

    var runsCount: String {
        tr(en: "runs", zh: "趟", es: "bajadas", ja: "本", ko: "회", fr: "descentes", de: "Abfahrten", it: "discese")
    }

    var sessionsCount: String {
        tr(en: "sessions", zh: "次记录", es: "sesiones", ja: "セッション", ko: "세션", fr: "sessions", de: "Sitzungen", it: "sessioni")
    }

    var monthsLabel: String {
        tr(en: "months", zh: "个月", es: "meses", ja: "か月", ko: "개월", fr: "mois", de: "Monate", it: "mesi")
    }

    var daysLabel: String {
        tr(en: "days", zh: "天", es: "dias", ja: "日", ko: "일", fr: "jours", de: "Tage", it: "giorni")
    }

    var unknownResort: String {
        tr(en: "Unknown Resort", zh: "未知雪场", es: "Estacion desconocida", ja: "不明なスキー場", ko: "알 수 없는 리조트", fr: "Station inconnue", de: "Unbekanntes Skigebiet", it: "Comprensorio sconosciuto")
    }

    // Authentication
    var signIn: String {
        tr(en: "Sign In", zh: "登录", es: "Iniciar sesion", ja: "サインイン", ko: "로그인", fr: "Se connecter", de: "Anmelden", it: "Accedi")
    }

    var signOut: String {
        tr(en: "Sign Out", zh: "退出登录", es: "Cerrar sesion", ja: "サインアウト", ko: "로그아웃", fr: "Se deconnecter", de: "Abmelden", it: "Esci")
    }

    var signInWithApple: String {
        tr(en: "Sign in with Apple", zh: "使用 Apple 登录", es: "Iniciar con Apple", ja: "Appleでサインイン", ko: "Apple로 로그인", fr: "Se connecter avec Apple", de: "Mit Apple anmelden", it: "Accedi con Apple")
    }

    var signInWithGoogle: String {
        tr(en: "Sign in with Google", zh: "使用 Google 登录", es: "Iniciar con Google", ja: "Googleでサインイン", ko: "Google로 로그인", fr: "Se connecter avec Google", de: "Mit Google anmelden", it: "Accedi con Google")
    }

    var welcomeMessage: String {
        tr(en: "Sign in to sync your ski data", zh: "登录以同步您的滑雪数据", es: "Inicia sesion para sincronizar tus datos", ja: "ログインしてデータを同期", ko: "로그인하여 스키 데이터를 동기화", fr: "Connectez-vous pour synchroniser vos donnees", de: "Anmelden, um Daten zu synchronisieren", it: "Accedi per sincronizzare i dati")
    }

    var syncData: String {
        language == .chinese ? "同步数据" : "Sync Data"
    }

    var syncing: String {
        language == .chinese ? "同步中..." : "Syncing..."
    }

    var lastSynced: String {
        language == .chinese ? "上次同步" : "Last synced"
    }

    var account: String {
        tr(en: "Account", zh: "账户", es: "Cuenta", ja: "アカウント", ko: "계정", fr: "Compte", de: "Konto", it: "Account")
    }

    var signedInAs: String {
        language == .chinese ? "已登录为" : "Signed in as"
    }

    var continueAsGuest: String {
        tr(en: "Continue as Guest", zh: "暂不登录", es: "Continuar como invitado", ja: "ゲストとして続行", ko: "게스트로 계속", fr: "Continuer en invite", de: "Als Gast fortfahren", it: "Continua come ospite")
    }

    var dataStoredLocally: String {
        language == .chinese ? "数据仅保存在本地" : "Data stored locally only"
    }

    var signInToSync: String {
        language == .chinese ? "登录以同步到云端" : "Sign in to sync to cloud"
    }

    // Run Segmentation
    var currentState: String {
        language == .chinese ? "当前状态" : "Current State"
    }

    var stateIdle: String {
        tr(en: "Idle", zh: "空闲", es: "Inactivo", ja: "待機", ko: "대기", fr: "Inactif", de: "Inaktiv", it: "Inattivo")
    }

    var stateSkiing: String {
        tr(en: "Skiing", zh: "滑行中", es: "Esquiando", ja: "滑走中", ko: "스키 중", fr: "Ski", de: "Skifahren", it: "Sciando")
    }

    var stateLift: String {
        tr(en: "On Lift", zh: "缆车上行", es: "En telesilla", ja: "リフト乗車中", ko: "리프트 탑승", fr: "Sur le telesiege", de: "Im Lift", it: "In risalita")
    }

    var stateStopped: String {
        tr(en: "Stopped", zh: "停止", es: "Detenido", ja: "停止", ko: "정지", fr: "Arrete", de: "Gestoppt", it: "Fermo")
    }

    var runsCompleted: String {
        tr(en: "Runs Completed", zh: "已完成趟数", es: "Bajadas completadas", ja: "完了ラン数", ko: "완료한 런", fr: "Descentes terminees", de: "Abfahrten abgeschlossen", it: "Discese completate")
    }

    var liftsCompleted: String {
        tr(en: "Lifts Taken", zh: "缆车次数", es: "Subidas en lift", ja: "リフト利用回数", ko: "리프트 탑승 수", fr: "Remontees prises", de: "Liftfahrten", it: "Risalite effettuate")
    }

    var verticalDrop: String {
        tr(en: "Vertical Drop", zh: "累计下降", es: "Desnivel vertical", ja: "累計落差", ko: "누적 낙차", fr: "Denivele vertical", de: "Hohenunterschied", it: "Dislivello verticale")
    }

    var runDetails: String {
        language == .chinese ? "单趟详情" : "Run Details"
    }

    var runPlayback: String {
        language == .chinese ? "滑行回放" : "Run Playback"
    }

    var dayPlayback: String {
        tr(en: "Day Playback", zh: "全天回放", es: "Reproduccion del dia", ja: "1日回放", ko: "하루 재생", fr: "Replay de la journee", de: "Tageswiedergabe", it: "Replay della giornata")
    }

    var sessionPlayback: String {
        tr(en: "Session Replay", zh: "会话回放", es: "Reproduccion de sesion", ja: "セッション回放", ko: "세션 리플레이", fr: "Replay de session", de: "Sitzungswiedergabe", it: "Replay sessione")
    }

    var play: String {
        tr(en: "Play", zh: "播放", es: "Reproducir", ja: "再生", ko: "재생", fr: "Lire", de: "Abspielen", it: "Riproduci")
    }

    var pause: String {
        tr(en: "Pause", zh: "暂停", es: "Pausa", ja: "一時停止", ko: "일시정지", fr: "Pause", de: "Pause", it: "Pausa")
    }

    var reset: String {
        tr(en: "Reset", zh: "重置", es: "Restablecer", ja: "リセット", ko: "초기화", fr: "Reinitialiser", de: "Zurucksetzen", it: "Reimposta")
    }

    var noTrackData: String {
        tr(en: "No track data", zh: "暂无轨迹数据", es: "Sin datos de recorrido", ja: "トラックデータなし", ko: "트랙 데이터 없음", fr: "Aucune donnee de trace", de: "Keine Trackdaten", it: "Nessun dato traccia")
    }

    var segmentType: String {
        tr(en: "Type", zh: "类型", es: "Tipo", ja: "タイプ", ko: "유형", fr: "Type", de: "Typ", it: "Tipo")
    }

    var deleteRunConfirmTitle: String {
        language == .chinese ? "删除此趟？" : "Delete this run?"
    }

    var deleteRunConfirmMessage: String {
        language == .chinese ? "此数据将被永久删除" : "This data will be permanently deleted"
    }

    var startAltitude: String {
        language == .chinese ? "起始海拔" : "Start Altitude"
    }

    var endAltitude: String {
        language == .chinese ? "结束海拔" : "End Altitude"
    }

    // Leaderboard
    var leaderboard: String {
        tr(en: "Leaderboard", zh: "排行榜", es: "Clasificacion", ja: "ランキング", ko: "리더보드", fr: "Classement", de: "Bestenliste", it: "Classifica")
    }

    var leaderboardCategoryMax: String {
        tr(en: "Max Records", zh: "最高纪录", es: "Mejores marcas", ja: "最高記録", ko: "최고 기록", fr: "Meilleurs records", de: "Bestwerte", it: "Record massimi")
    }

    var leaderboardCategoryMost: String {
        tr(en: "Most Records", zh: "最多纪录", es: "Mas registros", ja: "最多記録", ko: "최다 기록", fr: "Plus de records", de: "Meiste Rekorde", it: "Piu record")
    }

    var leaderboardOlympicBoard: String {
        tr(en: "Olympic Board", zh: "奥运榜单", es: "Podio olimpico", ja: "オリンピックボード", ko: "올림픽 보드", fr: "Podium olympique", de: "Olympia-Podium", it: "Podio olimpico")
    }

    var leaderboardFullRank: String {
        tr(en: "Full Ranking", zh: "完整排名", es: "Clasificacion completa", ja: "全順位", ko: "전체 순위", fr: "Classement complet", de: "Vollstandige Rangliste", it: "Classifica completa")
    }

    var rankBy: String {
        tr(en: "Rank By", zh: "排名指标", es: "Ordenar por", ja: "並び替え", ko: "정렬 기준", fr: "Classer par", de: "Rang nach", it: "Classifica per")
    }

    var leaderboardNoData: String {
        tr(en: "No leaderboard data yet", zh: "暂无排行榜数据", es: "Aun no hay datos de clasificacion", ja: "ランキングデータがありません", ko: "리더보드 데이터가 없습니다", fr: "Pas encore de donnees de classement", de: "Noch keine Bestenlisten-Daten", it: "Nessun dato classifica disponibile")
    }

    var leaderboardSingleUserHint: String {
        tr(en: "No friends yet, so the leaderboard currently shows only you.", zh: "当前没有好友，排行榜仅显示你自己。", es: "Aun no tienes amigos, por ahora solo apareces tu.", ja: "まだ友達がいないため、現在はあなたのみ表示されます。", ko: "아직 친구가 없어 현재는 본인만 표시됩니다.", fr: "Pas encore d'amis, le classement n'affiche que vous.", de: "Noch keine Freunde, daher wird nur du angezeigt.", it: "Ancora nessun amico, la classifica mostra solo te.")
    }

    var leaderboardFriendsOnlyHint: String {
        tr(en: "Only mutual friends are shown.", zh: "仅显示已互加好友的用户。", es: "Solo se muestran amigos mutuos.", ja: "相互フォローの友達のみ表示されます。", ko: "상호 친구만 표시됩니다.", fr: "Seuls les amis mutuels sont affiches.", de: "Es werden nur gegenseitige Freunde angezeigt.", it: "Sono mostrati solo amici reciproci.")
    }

    var leaderboardSyncTimeout: String {
        tr(en: "Leaderboard sync timed out. Showing local data.", zh: "排行榜同步超时，已显示本地数据。", es: "Tiempo de sincronizacion agotado. Mostrando datos locales.", ja: "ランキング同期がタイムアウトしました。ローカルデータを表示中。", ko: "리더보드 동기화 시간 초과. 로컬 데이터를 표시합니다.", fr: "Delai de synchro depasse. Affichage des donnees locales.", de: "Bestenlisten-Synchronisierung hat zu lange gedauert. Lokale Daten werden angezeigt.", it: "Sincronizzazione classifica scaduta. Mostro dati locali.")
    }

    var leaderboardMetricTopSpeed: String {
        tr(en: "Top Speed", zh: "最高速度", es: "Velocidad maxima", ja: "最高速度", ko: "최고 속도", fr: "Vitesse max", de: "Top-Speed", it: "Velocita massima")
    }

    var leaderboardMetricTopRunDescent: String {
        tr(en: "Top Run Descent", zh: "单趟最大落差", es: "Mayor desnivel por bajada", ja: "1本の最大落差", ko: "단일 런 최대 낙차", fr: "Plus grand denivele d'une descente", de: "Großter Abfahrt-Hohenunterschied", it: "Maggior dislivello per discesa")
    }

    var leaderboardMetricMaxAltitude: String {
        tr(en: "Max Altitude", zh: "最高海拔", es: "Altitud maxima", ja: "最高高度", ko: "최고 고도", fr: "Altitude max", de: "Maximale Hohe", it: "Altitudine massima")
    }

    var leaderboardMetricLongestRun: String {
        tr(en: "Longest Run", zh: "最长单趟距离", es: "Bajada mas larga", ja: "最長ラン", ko: "최장 런", fr: "Plus longue descente", de: "Langste Abfahrt", it: "Discesa piu lunga")
    }

    var leaderboardMetricTotalDistance: String {
        tr(en: "Total Distance", zh: "总滑行距离", es: "Distancia total", ja: "総距離", ko: "총 거리", fr: "Distance totale", de: "Gesamtdistanz", it: "Distanza totale")
    }

    var leaderboardMetricRunCount: String {
        tr(en: "Run Count", zh: "总趟数", es: "Numero de bajadas", ja: "ラン回数", ko: "런 횟수", fr: "Nombre de descentes", de: "Anzahl der Abfahrten", it: "Numero discese")
    }

    var leaderboardMetricTotalVerticalDrop: String {
        tr(en: "Total Vertical Drop", zh: "总下降", es: "Desnivel total", ja: "総落差", ko: "총 낙차", fr: "Denivele total", de: "Gesamter Hohenunterschied", it: "Dislivello totale")
    }

    var leaderboardMetricTotalDuration: String {
        tr(en: "Total Duration", zh: "总时长", es: "Duracion total", ja: "総時間", ko: "총 시간", fr: "Duree totale", de: "Gesamtdauer", it: "Durata totale")
    }

    var youLabel: String {
        language == .chinese ? "我" : "You"
    }

    // Friends
    var friends: String {
        tr(en: "Friends", zh: "好友", es: "Amigos", ja: "友達", ko: "친구", fr: "Amis", de: "Freunde", it: "Amici")
    }

    var myFriendQR: String {
        tr(en: "My Friend QR Code", zh: "我的好友二维码", es: "Mi codigo QR de amigo", ja: "マイフレンドQRコード", ko: "내 친구 QR 코드", fr: "Mon QR ami", de: "Mein Freundes-QR-Code", it: "Il mio QR amico")
    }

    var addFriend: String {
        tr(en: "Add Friend", zh: "添加好友", es: "Agregar amigo", ja: "友達を追加", ko: "친구 추가", fr: "Ajouter un ami", de: "Freund hinzufugen", it: "Aggiungi amico")
    }

    var enterFriendCodeOrLink: String {
        tr(en: "Enter friend code or invite link", zh: "输入好友邀请码或链接", es: "Ingresa codigo o enlace de invitacion", ja: "招待コードまたはリンクを入力", ko: "친구 코드 또는 초대 링크 입력", fr: "Saisissez le code ou lien d'invitation", de: "Freundescode oder Einladungslink eingeben", it: "Inserisci codice amico o link invito")
    }

    var addByCodeOrLink: String {
        tr(en: "Add by Code/Link", zh: "通过邀请码/链接添加", es: "Agregar por codigo/enlace", ja: "コード/リンクで追加", ko: "코드/링크로 추가", fr: "Ajouter par code/lien", de: "Per Code/Link hinzufugen", it: "Aggiungi con codice/link")
    }

    var scanFriendQRCode: String {
        language == .chinese ? "扫描好友二维码" : "Scan Friend QR"
    }

    var shareInviteLink: String {
        language == .chinese ? "分享邀请链接" : "Share Invite Link"
    }

    var copyInviteLink: String {
        language == .chinese ? "复制邀请链接" : "Copy Invite Link"
    }

    var inviteLinkCopied: String {
        language == .chinese ? "邀请链接已复制" : "Invite link copied"
    }

    var loadingFriends: String {
        tr(en: "Loading friends...", zh: "加载好友中...", es: "Cargando amigos...", ja: "友達を読み込み中...", ko: "친구 불러오는 중...", fr: "Chargement des amis...", de: "Freunde werden geladen...", it: "Caricamento amici...")
    }

    var noFriendsYet: String {
        tr(en: "No friends yet. Share your QR to add friends.", zh: "还没有好友，先分享你的二维码吧。", es: "Aun no tienes amigos. Comparte tu QR para agregarlos.", ja: "まだ友達がいません。QRを共有して追加しましょう。", ko: "아직 친구가 없습니다. QR을 공유해 친구를 추가하세요.", fr: "Pas encore d'amis. Partagez votre QR pour en ajouter.", de: "Noch keine Freunde. Teile deinen QR-Code, um Freunde hinzuzufugen.", it: "Ancora nessun amico. Condividi il tuo QR per aggiungerli.")
    }

    var signInToManageFriends: String {
        tr(en: "Please sign in to manage friends.", zh: "请先登录后管理好友。", es: "Inicia sesion para gestionar amigos.", ja: "友達管理にはログインが必要です。", ko: "친구 관리를 위해 로그인하세요.", fr: "Connectez-vous pour gerer les amis.", de: "Bitte anmelden, um Freunde zu verwalten.", it: "Accedi per gestire gli amici.")
    }

    var friendInviteSavedSignInNeeded: String {
        language == .chinese ? "已收到好友邀请，登录后会自动添加。" : "Friend invite received. Sign in to add automatically."
    }

    var friendInvalidInvite: String {
        language == .chinese ? "无效的好友邀请码或链接" : "Invalid friend invite code or link"
    }

    var friendCannotAddSelf: String {
        language == .chinese ? "不能添加自己为好友" : "You cannot add yourself as a friend"
    }

    var friendAccountNotFound: String {
        language == .chinese ? "未找到该账号" : "That account was not found"
    }

    var friendAdded: String {
        language == .chinese ? "已添加好友" : "Friend added"
    }

    var friendRequestSent: String {
        tr(en: "Friend request sent", zh: "好友请求已发送", es: "Solicitud de amistad enviada", ja: "友達リクエストを送信しました", ko: "친구 요청을 보냈습니다", fr: "Demande d'ami envoyee", de: "Freundschaftsanfrage gesendet", it: "Richiesta di amicizia inviata")
    }

    var friendRequestAccepted: String {
        tr(en: "Friend request accepted", zh: "已接受好友请求", es: "Solicitud de amistad aceptada", ja: "友達リクエストを承認しました", ko: "친구 요청을 수락했습니다", fr: "Demande d'ami acceptee", de: "Freundschaftsanfrage angenommen", it: "Richiesta di amicizia accettata")
    }

    var friendIncomingRequest: String {
        tr(en: "Incoming request", zh: "收到好友请求", es: "Solicitud recibida", ja: "受信したリクエスト", ko: "받은 요청", fr: "Demande recue", de: "Eingehende Anfrage", it: "Richiesta in arrivo")
    }

    var friendOutgoingRequest: String {
        tr(en: "Request sent", zh: "请求已发送", es: "Solicitud enviada", ja: "送信済み", ko: "요청 보냄", fr: "Demande envoyee", de: "Anfrage gesendet", it: "Richiesta inviata")
    }

    var friendHiddenFromCompetition: String {
        tr(en: "Friend hidden from competition.", zh: "已在排行榜中隐藏该好友。", es: "Amigo ocultado de la competicion.", ja: "フレンドをランキングから非表示にしました。", ko: "친구를 경쟁에서 숨겼습니다.", fr: "Ami masque du classement.", de: "Freund im Wettbewerb ausgeblendet.", it: "Amico nascosto dalla competizione.")
    }

    var friendShownInCompetition: String {
        tr(en: "Friend shown in competition.", zh: "已在排行榜中显示该好友。", es: "Amigo mostrado en la competicion.", ja: "フレンドをランキングに表示しました。", ko: "친구를 경쟁에 다시 표시했습니다.", fr: "Ami affiche dans le classement.", de: "Freund im Wettbewerb wieder sichtbar.", it: "Amico mostrato nella competizione.")
    }

    var friendRemoved: String {
        tr(en: "Friend removed.", zh: "好友已删除。", es: "Amigo eliminado.", ja: "フレンドを削除しました。", ko: "친구를 삭제했습니다.", fr: "Ami supprime.", de: "Freund entfernt.", it: "Amico rimosso.")
    }

    var friendHiddenBadge: String {
        tr(en: "Hidden from competition", zh: "已从排行榜隐藏", es: "Oculto de la competicion", ja: "ランキングで非表示", ko: "경쟁에서 숨김", fr: "Masque du classement", de: "Im Wettbewerb ausgeblendet", it: "Nascosto dalla competizione")
    }

    var hide: String {
        tr(en: "Hide", zh: "隐藏", es: "Ocultar", ja: "非表示", ko: "숨기기", fr: "Masquer", de: "Ausblenden", it: "Nascondi")
    }

    var unhide: String {
        tr(en: "Unhide", zh: "取消隐藏", es: "Mostrar", ja: "再表示", ko: "숨김 해제", fr: "Afficher", de: "Einblenden", it: "Mostra")
    }

    var accept: String {
        tr(en: "Accept", zh: "接受", es: "Aceptar", ja: "承认", ko: "수락", fr: "Accepter", de: "Annehmen", it: "Accetta")
    }

    var decline: String {
        tr(en: "Decline", zh: "拒绝", es: "Rechazar", ja: "拒否", ko: "거절", fr: "Refuser", de: "Ablehnen", it: "Rifiuta")
    }

    var friendOfflineQueued: String {
        language == .chinese ? "当前离线，好友邀请已保存，联网后会自动重试。" : "You are offline. Friend invite was saved and will retry automatically when online."
    }

    var friendOfflineRefresh: String {
        tr(en: "You are offline. Reconnect and refresh friends.", zh: "当前离线，请联网后刷新好友列表。", es: "Estas sin conexion. Vuelve a conectarte y actualiza amigos.", ja: "オフラインです。接続後に友達を更新してください。", ko: "오프라인 상태입니다. 연결 후 친구 목록을 새로고침하세요.", fr: "Vous etes hors ligne. Reconnectez-vous et actualisez les amis.", de: "Du bist offline. Verbinde dich erneut und aktualisiere Freunde.", it: "Sei offline. Riconnettiti e aggiorna gli amici.")
    }

    var cameraPermissionRequired: String {
        language == .chinese ? "需要相机权限以扫描二维码。请在系统设置中开启。" : "Camera permission is required to scan QR codes. Enable it in Settings."
    }

    // Heart Rate (local only)
    var maxHeartRate: String {
        language == .chinese ? "最高心率" : "Max Heart Rate"
    }

    var avgHeartRate: String {
        language == .chinese ? "平均心率" : "Avg Heart Rate"
    }

    var heartRateUnit: String {
        "bpm"
    }

    var waitingHeartRateData: String {
        language == .chinese
            ? "正在等待 Apple Watch 心率同步，请确认手表佩戴正常，并已在 iPhone 的「健康」里允许本应用读取心率。"
            : "Waiting for Apple Watch heart-rate sync. Confirm watch is worn and Health permissions allow heart-rate read for this app."
    }

    func welcomeToResortArea(_ resort: String) -> String {
        switch language {
        case .english:
            return "Welcome to the \(resort) area"
        case .chinese:
            return "欢迎来到\(resort)区域"
        case .spanish:
            return "Bienvenido al area de \(resort)"
        case .japanese:
            return "\(resort)エリアへようこそ"
        case .korean:
            return "\(resort) 지역에 오신 것을 환영합니다"
        case .french:
            return "Bienvenue dans la zone de \(resort)"
        case .german:
            return "Willkommen im Gebiet \(resort)"
        case .italian:
            return "Benvenuto nell'area di \(resort)"
        }
    }

    // Feedback
    var feedbackTitle: String {
        tr(en: "Feedback", zh: "意见反馈", es: "Comentarios", ja: "フィードバック", ko: "피드백", fr: "Retour", de: "Feedback", it: "Feedback")
    }

    var feedbackButton: String {
        tr(en: "Send Feedback", zh: "发送反馈", es: "Enviar comentarios", ja: "フィードバック送信", ko: "피드백 보내기", fr: "Envoyer un retour", de: "Feedback senden", it: "Invia feedback")
    }

    var feedbackDescription: String {
        tr(en: "Share your suggestions or report issues", zh: "告诉我们您的建议或遇到的问题", es: "Comparte sugerencias o reporta problemas", ja: "ご意見や問題点をお知らせください", ko: "제안이나 문제를 공유해 주세요", fr: "Partagez vos suggestions ou problemes", de: "Teile Vorschlage oder Probleme", it: "Condividi suggerimenti o segnala problemi")
    }

    var feedbackPlaceholder: String {
        tr(en: "Enter your feedback here...", zh: "请输入您的意见或建议...", es: "Escribe aqui tus comentarios...", ja: "ここにフィードバックを入力...", ko: "여기에 피드백을 입력하세요...", fr: "Saisissez votre retour ici...", de: "Feedback hier eingeben...", it: "Inserisci qui il tuo feedback...")
    }

    var feedbackSending: String {
        tr(en: "Sending...", zh: "发送中...", es: "Enviando...", ja: "送信中...", ko: "전송 중...", fr: "Envoi...", de: "Senden...", it: "Invio...")
    }

    var feedbackSent: String {
        tr(en: "Thank you for your feedback!", zh: "感谢您的反馈！", es: "Gracias por tus comentarios.", ja: "フィードバックありがとうございます。", ko: "피드백 감사합니다.", fr: "Merci pour votre retour.", de: "Danke fur dein Feedback.", it: "Grazie per il tuo feedback.")
    }

    var feedbackFailed: String {
        tr(en: "Failed to send. Please try again later.", zh: "发送失败，请稍后重试", es: "Error al enviar. Intenta de nuevo mas tarde.", ja: "送信に失敗しました。後でもう一度お試しください。", ko: "전송 실패. 잠시 후 다시 시도해 주세요.", fr: "Echec de l'envoi. Reessayez plus tard.", de: "Senden fehlgeschlagen. Bitte spater erneut versuchen.", it: "Invio non riuscito. Riprova piu tardi.")
    }

    var feedbackEmpty: String {
        tr(en: "Please enter your feedback", zh: "请输入反馈内容", es: "Ingresa tus comentarios", ja: "フィードバックを入力してください", ko: "피드백 내용을 입력해 주세요", fr: "Veuillez saisir votre retour", de: "Bitte Feedback eingeben", it: "Inserisci il feedback")
    }

    var feedbackDailyLimitExceeded: String {
        tr(en: "Daily limit reached (3/day). Please try again tomorrow.", zh: "今日反馈次数已达上限（3次），请明天再试。", es: "Limite diario alcanzado (3/dia). Intenta manana.", ja: "1日の上限（3件）に達しました。明日お試しください。", ko: "일일 한도(3회)에 도달했습니다. 내일 다시 시도하세요.", fr: "Limite quotidienne atteinte (3/jour). Reessayez demain.", de: "Tageslimit erreicht (3/Tag). Bitte morgen erneut versuchen.", it: "Limite giornaliero raggiunto (3/giorno). Riprova domani.")
    }

    var feedbackAddScreenshots: String {
        tr(en: "Add screenshots (up to 2)", zh: "添加截图（最多2张）", es: "Agregar capturas (hasta 2)", ja: "スクリーンショットを追加（最大2枚）", ko: "스크린샷 추가(최대 2장)", fr: "Ajouter des captures (max 2)", de: "Screenshots hinzufugen (max. 2)", it: "Aggiungi screenshot (max 2)")
    }

    // Run Detail Cards
    var timeTitle: String {
        tr(en: "Time", zh: "时间", es: "Tiempo", ja: "時間", ko: "시간", fr: "Temps", de: "Zeit", it: "Tempo")
    }

    var speedTitle: String {
        tr(en: "Speed", zh: "速度", es: "Velocidad", ja: "速度", ko: "속도", fr: "Vitesse", de: "Geschwindigkeit", it: "Velocita")
    }

    var altitudeTitle: String {
        tr(en: "Altitude", zh: "海拔", es: "Altitud", ja: "高度", ko: "고도", fr: "Altitude", de: "Hoehe", it: "Altitudine")
    }

    var heartRateTitle: String {
        tr(en: "Heart Rate", zh: "心率", es: "Frecuencia cardiaca", ja: "心拍数", ko: "심박수", fr: "Frequence cardiaque", de: "Herzfrequenz", it: "Frequenza cardiaca")
    }

    var runLabel: String {
        tr(en: "Run", zh: "滑行", es: "Bajada", ja: "ラン", ko: "런", fr: "Descente", de: "Abfahrt", it: "Discesa")
    }

    var windowLabel: String {
        tr(en: "Window", zh: "时间段", es: "Intervalo", ja: "時間帯", ko: "시간 구간", fr: "Plage horaire", de: "Zeitfenster", it: "Fascia oraria")
    }
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app_language")
        }
    }

    @Published var unitSystem: UnitSystem {
        didSet {
            UserDefaults.standard.set(unitSystem.rawValue, forKey: "unit_system")
        }
    }

    @Published var performanceModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(performanceModeEnabled, forKey: "performance_mode_enabled")
        }
    }

    var strings: LocalizedStrings {
        LocalizedStrings(language: language)
    }

    private init() {
        // Load saved preferences
        if let langRaw = UserDefaults.standard.string(forKey: "app_language"),
           let lang = AppLanguage(rawValue: langRaw) {
            self.language = lang
        } else {
            // Default based on system locale
            let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
            if systemLang.starts(with: "zh") {
                self.language = .chinese
            } else if systemLang.starts(with: "es") {
                self.language = .spanish
            } else if systemLang.starts(with: "ja") {
                self.language = .japanese
            } else if systemLang.starts(with: "ko") {
                self.language = .korean
            } else if systemLang.starts(with: "fr") {
                self.language = .french
            } else if systemLang.starts(with: "de") {
                self.language = .german
            } else if systemLang.starts(with: "it") {
                self.language = .italian
            } else {
                self.language = .english
            }
        }

        if let unitRaw = UserDefaults.standard.string(forKey: "unit_system"),
           let unit = UnitSystem(rawValue: unitRaw) {
            self.unitSystem = unit
        } else {
            // Default based on system locale (US uses imperial)
            let region = Locale.current.region?.identifier ?? ""
            self.unitSystem = (region == "US") ? .imperial : .metric
        }

        self.performanceModeEnabled = UserDefaults.standard.bool(forKey: "performance_mode_enabled")
    }

    // MARK: - Unit Conversions

    /// Convert km/h to current unit
    func formatSpeed(_ kmh: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f", kmh)
        case .imperial:
            return String(format: "%.1f", kmh * 0.621371)
        }
    }

    /// Convert km to current unit
    func formatDistance(_ km: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.2f", km)
        case .imperial:
            return String(format: "%.2f", km * 0.621371)
        }
    }

    /// Convert meters to current unit
    func formatAltitude(_ meters: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.0f", meters)
        case .imperial:
            return String(format: "%.0f", meters * 3.28084)
        }
    }
}
