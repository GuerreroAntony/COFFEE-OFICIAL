import SwiftUI

struct ChatTabView: View {
    let disciplina: Disciplina

    var body: some View {
        ChatView(disciplinaId: disciplina.id, disciplinaNome: disciplina.nome)
    }
}
