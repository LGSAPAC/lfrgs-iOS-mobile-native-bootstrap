import LiferayKit
import SwiftUI

struct AddressListView: View {
    @State private var model: AddressListModel
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(PostalAddress)
        var id: String {
            switch self {
            case .new: "new"
            case let .existing(address): "address-\(address.id ?? 0)"
            }
        }
    }

    init(api: APIClient, userAccountID: Int) {
        _model = State(initialValue: AddressListModel(api: api, userAccountID: userAccountID))
    }

    var body: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            ForEach(model.addresses) { address in
                Button {
                    editing = .existing(address)
                } label: {
                    AddressRow(address: address)
                }
                .tint(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await model.delete(address) } }
                }
            }
        }
        .overlay {
            if !model.hasLoaded {
                ProgressView()
            } else if model.addresses.isEmpty && model.errorMessage == nil {
                ContentUnavailableView("No addresses", systemImage: "house", description: Text("Tap + to add one."))
            }
        }
        .navigationTitle("My Addresses")
        .toolbar {
            Button("Add address", systemImage: "plus") { editing = .new }
                .disabled(model.countries.isEmpty)
        }
        .task { if !model.hasLoaded { await model.load() } }
        .refreshable { await model.load() }
        .sheet(item: $editing) { target in
            NavigationStack {
                switch target {
                case .new:
                    AddressFormView(title: "New Address", draft: PostalAddressDraft(), countries: model.countries) { draft in
                        try await model.add(draft)
                    }
                case let .existing(address):
                    AddressFormView(title: "Edit Address", draft: PostalAddressDraft(address, countries: model.countries),
                                    countries: model.countries) { draft in
                        if let id = address.id { try await model.update(id, with: draft) }
                    }
                }
            }
        }
    }
}

struct AddressRow: View {
    let address: PostalAddress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(address.name?.isEmpty == false ? address.name! : "Address").font(.headline)
                if address.primary == true {
                    Text("Primary")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            Text(address.streetAddressLine1)
            Text([address.addressLocality, address.addressRegion, address.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            if let country = address.addressCountry { Text(country).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }
}
