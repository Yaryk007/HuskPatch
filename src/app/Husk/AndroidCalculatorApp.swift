// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// HuskPatch: Android OS mode's Calculator, after AOSP's: the expression at the top with its result worked out as it is
/// typed, Material 3 Expressive's round keys below, and the scientific row (√, π, ^, !, %) slid open from the top of the pad.
struct AndroidCalculatorApp: View {
    @State private var expression = ""
    @State private var shownResult: String?
    @State private var scientific = false
    @State private var history: [(String, String)] = []

    private let rows: [[String]] = [["AC", "( )", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]]
    private let sci: [String] = ["√", "π", "^", "!", "e"]

    private var preview: String? {
        guard !expression.isEmpty, let v = CalcParser.evaluate(expression) else { return nil }
        let r = CalcParser.format(v)
        return r == expression ? nil : r
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 8) {
                Spacer()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                            Text(h.0 + " = " + h.1).font(.system(size: 18, design: .rounded))
                                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxHeight: 120)
                Text(expression.isEmpty ? "0" : expression)
                    .font(.system(size: shownResult == nil ? 56 : 34, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: shownResult == nil ? Material3.onSurface : Material3.onSurfaceVariant))
                    .lineLimit(2).minimumScaleFactor(0.4)
                    .textSelection(.enabled)
                Text(shownResult ?? preview ?? " ")
                    .font(.system(size: shownResult == nil ? 30 : 56, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(uiColor: shownResult == nil ? Material3.onSurfaceVariant : Material3.onSurface))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shownResult)

            VStack(spacing: 10) {
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { scientific.toggle() } } label: {
                    Image(systemName: "chevron.up").rotationEffect(.degrees(scientific ? 180 : 0))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: Material3.onSurfaceVariant))
                .accessibilityLabel("Scientific functions")
                if scientific {
                    HStack(spacing: 10) {
                        ForEach(sci, id: \.self) { k in key(k, kind: .function, height: 48) }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { k in key(k, kind: kind(k)) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .background(Color(uiColor: Material3.surfaceContainer), in: StackedCorners(top: 28, bottom: 0))
        }
        .background(Color(uiColor: Material3.surface))
    }

    private enum Kind { case digit, op, function, clear, equals }

    private func kind(_ k: String) -> Kind {
        switch k {
        case "AC": return .clear
        case "=": return .equals
        case "÷", "×", "−", "+": return .op
        case "( )", "%", "⌫": return .function
        default: return .digit
        }
    }

    private func key(_ k: String, kind: Kind, height: CGFloat = 76) -> some View {
        let (bg, fg): (UIColor, UIColor) = {
            switch kind {
            case .digit: return (Material3.surfaceContainerHighest, Material3.onSurface)
            case .op: return (Material3.secondaryContainer, Material3.onSecondaryContainer)
            case .function: return (Material3.surfaceContainerHigh, Material3.onSurface)
            case .clear: return (Material3.tertiaryContainer, Material3.onTertiaryContainer)
            case .equals: return (Material3.primary, Material3.onPrimary)
            }
        }()
        return Button { press(k) } label: {
            Group {
                if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 22, weight: .medium)) }
                else { Text(k).font(.system(size: kind == .digit ? 30 : 26, weight: .regular, design: .rounded)) }
            }
            .foregroundStyle(Color(uiColor: fg))
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Color(uiColor: bg), in: RoundedRectangle(cornerRadius: kind == .equals || kind == .op ? 24 : height / 2, style: .continuous))
        }
        .buttonStyle(AndroidSquashStyle())
        .accessibilityLabel(k)
    }

    private func press(_ k: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if shownResult != nil, k != "=" {
            // after =, an operator carries on from the result, a digit starts over
            if ["÷", "×", "−", "+", "^", "%", "!"].contains(k) { expression = shownResult! } else if k != "⌫" { expression = "" }
            shownResult = nil
        }
        switch k {
        case "AC": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        case "=":
            if let v = CalcParser.evaluate(expression) {
                let r = CalcParser.format(v)
                history.append((expression, r))
                if history.count > 20 { history.removeFirst() }
                shownResult = r
            } else if !expression.isEmpty {
                shownResult = "Error"
            }
        case "( )":
            let open = expression.filter { $0 == "(" }.count, close = expression.filter { $0 == ")" }.count
            let last = expression.last
            if open > close, let l = last, l.isNumber || l == ")" || l == "π" || l == "e" || l == "!" || l == "%" { expression += ")" }
            else { expression += (last.map { $0.isNumber || $0 == ")" } ?? false) ? "×(" : "(" }
        case "√": expression += "√("
        default: expression += k
        }
    }
}

/// The calculator's arithmetic: + − × ÷, ^, %, !, √, π, e and brackets, by recursive descent (unclosed brackets close at the end).
enum CalcParser {
    static func evaluate(_ s: String) -> Double? {
        var p = Parser(Array(s.replacingOccurrences(of: " ", with: "")))
        guard let v = p.expression(), p.i == p.c.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.maximumSignificantDigits = 12
        f.usesSignificantDigits = true
        f.numberStyle = abs(v) >= 1e15 || abs(v) < 1e-9 ? .scientific : .decimal
        f.usesGroupingSeparator = false
        f.decimalSeparator = "."
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "−" || c[i] == "-" {
                let op = c[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < c.count {
                if c[i] == "×" || c[i] == "*" || c[i] == "÷" || c[i] == "/" {
                    let op = c[i]; i += 1
                    guard let r = power() else { return nil }
                    v = (op == "×" || op == "*") ? v * r : v / r
                } else if c[i] == "(" || c[i] == "π" || c[i] == "√" || c[i] == "e" {
                    // implied multiplication: 2π, 3(4), 2√9
                    guard let r = power() else { return nil }
                    v *= r
                } else { break }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if i < c.count, c[i] == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }

        mutating func unary() -> Double? {
            if i < c.count, c[i] == "−" || c[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < c.count, c[i] == "√" { i += 1; return unary().map { $0.squareRoot() } }
            return postfix()
        }

        mutating func postfix() -> Double? {
            guard var v = primary() else { return nil }
            while i < c.count {
                if c[i] == "%" { v /= 100; i += 1 }
                else if c[i] == "!" {
                    guard v >= 0, v == v.rounded(), v <= 170 else { return nil }
                    v = (1...max(1, Int(v))).reduce(1.0) { $0 * Double($1) }
                    i += 1
                } else { break }
            }
            return v
        }

        mutating func primary() -> Double? {
            guard i < c.count else { return nil }
            if c[i] == "(" {
                i += 1
                let v = expression()
                if i < c.count, c[i] == ")" { i += 1 }
                return v
            }
            if c[i] == "π" { i += 1; return .pi }
            if c[i] == "e" { i += 1; return M_E }
            let start = i
            while i < c.count, c[i].isNumber || c[i] == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(c[start..<i]))
        }
    }
}
