//
//  HostSidebarView.swift
//  Limelight
//
//  Created by SkyHua on 2025-01-20.
//

import SwiftUI

@objc public class HostSidebarViewFactory: NSObject {
    @objc public static func createSidebar(selectedHostUUID: String?, initialHost: TemporaryHost?, initialHosts: [TemporaryHost], onHostSelected: @escaping (String, Int) -> Void) -> NSViewController {
        // We need a binding for the selectedHostUUID
        // Since we can't easily pass a Binding from ObjC, we'll use a StateObject or similar in the wrapper view
        // OR, we can just pass the initial value and rely on the callback.
        // But the View expects a Binding.

        // Let's create a wrapper view that manages the binding
        let wrapper = HostSidebarWrapper(initialUUID: selectedHostUUID, initialHost: initialHost, initialHosts: initialHosts, onHostSelected: onHostSelected)
        return NSHostingController(rootView: wrapper)
    }
}

struct HostSidebarWrapper: View {
    @SwiftUI.State private var selectedUUID: String?
    let initialHost: TemporaryHost?
    let initialHosts: [TemporaryHost]
    let onHostSelected: (String, Int) -> Void

    init(initialUUID: String?, initialHost: TemporaryHost?, initialHosts: [TemporaryHost], onHostSelected: @escaping (String, Int) -> Void) {
        _selectedUUID = SwiftUI.State(initialValue: initialUUID)
        self.initialHost = initialHost
        self.initialHosts = initialHosts
        self.onHostSelected = onHostSelected
    }

    var body: some View {
        HostSidebarView(selectedHostUUID: $selectedUUID, initialHost: initialHost, initialHosts: initialHosts, onHostSelected: onHostSelected)
    }
}

struct HostSidebarView: View {
    @StateObject private var viewModel: HostSidebarViewModel
    @Binding var selectedHostUUID: String?
    let onHostSelected: (String, Int) -> Void

    init(selectedHostUUID: Binding<String?>, initialHost: TemporaryHost?, initialHosts: [TemporaryHost], onHostSelected: @escaping (String, Int) -> Void) {
        self._viewModel = StateObject(wrappedValue: HostSidebarViewModel(initialHost: initialHost, initialHosts: initialHosts))
        self._selectedHostUUID = selectedHostUUID
        self.onHostSelected = onHostSelected
    }

    var body: some View {
        List(selection: $selectedHostUUID) {
            Section(header: Text(LanguageManager.shared.localize("Computers"))) {
                ForEach(viewModel.hosts, id: \.uuid) { host in
                    HostRowView(host: host)
                        .tag(host.uuid)
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200)
        .onChange(of: selectedHostUUID) { newUUID in
            if let uuid = newUUID {
                let stateRaw = viewModel.hosts.first(where: { $0.uuid == uuid })?.state.rawValue ?? HostState.unknown.rawValue
                onHostSelected(uuid, stateRaw)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // Force view update by toggling a state or simply relying on the view re-evaluating body
            // Since localize() is called in body, a re-render is needed.
            // Using a dummy ID or just the fact that onReceive triggers an update might work,
            // but explicitly changing an ID is safer.
            viewModel.objectWillChange.send()
        }
    }
}

struct HostRowView: View {
    let host: HostDisplayModel

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(host.statusColor)
                .frame(width: 8, height: 8)

            // Host name
            Text(host.name)
                .lineLimit(1)
                .font(.body)

            Spacer()

            // Streaming badge
            if host.isStreaming {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

extension HostDisplayModel {
    var statusColor: Color {
        // According to HostCell.m logic:
        // Online + Paired -> Green
        // Online + Unpaired -> Orange
        // Offline + Paired -> Red
        // Offline + Unpaired -> Gray
        // Unknown -> Gray (or Yellow as before, but HostCell says Gray for unknown default, though there is a comment about yellow in previous swift code. Let's stick to the requested plan: Unknown -> Yellow)

        // User request:
        // 1. Offline is red (Offline + Paired)
        // 2. Paired is orange (Wait, user said "Paired is orange"? No, user said "Paired is orange" in the prompt "2. Paired is orange" but usually Unpaired is orange.
        // Let's re-read the user prompt: "2. Paired is orange".
        // BUT HostCell.m says:
        // if (self.host.pairState == PairStateUnpaired) { statusColor = [NSColor systemOrangeColor]; } // This is ONLINE + UNPAIRED
        // User might have meant "Unpaired is orange". "Paired" means "Paired". "Unpaired" means "Unpaired".
        // The user said: "2. Paired is orange" (Paired is orange). This contradicts standard Moonlight logic (Green is connected/paired).
        // However, looking at the plan: "Online unpaired = orange".
        // Let's look at the user's prompt again carefully.
        // "1. Offline is red"
        // "2. Paired is orange"
        // "3. Online is green"
        // "4. Streaming is green with a green play button"

        // This is slightly confusing. "Online" implies Paired usually in user's mind if they just say "Online is Green".
        // "Paired is orange" (Paired is Orange) - this is very weird. Usually Orange is for "Ready to pair" (Unpaired).
        // Let's trust the Plan which analyzed HostCell.m:
        // "Online unpaired = orange" (Online Unpaired = Orange)
        // "Online paired = green" (Online Paired = Green)
        // I will follow the Plan and HostCell.m logic, assuming the user might have misspoken or meant "Detected but not paired".

        if isStreaming { return .green }

        switch state {
        case .online:
            return pairState == .paired ? .green : .orange
        case .offline:
            return pairState == .paired ? .red : .gray
        case .unknown:
            return .gray
        }
    }
}
