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
            .onAppear {
                Task {
                    do {
                        try await vm.initialize()
                    } catch {
                        fatalError("Error initializing: \(error). This is a fatal error.")
                    }

                    await fetchChanges()
                }
            }
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task {
                            await fetchChanges()
                        }
                    }) { Image(systemName: "arrow.clockwise" )}
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { self.isAddingContact = true }) { Image(systemName: "plus") }
                }
            }
        }.sheet(isPresented: $isAddingContact, content: { createAddContactView() })
    }

    /// View for adding a new Contact.
    private func createAddContactView() -> some View {
        let addAction: () -> Void = {
            Task {
                do {
                    try await vm.addContact(name: nameInput)
                } catch {
                    print("An error occurred adding contact to CloudKit: \(error)")
                }
                isAddingContact = false
                await fetchChanges()
            }
        }

        return NavigationView {
            VStack {
                TextField("Name", text: $nameInput)
                    .onSubmit(addAction)
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

    private func fetchChanges() async {
        do {
            try await vm.fetchLatestChanges()
        } catch {
            print("An error occurred fetching latest changes from CloudKit: \(error)")
        }
    }

    private func deleteContacts(at indexSet: IndexSet) {
        guard let firstIndex = indexSet.first else {
            return
        }

        let contactName = vm.contactNames[firstIndex]

        Task {
            do {
                try await vm.deleteContact(name: contactName)
                await fetchChanges()
            } catch {
                print("An error occurred removing contact from CloudKit: \(error)")
            }
        }
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
