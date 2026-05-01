import SwiftUI

struct KnowledgeBaseView: View {
    @State private var glossary: [GlossaryEntry] = []
    @State private var writingStyle: String = ""
    @State private var businessDesc: String = ""
    @State private var businessProducts: String = ""
    @State private var businessTerms: String = ""
    @State private var businessExtra: String = ""

    @State private var glossaryExpanded = false
    @State private var styleExpanded = false
    @State private var businessExpanded = false

    @State private var showClearConfirm = false

    private let settings = SharedSettings.shared

    var body: some View {
        Group {
            // MARK: - Glossary
            Section {
                DisclosureGroup(isExpanded: $glossaryExpanded) {
                    ForEach($glossary) { $entry in
                        VStack(spacing: 6) {
                            TextField("Term (e.g. MOQ)", text: $entry.term)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("Meaning (e.g. Minimum Order Quantity)", text: $entry.meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indices in
                        glossary.remove(atOffsets: indices)
                        saveGlossary()
                    }

                    if glossary.count < AppConstants.maxGlossaryEntries {
                        Button {
                            glossary.append(GlossaryEntry(term: "", meaning: ""))
                        } label: {
                            Label("Add Term", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    } else {
                        Text("Maximum \(AppConstants.maxGlossaryEntries) entries reached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Label("My Glossary", systemImage: "book.closed")
                        Spacer()
                        Text(glossary.isEmpty ? "not set" : "\(glossary.count) terms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: glossary) { _, _ in saveGlossary() }
            } header: {
                Text("Knowledge Base")
            } footer: {
                if glossaryExpanded {
                    Text("Define terms the AI should always translate correctly.")
                }
            }

            // MARK: - Writing Style
            Section {
                DisclosureGroup(isExpanded: $styleExpanded) {
                    TextEditor(text: $writingStyle)
                        .frame(minHeight: 100)
                        .font(.subheadline)
                        .overlay(alignment: .topLeading) {
                            if writingStyle.isEmpty {
                                Text("Paste 3-5 real messages you've sent to clients or suppliers. The AI will learn your communication style.")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: writingStyle) { _, newValue in
                            if newValue.count > AppConstants.maxWritingStyleCharacters {
                                writingStyle = String(newValue.prefix(AppConstants.maxWritingStyleCharacters))
                            }
                            settings.writingStyleExamples = writingStyle
                        }

                    HStack {
                        Text("\(writingStyle.count)/\(AppConstants.maxWritingStyleCharacters)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Your examples stay on your device. They are only sent to your chosen AI provider when translating.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } label: {
                    HStack {
                        Label("My Writing Style", systemImage: "text.quote")
                        Spacer()
                        Text(writingStyle.isEmpty ? "not set" : "set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Business Info
            Section {
                DisclosureGroup(isExpanded: $businessExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        businessField("What does your business do?", text: $businessDesc, key: "description")
                        businessField("Common products/services", text: $businessProducts, key: "products",
                                      placeholder: "e.g. women's clothing, dresses, blouses")
                        businessField("Standard terms", text: $businessTerms, key: "terms",
                                      placeholder: "e.g. MOQ 500pcs, 30/70 payment, FOB Guangzhou")
                        businessField("Anything else the AI should know", text: $businessExtra, key: "extra",
                                      placeholder: "e.g. We only work with natural fabrics")
                    }
                } label: {
                    HStack {
                        Label("My Business Info", systemImage: "building.2")
                        Spacer()
                        Text(hasBusinessInfo ? "set" : "not set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Clear & Cost
            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Knowledge base adds ~$0.001 per translation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear All Knowledge Base Data", systemImage: "trash")
                        .font(.subheadline)
                }
                .confirmationDialog("Clear all knowledge base data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("Clear All", role: .destructive) {
                        clearAll()
                    }
                }
            }
        }
        .onAppear { loadAll() }
    }

    private var hasBusinessInfo: Bool {
        !businessDesc.isEmpty || !businessProducts.isEmpty || !businessTerms.isEmpty || !businessExtra.isEmpty
    }

    @ViewBuilder
    private func businessField(_ label: String, text: Binding<String>, key: String, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? label : placeholder, text: text)
                .font(.subheadline)
                .onChange(of: text.wrappedValue) { _, _ in saveBusinessInfo() }
        }
    }

    // MARK: - Persistence

    private func loadAll() {
        let raw = settings.glossary
        glossary = raw.map { GlossaryEntry(term: $0["term"] ?? "", meaning: $0["meaning"] ?? "") }
        writingStyle = settings.writingStyleExamples
        let biz = settings.businessInfo
        businessDesc = biz["description"] ?? ""
        businessProducts = biz["products"] ?? ""
        businessTerms = biz["terms"] ?? ""
        businessExtra = biz["extra"] ?? ""
    }

    private func saveGlossary() {
        let raw = glossary.filter { !$0.term.isEmpty || !$0.meaning.isEmpty }
            .map { ["term": $0.term, "meaning": $0.meaning] }
        settings.glossary = raw
    }

    private func saveBusinessInfo() {
        var info: [String: String] = [:]
        if !businessDesc.isEmpty { info["description"] = businessDesc }
        if !businessProducts.isEmpty { info["products"] = businessProducts }
        if !businessTerms.isEmpty { info["terms"] = businessTerms }
        if !businessExtra.isEmpty { info["extra"] = businessExtra }
        settings.businessInfo = info
    }

    private func clearAll() {
        settings.clearKnowledgeBase()
        glossary = []
        writingStyle = ""
        businessDesc = ""
        businessProducts = ""
        businessTerms = ""
        businessExtra = ""
    }
}

// MARK: - Glossary Entry Model

struct GlossaryEntry: Identifiable, Equatable {
    let id = UUID()
    var term: String
    var meaning: String
}
