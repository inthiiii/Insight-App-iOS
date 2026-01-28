import SwiftUI

struct TextInputView: View {
    @Binding var text: String
    @Environment(\.dismiss) var dismiss
    var onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0f172a").ignoresSafeArea()
                
                VStack {
                    TextEditor(text: $text)
                        .padding()
                        .scrollContentBackground(.hidden) // Removes default gray background
                        .background(.white.opacity(0.05))
                        .foregroundStyle(.white)
                        .cornerRadius(15)
                        .font(.body)
                        .padding()
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}
