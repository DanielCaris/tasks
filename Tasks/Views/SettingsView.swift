import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var jiraURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jql = "assignee = currentUser() ORDER BY updated DESC"
    @State private var jqlPreset: JQLPreset = .misTareas

    private enum JQLPreset: String, CaseIterable {
        case misTareas = "Mis tareas"
        case todasRecientes = "Todas recientes"
        case porProyecto = "Por proyecto"
        case otra = "Otra"

        var query: String? {
            switch self {
            case .misTareas: return "assignee = currentUser() ORDER BY updated DESC"
            case .todasRecientes: return "order by updated DESC"
            case .porProyecto: return "project in projectsLeadByUser() ORDER BY updated DESC"
            case .otra: return nil
            }
        }

        static func from(jql: String) -> JQLPreset {
            let trimmed = jql.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "assignee = currentUser() ORDER BY updated DESC" { return .misTareas }
            if trimmed == "order by updated DESC" { return .todasRecientes }
            if trimmed == "project in projectsLeadByUser() ORDER BY updated DESC" { return .porProyecto }
            return .otra
        }
    }
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSuccess: Bool?
    @State private var selectedStatusFilters: Set<String> = []
    @State private var newStatusInput = ""
    @State private var selectedTab = 0
    @State private var statusOrdersByProject: [String: [String]] = [:]
    @State private var statusColors: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Listado").tag(0)
                Text("Conexión").tag(1)
                Text("Orden por estado").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Group {
                if selectedTab == 0 {
                    listadoTab
                } else if selectedTab == 1 {
                    conexionTab
                } else {
                    ordenPorEstadoTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 500)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            jiraURL = KeychainHelper.load(key: "jira_url") ?? ""
            jiraEmail = KeychainHelper.load(key: "jira_email") ?? ""
            jiraToken = KeychainHelper.load(key: "jira_api_token") ?? ""
            jql = KeychainHelper.loadJQL() ?? "assignee = currentUser() ORDER BY updated DESC"
            jqlPreset = JQLPreset.from(jql: jql)
            selectedStatusFilters = taskStore.selectedStatusFilters
            testMessage = nil
            testSuccess = nil
            loadAllStatusOrders()
            statusColors = KeychainHelper.loadStatusColors()
        }
        .onChange(of: jql) { _, _ in applyChanges() }
        .onChange(of: jiraURL) { _, _ in applyChanges() }
        .onChange(of: jiraEmail) { _, _ in applyChanges() }
        .onChange(of: jiraToken) { _, _ in applyChanges() }
        .onChange(of: selectedStatusFilters) { _, _ in applyChanges() }
    }

    private var listadoTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Solo se mostrarán tareas con estos status. Vacío = mostrar todas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 8) {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(selectedStatusFilters).sorted(), id: \.self) { status in
                                StatusPill(label: status) {
                                    selectedStatusFilters.remove(status)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Menu {
                            ForEach(availableStatusesToAdd, id: \.self) { status in
                                Button(status) {
                                    selectedStatusFilters.insert(status)
                                }
                            }
                            if availableStatusesToAdd.isEmpty && !taskStore.knownStatuses.isEmpty {
                                Text("Todos agregados")
                                    .disabled(true)
                            }
                        } label: {
                            Label("Agregar status", systemImage: "plus.circle")
                        }
                        .disabled(availableStatusesToAdd.isEmpty && newStatusInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        TextField("O escribe uno nuevo", text: $newStatusInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 100)
                            .onSubmit { addCustomStatus() }

                        Button("Agregar") {
                            addCustomStatus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(newStatusInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Filtrar por status")
            } footer: {
                if !taskStore.knownStatuses.isEmpty {
                    Text("Status descubiertos: \(taskStore.knownStatuses.joined(separator: ", "))")
                        .font(.caption2)
                }
            }

            Section {
                Picker("Presets", selection: $jqlPreset) {
                    ForEach(JQLPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: jqlPreset) { _, preset in
                    if let query = preset.query {
                        jql = query
                    }
                }

                TextField("JQL (opcional)", text: $jql, prompt: Text("assignee = currentUser()"), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: jql) { _, _ in
                        jqlPreset = JQLPreset.from(jql: jql)
                    }
            } header: {
                Text("Consulta JQL")
            }
        }
        .formStyle(.grouped)
    }

    private var ordenPorEstadoTab: some View {
        Form {
            Section {
                if statusesForColors.isEmpty {
                    Text("Sincroniza tareas desde Jira para ver los estados aquí.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(statusesForColors, id: \.self) { status in
                        HStack {
                            Circle()
                                .fill(Color(hex: statusColors[status] ?? "808080"))
                                .frame(width: 10, height: 10)
                            Text(status)
                                .font(.subheadline)
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: statusColors[status] ?? "808080") },
                                set: { newColor in
                                    statusColors[status] = newColor.hexString
                                    KeychainHelper.saveStatusColors(statusColors)
                                    taskStore.reloadStatusColors()
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            } header: {
                Text("Colores por estado")
            } footer: {
                Text("El círculo junto al estado de cada tarea usará el color configurado.")
                    .font(.caption)
            }

            Section {
                Text("Orden de estados para subtareas (primero = más arriba). Cada proyecto tiene su propia configuración.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if taskStore.knownProjectKeys.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Sin proyectos",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Sincroniza tareas desde Jira para ver los proyectos aquí.")
                    )
                }
            } else {
                ForEach(taskStore.knownProjectKeys, id: \.self) { projectKey in
                    Section {
                        projectStatusOrderSection(projectKey: projectKey)
                    } header: {
                        Text(projectKey)
                            .font(.headline)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadAllStatusOrders()
            statusColors = KeychainHelper.loadStatusColors()
        }
    }

    private func projectStatusOrderSection(projectKey: String) -> some View {
        let order = statusOrdersByProject[projectKey] ?? []
        return Group {
            List {
                ForEach(order, id: \.self) { status in
                    Text(status)
                        .font(.subheadline)
                }
                .onMove { from, to in
                    var newOrder = order
                    newOrder.move(fromOffsets: from, toOffset: to)
                    updateAndSaveOrder(projectKey: projectKey, order: newOrder)
                }
                .onDelete { indexSet in
                    var newOrder = order
                    newOrder.remove(atOffsets: indexSet)
                    updateAndSaveOrder(projectKey: projectKey, order: newOrder)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: CGFloat(min(order.count, 4)) * 28)

            Menu {
                ForEach(taskStore.knownStatuses.filter { !order.contains($0) }, id: \.self) { status in
                    Button(status) {
                        var newOrder = order
                        newOrder.append(status)
                        updateAndSaveOrder(projectKey: projectKey, order: newOrder)
                    }
                }
                if taskStore.knownStatuses.filter({ !order.contains($0) }).isEmpty && !taskStore.knownStatuses.isEmpty {
                    Text("Todos agregados")
                        .disabled(true)
                }
            } label: {
                Label("Agregar status", systemImage: "plus.circle")
            }
            .disabled(taskStore.knownStatuses.filter { !order.contains($0) }.isEmpty)
        }
    }

    private func loadAllStatusOrders() {
        var dict: [String: [String]] = [:]
        for key in taskStore.knownProjectKeys {
            dict[key] = KeychainHelper.loadStatusOrder(projectKey: key)
        }
        statusOrdersByProject = dict
    }

    private func updateAndSaveOrder(projectKey: String, order: [String]) {
        statusOrdersByProject = statusOrdersByProject.merging([projectKey: order]) { _, new in new }
        KeychainHelper.saveStatusOrder(projectKey: projectKey, order: order)
    }

    private var conexionTab: some View {
        Form {
            Section {
                TextField("URL base", text: $jiraURL, prompt: Text("https://tu-empresa.atlassian.net"))
                    .textContentType(.URL)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $jiraEmail, prompt: Text("tu@email.com"))
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Token", text: $jiraToken, prompt: Text("Token de Atlassian"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Jira")
            } footer: {
                Text("Genera un API token en id.atlassian.com → Seguridad → Tokens de API. Usa el mismo email con el que accedes a Jira.")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if isTesting {
                                ProgressView().scaleEffect(0.5)
                            } else {
                                Image(systemName: "network")
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(isTesting ? "Probando..." : "Probar conexión")
                    }
                    .frame(width: 160, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!isValid || isTesting)

                if let msg = testMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(testSuccess == true ? .green : .red)
                }

                Button("Limpiar caché de usuario") {
                    taskStore.clearCurrentUserDisplayNameCache()
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
    }

    private var statusesForColors: [String] {
        Set(taskStore.knownStatuses).union(statusColors.keys).sorted()
    }

    private var availableStatusesToAdd: [String] {
        taskStore.knownStatuses.filter { !selectedStatusFilters.contains($0) }
    }

    private func addCustomStatus() {
        let trimmed = newStatusInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedStatusFilters.insert(trimmed)
        newStatusInput = ""
    }

    private func testConnection() {
        testMessage = nil
        testSuccess = nil
        isTesting = true
        let url = jiraURL.trimmingCharacters(in: .whitespaces)
        let email = jiraEmail.trimmingCharacters(in: .whitespaces)
        let provider = JiraProvider(baseURL: url, email: email, apiToken: jiraToken, jql: jql)
        Task {
            do {
                let issues = try await provider.fetchIssues()
                await MainActor.run {
                    testMessage = "Conexión exitosa. Se encontraron \(issues.count) tareas."
                    testSuccess = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testMessage = error.localizedDescription
                    testSuccess = false
                    isTesting = false
                }
            }
        }
    }

    private var isValid: Bool {
        !jiraURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !jiraEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        !jiraToken.isEmpty
    }

    private func applyChanges() {
        let url = jiraURL.trimmingCharacters(in: .whitespaces)
        let email = jiraEmail.trimmingCharacters(in: .whitespaces)

        KeychainHelper.save(key: "jira_url", value: url)
        KeychainHelper.save(key: "jira_email", value: email)
        KeychainHelper.save(key: "jira_api_token", value: jiraToken)
        KeychainHelper.saveJQL(jql.isEmpty ? "assignee = currentUser() ORDER BY updated DESC" : jql)
        taskStore.setStatusFilters(selectedStatusFilters)

        if isValid {
            taskStore.setProvider(JiraProvider(
                baseURL: url,
                email: email,
                apiToken: jiraToken,
                jql: jql.isEmpty ? "assignee = currentUser() ORDER BY updated DESC" : jql
            ))
        }
    }
}
