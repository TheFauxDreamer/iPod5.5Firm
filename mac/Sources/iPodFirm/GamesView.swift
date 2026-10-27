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
                Label("The app does not come with the game files and does not download them. The games come from the iPod that bought them: use iTunes or the Finder on a Mac to put purchased games on the iPod. The app copies the game folders from a folder on your Mac to the iPod.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("About the Game Files") }

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
                Text("Optional. A game plays only on the iPod that bought it, and only if that iPod has the key file IC-Info.sidb of the account that bought the game. A restore removes this file. Choose your own file, for example from a backup of the folder iPod_Control/iTunes of this iPod. The app copies the file to iPod_Control/iTunes as it is. The app does not read, change or make a key file.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Install Games") { Task { await model.installGames() } }
                        .disabled(model.currentIPod == nil || model.gamesLibrary.isEmpty)
                        .help("Copy the selected games to the folder games_RO of the connected iPod, and the key file if you chose one")
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
