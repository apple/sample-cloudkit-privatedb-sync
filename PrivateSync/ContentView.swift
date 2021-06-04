//
//  ContentView.swift
//  (cloudkit-samples) Private Sync
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: ViewModel
    @State var nameInput: String = ""
    @State var isAddingContact: Bool = false

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.contactNames) {
                    Text($0)
                }.onDelete(perform: deleteContacts)
            }
            .onAppear { vm.initializeAndFetchLatestChanges() }
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { vm.fetchLatestChanges() }) { Image(systemName: "arrow.clockwise" )}
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { self.isAddingContact = true }) { Image(systemName: "plus") }
                }
            }
        }.sheet(isPresented: $isAddingContact, content: { createAddContactView() })
    }

    /// View for adding a new Contact.
    private func createAddContactView() -> some View {
        let addAction = {
            vm.addContactToLocalAndRemote(name: nameInput) { _ in
                isAddingContact = false
                vm.fetchLatestChanges()
            }
        }

        return NavigationView {
            VStack {
                TextField("Name", text: $nameInput, onCommit: addAction)
                    .font(.body)
                    .textContentType(.name)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .navigationTitle("Add New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { isAddingContact = false })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addAction)
                }
            }
        }.onDisappear { nameInput = "" }
    }

    private func deleteContacts(at indexSet: IndexSet) {
        guard let firstIndex = indexSet.first else {
            return
        }

        let contactName = vm.contactNames[firstIndex]
        vm.deleteContactFromLocalAndRemote(name: contactName) { _ in }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(ViewModel())
    }
}

// MARK: - Helper Extensions

extension String: Identifiable {
    public typealias ID = Int
    public var id: Int {
        return hash
    }
}
