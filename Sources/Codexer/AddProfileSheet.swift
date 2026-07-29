import AppKit
import CodexerCore
import SwiftUI

struct AddProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: CodexerModel
    @State private var product: DesktopProduct = .codex
    @State private var name = ""
    @State private var iconKind: ProfileIconKind = .monogram
    @State private var iconValue = ""
    @State private var iconColor = "#2563EB"
    @State private var customIconData: Data?
    @State private var customizeExpanded = false
    @State private var isSubmitting = false
    @State private var creationTask: Task<Void, Never>?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add Profile")
                        .font(.system(size: 19, weight: .semibold))
                        .padding(.bottom, 18)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Provider")
                            Picker("Provider", selection: $product) {
                                ForEach(DesktopProduct.allCases) { item in
                                    Label(
                                        item.displayName,
                                        systemImage: item == .codex ? "sparkles" : "brain"
                                    )
                                    .tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .controlSize(.regular)
                            .disabled(isSubmitting)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Name")
                            TextField("Personal", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.regular)
                                .focused($nameFocused)
                                .onSubmit(submit)
                                .disabled(isSubmitting)
                        }
                    }
                    .padding(.bottom, 16)

                    DisclosureGroup(isExpanded: $customizeExpanded) {
                        ProfileAppearanceEditor(
                            name: name,
                            iconKind: $iconKind,
                            iconValue: $iconValue,
                            iconColor: $iconColor,
                            customIconData: $customIconData,
                            existingImageURL: nil,
                            compact: true
                        )
                        .padding(.top, 12)
                    } label: {
                        HStack(spacing: 10) {
                            ProfileIconPreview(
                                name: name,
                                kind: iconKind,
                                value: iconValue,
                                color: iconColor,
                                customIconData: customIconData,
                                existingImageURL: nil,
                                size: 30
                            )
                            Text("Customize Icon & Color")
                                .font(.system(size: 14))
                            Spacer()
                            Circle()
                                .fill(Color(hex: iconColor))
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(isSubmitting)
                    .padding(.bottom, 14)

                    Label(
                        "Credentials and conversations stay in this profile's local data.",
                        systemImage: "lock.fill"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(customizeExpanded ? .visible : .hidden)
            .scrollDisabled(!customizeExpanded)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    creationTask?.cancel()
                    model.errorMessage = nil
                    dismiss()
                }
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
                Button("Create Profile", action: submit)
                    .agentDockPrimaryAction()
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || isSubmitting || model.storeMutationInProgress)
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Creating profile")
                }
            }
            .padding(.top, 10)
        }
        .padding(24)
        .frame(
            width: 480,
            height: customizeExpanded ? 540 : 356,
            alignment: .topLeading
        )
        .background(AgentDockPalette.graphite)
        .background(AddProfileWindowConfigurator(isExpanded: customizeExpanded))
        .animation(.easeInOut(duration: 0.18), value: customizeExpanded)
        .onAppear {
            nameFocused = true
        }
        .onDisappear {
            creationTask?.cancel()
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .medium))
            .tracking(0.4)
            .foregroundStyle(.secondary)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty, !isSubmitting, !model.storeMutationInProgress else { return }
        isSubmitting = true
        model.errorMessage = nil
        let requestedProduct = product
        let requestedName = trimmedName
        let requestedColor = Color(hex: iconColor)
        let requestedIconKind = iconKind
        let requestedIconValue = iconValue
        let requestedCustomIconData = customIconData

        creationTask = Task { @MainActor in
            let created = await model.addProfile(
                product: requestedProduct,
                name: requestedName,
                color: requestedColor,
                iconKind: requestedIconKind,
                iconValue: requestedIconValue,
                customIconData: requestedCustomIconData
            )
            guard !Task.isCancelled else { return }
            isSubmitting = false
            creationTask = nil
            if created {
                dismiss()
            }
        }
    }
}

private struct AddProfileWindowConfigurator: NSViewRepresentable {
    let isExpanded: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resize(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { resize(view.window) }
    }

    private func resize(_ window: NSWindow?) {
        guard let window else { return }
        let target = NSSize(width: 480, height: isExpanded ? 540 : 356)
        guard abs(window.contentLayoutRect.width - target.width) > 0.5
            || abs(window.contentLayoutRect.height - target.height) > 0.5
        else {
            return
        }

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(target)
        var frame = window.frame
        frame.origin.x = center.x - frame.width / 2
        frame.origin.y = center.y - frame.height / 2
        window.setFrame(frame, display: true, animate: true)
    }
}
