import SwiftUI

struct DisciplinasListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = DisciplinasViewModel()
    @State private var showNovaDisciplina = false
    @State private var showProfileMenu = false

    var body: some View {
        NavigationStack {
            ZStack {
                CoffeeTheme.Colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("olá, \(authViewModel.currentUser?.nome.components(separatedBy: " ").first ?? "aluno")")
                                .font(.system(size: 17))
                                .foregroundColor(CoffeeTheme.Colors.almond)

                            Text("suas disciplinas")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(CoffeeTheme.Colors.espresso)
                        }

                        Spacer()

                        Button { showNovaDisciplina = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(CoffeeTheme.Colors.coffee)
                        }
                        .padding(.trailing, CoffeeTheme.Spacing.sm)

                        Button { showProfileMenu = true } label: {
                            Circle()
                                .fill(CoffeeTheme.Colors.vanilla)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(authViewModel.currentUser?.nome.prefix(1) ?? "?"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(CoffeeTheme.Colors.espresso)
                                )
                        }
                    }
                    .padding(.horizontal, CoffeeTheme.Spacing.lg)
                    .padding(.top, CoffeeTheme.Spacing.lg)
                    .padding(.bottom, CoffeeTheme.Spacing.md)

                    // Content
                    if viewModel.isLoading && viewModel.disciplinas.isEmpty {
                        LoadingView()
                    } else if viewModel.disciplinas.isEmpty {
                        VStack(spacing: CoffeeTheme.Spacing.lg) {
                            EmptyStateView(
                                icon: "link.badge.plus",
                                title: "nenhuma disciplina encontrada",
                                subtitle: "conecte o portal ESPM para importar sua grade"
                            )
                            NavigationLink(destination: ESPMConnectView(onSuccess: {
                                Task { await viewModel.loadDisciplinas() }
                            })) {
                                CoffeeButton(title: "conectar portal ESPM") {}
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, CoffeeTheme.Spacing.lg)
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: CoffeeTheme.Spacing.sm) {
                                ForEach(Array(viewModel.disciplinas.enumerated()), id: \.element.id) { index, disciplina in
                                    NavigationLink(destination: DisciplinaDetailView(disciplina: disciplina)) {
                                        DisciplinaCard(disciplina: disciplina, index: index)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, CoffeeTheme.Spacing.lg)
                            .padding(.bottom, CoffeeTheme.Spacing.lg)
                        }
                        .refreshable {
                            await viewModel.loadDisciplinas()
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.loadDisciplinas() }
            .sheet(isPresented: $showNovaDisciplina) {
                NovaDisciplinaView(viewModel: viewModel)
            }
            .confirmationDialog(
                authViewModel.currentUser?.nome ?? "perfil",
                isPresented: $showProfileMenu,
                titleVisibility: .visible
            ) {
                Button("sair da conta", role: .destructive) {
                    authViewModel.logout()
                }
                Button("cancelar", role: .cancel) {}
            }
        }
    }
}
