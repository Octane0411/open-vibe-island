import SwiftUI

struct MusicCustomSliderView: View {
    @Environment(\.isEnabled) var isEnabled

    @Binding var value: CGFloat
    @Binding var isDragging: Bool

    @State private var lastOffset: CGFloat = 0
    @State private var sliderHeight: CGFloat = 7

    let range: ClosedRange<CGFloat>
    var onEndedDragging: ((DragGesture.Value) -> Void)?

    init(
        value: Binding<CGFloat>,
        isDragging: Binding<Bool>,
        range: ClosedRange<CGFloat>,
        sliderHeight: CGFloat = 7,
        onEndedDragging: ((DragGesture.Value) -> Void)? = nil
    ) {
        _value = value
        _isDragging = isDragging
        self.range = range
        self.sliderHeight = sliderHeight
        self.onEndedDragging = onEndedDragging
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.85))
                    .opacity(isEnabled ? 1 : 0.25)
                    .frame(height: sliderHeight)
                    .cornerRadius(5)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: leadingWidth(geometry), height: sliderHeight)
                    }

                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .opacity(isEnabled ? 1 : 0.25)
                    .frame(height: sliderHeight)
                    .cornerRadius(5)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geometry))
        }
        .frame(height: sliderHeight)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                sliderHeight += hovering ? 3 : -3
            }
        }
    }

    private func knobOffset(_ geometry: GeometryProxy) -> CGFloat {
        max(0, value.musicMap(from: range, to: 0...geometry.size.width))
    }

    private func leadingWidth(_ geometry: GeometryProxy) -> CGFloat {
        max(0, knobOffset(geometry))
    }

    private func dragGesture(_ geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                isDragging = true
                let clamped = drag.location.x.musicClamped(to: 0...geometry.size.width)
                value = clamped.musicMap(from: 0...geometry.size.width, to: range)
            }
            .onEnded { drag in
                isDragging = false
                onEndedDragging?(drag)
            }
    }
}
