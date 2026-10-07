import SwiftUI

struct ManagerView: View {
    @ObservedObject var host: WidgetHost
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 240)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $host.editMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode edit").font(.headline)
                    Text(host.editMode ? "Geser dan tarik tepi widget. Klik kanan untuk menu."
                                       : "Widget terkunci dan klik menembus ke desktop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityHint("Mengaktifkan atau mengunci posisi dan ukuran widget")

            Spacer()

            Menu {
                ForEach(WidgetRegistry.all) { def in
                    Button { host.add(type: def.id) } label: { Label(def.displayName, systemImage: def.symbol) }
                }
            } label: {
                Label("Tambah widget", systemImage: "plus")
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .padding(14)
    }

    // MARK: Daftar

    private var sidebar: some View {
        Group {
            if host.instances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Belum ada widget").foregroundStyle(.secondary)
                    Text("Pakai “Tambah widget” di kanan atas.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $host.selectedID) {
                    ForEach(host.instances) { inst in
                        row(inst).tag(inst.id as UUID?)
                    }
                }
            }
        }
    }

    private func row(_ inst: WidgetInstance) -> some View {
        let def = WidgetRegistry.definition(for: inst.type)
        return HStack {
            Image(systemName: def?.symbol ?? "questionmark.square").frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(def?.displayName ?? inst.type)
                Text(inst.fullScreen ? "Layar Penuh" : "\(Int(inst.frame.w)) × \(Int(inst.frame.h))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                host.update(inst.id) { $0.visible.toggle() }
            } label: {
                Image(systemName: inst.visible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(inst.visible ? "Sembunyikan widget" : "Tampilkan widget")
        }
        .opacity(inst.visible ? 1 : 0.5)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let inst = host.selected, let def = WidgetRegistry.definition(for: inst.type) {
            WidgetDetailView(host: host, id: inst.id, def: def)
        } else {
            Text("Pilih widget untuk mengatur").foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 20) {
            Toggle("Buka otomatis saat login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }))
            Toggle("Ikon menu bar", isOn: $settings.showMenuBarIcon)
            Toggle("Lacak pemakaian app", isOn: $settings.trackUsage)
                .help("Mencatat berapa lama tiap app dipakai, untuk widget Penggunaan Aplikasi. Data hanya di Mac ini.")
            if let err = settings.loginError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
    }
}

struct WidgetDetailView: View {
    @ObservedObject var host: WidgetHost
    let id: UUID
    let def: AnyWidgetDefinition

    var body: some View {
        if let inst = host.instance(id) {
            Form {
                Section("Ukuran & posisi") {
                    HStack {
                        ForEach(SizePreset.allCases.filter { $0 != .fullScreen }) { preset in
                            Button(preset.title) { host.applyPreset(id, preset) }
                        }
                        Button(inst.fullScreen ? "Kembalikan ukuran" : "Layar Penuh") { host.toggleFullScreen(id) }
                    }
                    Picker("Layar", selection: Binding(
                        get: { inst.display },
                        set: { v in host.update(id) { $0.display = v } })) {
                        ForEach(DisplayManager.all, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Di atas ikon desktop", isOn: Binding(
                        get: { inst.aboveIcons },
                        set: { v in host.update(id) { $0.aboveIcons = v } }))
                    HStack {
                        Text("Opasitas")
                        Slider(value: Binding(
                            get: { inst.opacity },
                            set: { v in host.update(id) { $0.opacity = v } }), in: 0.1...1)
                        Text("\(Int(inst.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Section(def.displayName) {
                    def.settings(Binding(
                        get: { host.instance(id)?.config ?? .null },
                        set: { v in host.update(id) { $0.config = v } }))
                }
                Section {
                    Button("Hapus widget", role: .destructive) { host.remove(id) }
                }
            }
            .formStyle(.grouped)
        }
    }
}
