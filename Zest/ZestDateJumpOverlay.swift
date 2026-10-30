//
//  ZestDateJumpOverlay.swift
//  Zest
//
//  Compact in-panel date jump dialog using the same visual language as
//  Clipboard's destructive-action confirmation.
//

import SwiftUI

struct ZestDateJumpOverlay: View {
    let initialDate: Date
    let accentColor: Color
    let onCancel: () -> Void
    let onJump: (Date) -> Void

    @State private var dateText = ""
    @FocusState private var fieldFocused: Bool

    init(
        initialDate: Date,
        accentColor: Color,
        onCancel: @escaping () -> Void,
        onJump: @escaping (Date) -> Void
    ) {
        self.initialDate = initialDate
        self.accentColor = accentColor
        self.onCancel = onCancel
        self.onJump = onJump
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                    Image(systemName: "pointer.arrow.motionlines")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 36, height: 36)

                Text("Jump to…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                TextField("DD / MM / YYYY", text: $dateText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                fieldFocused
                                    ? accentColor.opacity(0.48)
                                    : Color.white.opacity(0.22),
                                lineWidth: fieldFocused ? 1.0 : 0.7
                            )
                    }
                    .onChange(of: dateText) { _, value in
                        let formatted = formatContinuousDateInput(value)
                        if formatted != value {
                            dateText = formatted
                        }
                    }
                    .onSubmit {
                        guard let date = parsedDate else { return }
                        onJump(date)
                    }

                HStack(spacing: 7) {
                    compactButton("Cancel", primary: false) {
                        onCancel()
                    }

                    compactButton("Jump", primary: true) {
                        guard let date = parsedDate else { return }
                        onJump(date)
                    }
                    .disabled(parsedDate == nil)
                    .opacity(parsedDate == nil ? 0.48 : 1)
                }
            }
            .padding(15)
            .frame(width: 238)
            .background {
                ZStack {
                    Color.clear
                        .glassEffect(
                            .regular.tint(accentColor.opacity(0.045)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.065),
                                    Color.clear,
                                    Color.black.opacity(0.035)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.72),
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            }
            .shadow(color: Color.black.opacity(0.20), radius: 15, y: 8)
            .shadow(color: accentColor.opacity(0.07), radius: 10, y: 4)
        }
        .transition(.scale(scale: 0.97).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.async {
                fieldFocused = true
            }
        }
    }

    private func formatContinuousDateInput(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(8))

        switch digits.count {
        case 0:
            return ""
        case 1...2:
            return digits
        case 3...4:
            let day = String(digits.prefix(2))
            let month = String(digits.dropFirst(2))
            return "\(day) / \(month)"
        default:
            let day = String(digits.prefix(2))
            let month = String(digits.dropFirst(2).prefix(2))
            let year = String(digits.dropFirst(4))
            return "\(day) / \(month) / \(year)"
        }
    }

    private func compactButton(
        _ title: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(primary ? accentColor.opacity(0.92) : Color.primary.opacity(0.045))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(primary ? 0.30 : 0.22), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var parsedDate: Date? {
        let digits = String(dateText.filter(\.isNumber))
        guard digits.count == 8 else { return nil }

        let dayText = String(digits.prefix(2))
        let monthText = String(digits.dropFirst(2).prefix(2))
        let yearText = String(digits.dropFirst(4).prefix(4))

        guard
            let day = Int(dayText),
            let month = Int(monthText),
            let year = Int(yearText),
            (1...31).contains(day),
            (1...12).contains(month),
            (1900...9999).contains(year)
        else { return nil }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let date = Calendar.current.date(from: components) else { return nil }
        let check = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
