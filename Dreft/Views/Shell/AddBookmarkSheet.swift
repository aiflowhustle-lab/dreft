import SwiftUI

struct AddBookmarkSheet: View {
    @Bindable var workspace: WorkspaceStore
    let fileID: String

    @State private var title = ""
    @State private var group = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case group
    }

    private var file: WorkspaceFileEntry? {
        workspace.files.first { $0.id == fileID }
    }

    private var pathLabel: String {
        guard let file else { return "" }
        return WorkspaceStore.defaultBookmarkTitle(for: file)
    }

    private var isEditing: Bool {
        workspace.isBookmarked(fileID)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    workspace.dismissBookmarkEditor()
                }

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                VStack(spacing: 0) {
                    formRow(label: "Path") {
                        Text(pathLabel)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(fieldBackground(isFocused: false))
                    }

                    hairline

                    formRow(label: "Title") {
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .title)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(fieldBackground(isFocused: focusedField == .title))
                            .onSubmit { save() }
                    }

                    hairline

                    formRow(label: "Bookmark group") {
                        HStack(spacing: 0) {
                            TextField("", text: $group)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white)
                                .focused($focusedField, equals: .group)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)

                            Menu {
                                Button("None") { group = "" }
                                if !workspace.bookmarkGroups.isEmpty {
                                    Divider()
                                    ForEach(workspace.bookmarkGroups, id: \.self) { existingGroup in
                                        Button(existingGroup) { group = existingGroup }
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.45))
                                    .frame(width: 28, height: 28)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                        }
                        .background(fieldBackground(isFocused: focusedField == .group))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.035))
                )
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") {
                        workspace.dismissBookmarkEditor()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.75))

                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppColors.selectionStroke)
                    )
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
            #if os(iOS)
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            #else
            .frame(width: 420)
            #endif
            .background(Color(red: 0.125, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
        }
        .onAppear(perform: loadDraft)
        .onChange(of: fileID) { _, _ in loadDraft() }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit bookmark" : "Add bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                workspace.dismissBookmarkEditor()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 108, alignment: .leading)

            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fieldBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isFocused
                            ? AppColors.selectionStroke.opacity(0.8)
                            : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            )
    }

    private func loadDraft() {
        guard let file else {
            workspace.dismissBookmarkEditor()
            return
        }
        if let bookmark = workspace.bookmark(for: fileID) {
            title = bookmark.title
            group = bookmark.group
        } else {
            title = WorkspaceStore.defaultBookmarkTitle(for: file)
            group = ""
        }
        focusedField = .title
    }

    private func save() {
        workspace.saveBookmark(fileID: fileID, title: title, group: group)
    }
}
