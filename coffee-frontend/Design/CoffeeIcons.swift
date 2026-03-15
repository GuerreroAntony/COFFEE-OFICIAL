import SwiftUI

// MARK: - SF Symbols Mapping
// Maps all 56+ Material Symbols Outlined icons used in React to SF Symbols

enum CoffeeIcon {
    // Navigation
    static let back = "chevron.left"
    static let forward = "chevron.right"
    static let close = "xmark"
    static let expandMore = "chevron.down"
    static let expandLess = "chevron.up"
    static let moreHoriz = "ellipsis"

    // Tabs
    static let home = "book"                          // book_2
    static let record = "mic.fill"                    // mic
    static let barista = "sparkles"                   // auto_awesome

    // Actions
    static let add = "plus"
    static let addCircle = "plus.circle"
    static let removeCircle = "minus.circle.fill"
    static let share = "square.and.arrow.up"          // ios_share
    static let download = "arrow.down.circle"
    static let send = "arrow.up"                      // arrow_upward
    static let edit = "square.and.pencil"             // edit_note
    static let sync = "arrow.triangle.2.circlepath"
    static let search = "magnifyingglass.circle"      // manage_search
    static let gift = "gift.fill"

    // Recording
    static let mic = "mic.fill"
    static let pause = "pause.fill"
    static let play = "play.fill"
    static let playCircle = "play.circle.fill"
    static let stop = "stop.fill"
    static let stopCircle = "stop.circle.fill"
    static let camera = "camera.fill"                 // photo_camera
    static let videoCamera = "video.fill"             // video_camera_back
    static let waveform = "waveform"                  // graphic_eq
    static let forward10 = "goforward.10"
    static let replay10 = "gobackward.10"
    static let headphones = "headphones"

    // Education
    static let school = "graduationcap"
    static let discipline = "text.book.closed"        // auto_stories
    static let notes = "note.text"
    static let description = "doc.text"

    // AI / Chat
    static let sparkles = "sparkles"                  // auto_awesome
    static let bolt = "bolt.fill"                     // Espresso mode
    static let brain = "brain"                        // psychology / Cold Brew
    static let chat = "bubble.left"
    static let chatBubble = "bubble.left.fill"
    static let history = "clock.arrow.circlepath"

    // Course / Content
    static let mindMap = "chart.dots.scatter"         // account_tree
    static let hub = "point.3.connected.trianglepath.dotted"
    static let layers = "square.3.layers.3d"
    static let image = "photo"
    static let pdf = "doc.richtext"                   // picture_as_pdf
    static let folder = "folder"
    static let folderSpecial = "folder.badge.star"
    static let createFolder = "folder.badge.plus"     // create_new_folder
    static let menuBook = "book.pages"                // menu_book

    // Profile / Settings
    static let person = "person.fill"
    static let group = "person.2"
    static let groups = "person.3"
    static let settings = "gearshape.fill"
    static let logout = "rectangle.portrait.and.arrow.right"
    static let lock = "lock.fill"
    static let shield = "lock.shield"                 // security / privacy
    static let mail = "envelope"
    static let info = "info.circle"
    static let creditCard = "creditcard"
    static let qrCode = "qrcode"                     // qr_code_2

    // Status
    static let checkCircle = "checkmark.circle.fill"
    static let check = "checkmark"
    static let warning = "exclamationmark.triangle.fill"
    static let error = "exclamationmark.circle.fill"
    static let schedule = "clock"
    static let deleteForever = "trash.fill"
    static let confirmation = "ticket"                // confirmation_number

    // Cancel Reasons
    static let payments = "banknote"                  // Caro
    static let eventBusy = "calendar.badge.minus"     // Não uso
    static let thumbDown = "hand.thumbsdown"          // Inadequado
    static let bugReport = "ladybug"                  // Problemas técnicos
    static let cancel = "xmark.circle"

    // Misc
    static let allInclusive = "infinity"
    static let sentimentSad = "face.smiling.inverse"
    static let copyright = "c.circle"
    static let trendingUp = "chart.line.uptrend.xyaxis"  // Marketing icon
    static let monitoring = "chart.line.uptrend.xyaxis"  // Economics icon
    static let quiz = "questionmark.circle"
    static let fullscreen = "arrow.up.left.and.arrow.down.right"
}
