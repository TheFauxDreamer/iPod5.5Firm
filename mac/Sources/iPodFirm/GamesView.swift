import AppKit
import IPodFWKit
import SwiftUI

// The pane of the games. The pane copies the game folders from a folder on the Mac
// to the folder games_RO of the connected iPod. The pane also removes games from
// the iPod.

struct GamesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Label("iPodFirm and the iPod firmware do not contain the games. iPodFirm does not download them. Get the game files from an iPod that bought them, for example a backup of the folder iPod_Control. Each game is a folder with the GUID of the game, for example 11002.",
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
                        Text("\(model.selectedGameFolders.count) of \(model.gamesLibrary.count)")
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
                    Button("Choose Key File…") { model.chooseGameKeyFile() }
                        .help("Optional: choose your own file IC-Info.sidb. The install copies it to the iPod with the games.")
                    Spacer()
                    if let key = model.gameKeyFile {
                        Text(key.lastPathComponent).foregroundStyle(.secondary)
                        Button("Clear") { model.gameKeyFile = nil }
                            .help("Do not copy a key file")
                    } else {
                        Text("No key file").foregroundStyle(.secondary)
                    }
                }
                Text("Optional. A game plays only on the iPod that bought it, and only if that iPod has the key file IC-Info.sidb of the account that bought the game. A restore removes this file. Choose your own file, for example from a backup of the folder iPod_Control/iTunes of this iPod. iPodFirm copies the file to iPod_Control/iTunes as it is. iPodFirm does not read, change or make a key file.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Install Games") { Task { await model.installGames() } }
                        .disabled(model.currentIPod == nil || model.selectedGameFolders.isEmpty)
                        .help("Copy the selected games to the folder games_RO of the connected iPod, and the key file if you chose one")
                    Spacer()
                }
                if !model.gameInstallStatus.isEmpty {
                    Text(model.gameInstallStatus).foregroundStyle(.secondary)
                }
                Text("iPodFirm copies the selected games to the folder games_RO of the iPod. iPodFirm writes the name of the folder with small letters. iPodFirm never changes the file Manifest.plist or the file Manifest.plist.p7b.")
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
                            Text(counted(model.ipodGames.count, "game")).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.ipodGames, id: \.self) { guid in
                        Toggle(guid, isOn: Binding(
                            get: { model.selectedIPodGames.contains(guid) },
                            set: { on in
                                if on { model.selectedIPodGames.insert(guid) } else { model.selectedIPodGames.remove(guid) }
                            }))
                            .toggleStyle(.checkbox)
                            .help("Select this game for the removal")
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
        // The removal deletes files on the iPod. Cancel is the default button.
        .confirmationDialog("Remove \(counted(model.selectedIPodGames.count, "game")) from the iPod?", isPresented: $model.showRemoveGamesSheet) {
            Button("Remove", role: .destructive) {
                let wanted = model.selectedIPodGames
                Task { await model.removeGames(wanted) }
            }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text("The removal deletes the folder of each selected game in the folder games_RO. The removal does not touch the saves and the scores of the games. The iPod does not show the games again after the removal.")
        }
    }
}

/// One game of the library, with a switch that selects it for the copy.
struct GamePickerRow: View {
    var game: GameLibraryItem
    var selected: Bool
    var toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { selected }, set: { _ in toggle() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                Text("\(game.folder)  •  platform \(game.manifest.platformID)  •  \(game.manifest.totalSize) bytes")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .help(selected ? "Do not copy this game" : "Copy this game")
    }
}
