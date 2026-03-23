import SwiftUI

// MARK: - Friend Detail Sheet
// Shows shared recordings between the current user and a friend

struct FriendDetailSheet: View {
    let friend: Friend

    @Environment(\.dismiss) private var dismiss
    @State private var sharedItems: [SharedItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Grab indicator
            Capsule()
                .fill(Color.coffeeTextSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Header
            HStack {
                Spacer()
                Text(friend.nome.components(separatedBy: " ").first ?? friend.nome)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: {
                    Text("Fechar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.coffeePrimary)
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if sharedItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.coffeeTextSecondary.opacity(0.4))
                    Text("Nenhuma aula compartilhada")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.coffeeTextSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sharedItems.enumerated()), id: \.element.id) { index, item in
                            friendShareRow(item)
                            if index < sharedItems.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color.coffeeCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .background(Color.coffeeBackground)
        .presentationDetents([.medium, .large])
        .task {
            await loadShares()
        }
    }

    private func friendShareRow(_ item: SharedItem) -> some View {
        HStack(spacing: 12) {
            // Date column
            VStack(spacing: 1) {
                let parts = item.gravacao.date.prefix(10).split(separator: "-")
                if parts.count >= 3 {
                    Text(String(parts[2]))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.coffeePrimary)
                    Text(Self.monthAbbrev(String(parts[1])))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.coffeeTextSecondary)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coffeePrimary)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.sourceDiscipline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.coffeeTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("por")
                        .foregroundStyle(Color.coffeeTextSecondary)
                    Text(item.sender.nome.components(separatedBy: " ").first ?? item.sender.nome)
                        .foregroundStyle(Color.coffeePrimary)
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }

            Spacer()

            if item.status == .pending {
                Button {
                    acceptShare(item)
                } label: {
                    Text("Salvar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.coffeePrimary)
                        .clipShape(Capsule())
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coffeeSuccess)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    static func monthAbbrev(_ m: String) -> String {
        switch m {
        case "01": return "JAN"
        case "02": return "FEV"
        case "03": return "MAR"
        case "04": return "ABR"
        case "05": return "MAI"
        case "06": return "JUN"
        case "07": return "JUL"
        case "08": return "AGO"
        case "09": return "SET"
        case "10": return "OUT"
        case "11": return "NOV"
        case "12": return "DEZ"
        default: return m
        }
    }

    private func acceptShare(_ item: SharedItem) {
        guard let sourceType = item.sourceType,
              let sourceId = item.sourceId else {
            print("[FriendDetail] Missing source info for accept")
            return
        }
        Task {
            do {
                let body = AcceptShareRequest(
                    destinationType: sourceType,
                    destinationId: sourceId
                )
                let _: AcceptShareResponse = try await APIClient.shared.request(
                    path: APIEndpoints.compartilhamentoAccept(id: item.id),
                    method: .POST,
                    body: body
                )
                await loadShares()
            } catch {
                print("[FriendDetail] Accept failed: \(error)")
            }
        }
    }

    private func loadShares() async {
        isLoading = true
        do {
            // group_id=none → only direct shares (not via group)
            let all: [SharedItem] = try await APIClient.shared.request(
                path: "\(APIEndpoints.compartilhamentosReceived)?group_id=none"
            )
            // Filter to only shares from this friend
            sharedItems = all.filter { $0.sender.nome == friend.nome }
        } catch {
            print("[FriendDetail] Failed to load shares: \(error)")
        }
        isLoading = false
    }
}
