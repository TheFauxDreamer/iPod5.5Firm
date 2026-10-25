import AppKit
import IPodFWKit
import SwiftUI

// The pane of the games. The pane reads the file of the keys of the connected
// iPod and the games in the folder games_RO of the iPod. The pane shows the
// accounts of the Apple ID and the key of each account. The pane shows the key
// of each game.

struct GamesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Label("The app does not come with the game files and does not download them. The games come from the iPod that bought them: use iTunes or the Finder on a Mac to put purchased games on the iPod. The app reads the keys and copies the game folders between the iPod and a folder on your Mac.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("About the Game Files") }

            Section {
                if model.currentIPod == nil {
                    Label("No iPod is connected. Connect the iPod. The pane reads the file of the keys of the iPod.",
                          systemImage: "cable.connector.slash").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Read the Keys") { Task { await model.readGameKeys() } }
                            .help("Read the file of the keys of the connected iPod")
                        Spacer()
                        if !model.gameKeyStatus.isEmpty { Text(model.gameKeyStatus).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button("Choose a Folder…") { Task { await model.readGameKeysFromFolder() } }
                        .help("Read the file of the keys from a folder iPod_Control that you choose. The folder can come from any iPod, also from a copy of a backup.")
                    Spacer()
                }
            } header: { Text("Key Store") }

            if let store = model.gameKeyStore {
                Section {
                    HStack {
                        Text("Accounts")
                        Spacer()
                        Text("\(store.accounts.count)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Keys")
                        Spacer()
                        Text("\(store.keyCount)").foregroundStyle(.secondary)
                    }
                    if model.gameKeyFileSize > 0 {
                        HStack {
                            Text("File of the keys")
                            Spacer()
                            Text("\(model.gameKeyFileSize) bytes").foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("The File of the Keys") }

                Section {
                    ForEach(store.accounts) { account in
                        AccountRow(account: account, games: model.gameKeyGames.filter { $0.keys.number == account.number })
                    }
                } header: { Text("Accounts") }
            } else if !model.gameKeyStatus.isEmpty {
                Section {
                    Text(model.gameKeyStatus).foregroundStyle(.secondary)
                } header: { Text("The File of the Keys") }
            }

            if !model.gameKeyGames.isEmpty {
                Section {
                    ForEach(model.gameKeyGames, id: \.sinfPath) { game in
                        GameRow(game: game)
                    }
                } header: { Text("Games") }
            }

            Section {
                Label("The games are not in the app. The games are not in the firmware of the iPod. You must get the game files from another place: for example a backup of the folder iPod_Control of an iPod that has the games, or a folder that you keep on your Mac. Each game is a folder with the GUID of the game, for example 11002.",
                      systemImage: "gamecontroller")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Select Games Folder…") { model.chooseGamesFolder() }
                        .help("Choose the folder with the games, or the folder iPod_Control of an iPod")
                    Spacer()
                    if let folder = model.gamesSourceFolder {
                        Text(folder.lastPathComponent).foregroundStyle(.secondary)
                    }
                }
                if !model.gamesLibrary.isEmpty {
                    HStack {
                        Button("Select All") { model.selectAllGames(true) }
                        Button("Select None") { model.selectAllGames(false) }
                        Spacer()
                        Text("\(model.selectedGameFolders.isEmpty ? model.gamesLibrary.count : model.selectedGameFolders.count) of \(model.gamesLibrary.count)")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.gamesLibrary, id: \.folder) { game in
                        GamePickerRow(game: game, selected: model.selectedGameFolders.contains(game.folder)) {
                            if model.selectedGameFolders.contains(game.folder) {
                                model.selectedGameFolders.remove(game.folder)
                            } else {
                                model.selectedGameFolders.insert(game.folder)
                            }
                        }
                    }
                }
                HStack {
                    Button("Install Games") { Task { await model.installGames() } }
                        .disabled(model.currentIPod == nil || model.gamesLibrary.isEmpty)
                        .help("Copy the selected games to the folder games_RO of the connected iPod")
                    Spacer()
                }
                if !model.gameInstallStatus.isEmpty {
                    Text(model.gameInstallStatus).foregroundStyle(.secondary)
                }
                Text("The app copies the selected games to the folder games_RO of the iPod. The app writes the name of the folder with small letters. The app never changes the file Manifest.plist or the file Manifest.plist.p7b.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Install Games") }

            Section {
                if model.currentIPod == nil {
                    Label("No iPod is connected. Connect the iPod to remove games from it.",
                          systemImage: "cable.connector.slash").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Read the Games on the iPod") { Task { await model.readIPodGames() } }
                            .help("Read the folder games_RO of the connected iPod and list its games")
                        Spacer()
                        if !model.ipodGames.isEmpty {
                            Text("\(model.ipodGames.count) game(s)").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.ipodGames, id: \.self) { guid in
                        HStack {
                            Button {
                                if model.selectedIPodGames.contains(guid) {
                                    model.selectedIPodGames.remove(guid)
                                } else {
                                    model.selectedIPodGames.insert(guid)
                                }
                            } label: {
                                Image(systemName: model.selectedIPodGames.contains(guid) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(model.selectedIPodGames.contains(guid) ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Select this game for the removal")
                            Text(guid)
                            Spacer()
                        }
                    }
                    HStack {
                        Button("Remove Selected Games…") { model.showRemoveGamesSheet = true }
                            .disabled(model.selectedIPodGames.isEmpty)
                            .help("Remove the selected game folders from the folder games_RO of the connected iPod")
                        Spacer()
                    }
                    if !model.gameRemoveStatus.isEmpty {
                        Text(model.gameRemoveStatus).foregroundStyle(.secondary)
                    }
                    Text("The removal deletes the folder of the selected game in games_RO. The folders gamedata_RW and gamestats_WO hold the saves and the scores. The removal does not touch them. The removal cannot delete a folder outside the folder of a game.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: { Text("Remove Games") }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $model.showRemoveGamesSheet) { RemoveGamesSheet() }
    }
}

/// The confirmation of the removal of the games. The removal deletes files on
/// the iPod, thus the owner must confirm each removal.
struct RemoveGamesSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Remove \(model.selectedIPodGames.count) game(s) from the iPod?")
                .font(.title3).bold()
            Text("The removal deletes the folder of each selected game in the folder games_RO. The removal does not touch the saves and the scores of the games. The iPod does not show the games again after the removal.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remove") {
                    let wanted = model.selectedIPodGames
                    dismiss()
                    Task { await model.removeGames(wanted) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 380)
    }
}

/// One game of the library, with a switch that selects it for the copy.
struct GamePickerRow: View {
    var game: GameLibraryItem
    var selected: Bool
    var toggle: () -> Void

    var body: some View {
        HStack {
            Button(action: toggle) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(selected ? "Do not copy this game" : "Copy this game")
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                Text("\(game.folder)  •  platform \(game.manifest.platformID)  •  \(game.manifest.totalSize) bytes")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// One account of the Apple ID, with the number of its keys and the games that use it.
struct AccountRow: View {
    var account: GameKeys.Account
    var games: [GameKeys.Game]
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            if games.isEmpty {
                Text("No game of the iPod uses this account.").foregroundStyle(.secondary)
            }
            ForEach(games, id: \.sinfPath) { game in
                GameRow(game: game)
            }
            if !account.keys.isEmpty {
                Text("Key indices: \(account.keys.map { String($0.index) }.sorted { $0 < $1 }.joined(separator: ", "))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Text(String(format: "0x%08x", account.number))
                Spacer()
                Text("\(account.keys.count) keys").foregroundStyle(.secondary)
            }
        }
    }
}

/// One game of the iPod, with its account and its key.
struct GameRow: View {
    var game: GameKeys.Game

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.folder)
                Text("Account \(String(format: "0x%08x", game.keys.number))  •  key \(game.keys.keyIndex)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let key = game.keys.key {
                Text(key.hex)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Label("no key", systemImage: "questionmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
