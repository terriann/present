import SwiftUI
import PresentCore

struct LogFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedType: SessionType?
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    var onRefresh: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Picker("Type", selection: $selectedType) {
                Text("All Types").tag(SessionType?.none)
                ForEach(SessionType.allCases, id: \.self) { type in
                    Text(SessionTypeConfig.config(for: type).displayName)
                        .tag(SessionType?.some(type))
                }
            }
            .frame(width: 150)

            DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                .labelsHidden()

            DatePicker("To", selection: $dateTo, displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
