import AppKit
import IPodFWKit
import SwiftUI
import UniformTypeIdentifiers

struct PicturesView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: Int?
    @State private var filter = Filter.all
    @State private var search = ""

    enum Filter: String, CaseIterable { case all = "All", colour = "Colour", transparent = "Transparent", grey = "Greyscale" }

    var items: [PictureItem] {
        guard let ed = model.editor else { return [] }
        return ed.pictures.filter { item in
            switch filter {
            case .all: true
            case .colour: item.picture.depth == 16 && !item.picture.hasAlpha
            case .transparent: item.picture.hasAlpha
            case .grey: item.picture.isGrey
            }
        }.filter { search.isEmpty || "\($0.index)".contains(search) || "\($0.resourceID)".contains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Picker("Show", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    Spacer()
                    TextField("Index or ID", text: $search).textFieldStyle(.roundedBorder).frame(width: 140)
                }
                .padding(10)
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in
                            Thumb(item: item, selected: selection == item.index)
                                .onTapGesture { selection = item.index }
                        }
                    }
                    .padding(12)
                    .id(model.revision)
                }
            }
            .frame(minWidth: 420)

            Group {
                if let index = selection, let item = model.editor?.pictures.first(where: { $0.index == index }) {
                    PictureDetail(item: item)
                } else {
                    Text("Select a picture").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Export All…") { model.exportFolder() }
                Button("Import Folder…") { model.importFolder() }
            }
        }
    }
}

func nsImage(_ item: PictureItem, _ ed: FirmwareEditor) -> NSImage {
    let p = item.picture
    guard let cg = ImageCodec.cgImage(rgba: ed.rgba(of: item), width: p.width, height: p.height, grey: p.isGrey, alpha: p.hasAlpha) else {
        return NSImage()
    }
    return NSImage(cgImage: cg, size: NSSize(width: p.width, height: p.height))
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 6
            for y in stride(from: 0, to: size.height, by: s) {
                for x in stride(from: 0, to: size.width, by: s) where (Int(x / s) + Int(y / s)) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.18)))
                }
            }
        }
    }
}

struct Thumb: View {
    @EnvironmentObject var model: AppModel
    let item: PictureItem
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Checkerboard()
                if let ed = model.editor {
                    Image(nsImage: nsImage(item, ed)).interpolation(.none).resizable().scaledToFit().padding(4)
                }
            }
            .frame(width: 76, height: 60)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : .secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
            Text("#\(item.index) · \(item.picture.width)×\(item.picture.height)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct PictureDetail: View {
    @EnvironmentObject var model: AppModel
    let item: PictureItem
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Checkerboard()
                    if let ed = model.editor {
                        Image(nsImage: nsImage(item, ed)).interpolation(.none).resizable().scaledToFit().padding(10)
                    }
                }
                .frame(height: 240)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(dropTargeted ? Color.accentColor : .secondary.opacity(0.3), lineWidth: dropTargeted ? 3 : 1))
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.replacePicture(item, from: url) } }
                    }
                    return true
                }
                .id(model.revision)
                Text("Drop a \(item.picture.width)×\(item.picture.height) PNG here to replace it.")
                    .font(.caption).foregroundStyle(.secondary)

                Grid(alignment: .leading, verticalSpacing: 4) {
                    GridRow { Text("Index").foregroundStyle(.secondary); Text("\(item.index)") }
                    GridRow { Text("Resource ID").foregroundStyle(.secondary); Text("\(item.resourceID)") }
                    GridRow { Text("Size").foregroundStyle(.secondary); Text("\(item.picture.width) × \(item.picture.height)") }
                    GridRow { Text("Format").foregroundStyle(.secondary); Text(item.picture.formatName) }
                }
                HStack {
                    Button("Export PNG…") { model.exportPicture(item) }
                    Button("Replace…") { model.chooseReplacement(for: item) }
                }
            }
            .padding(16)
        }
    }
}
