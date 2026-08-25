import SwiftUI
import Combine

struct HourProgressView: View {
    @State private var currentDate: Date = Date()
    var showRing: Bool = true
    var fontSize: CGFloat = 12
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    private var minuteOfHour: Int {
        Calendar.current.component(.minute, from: currentDate)
    }
    
    private var secondOfMinute: Int {
        Calendar.current.component(.second, from: currentDate)
    }
    
    private var progress: Double {
        let totalSeconds = Double(minuteOfHour * 60 + secondOfMinute)
        return min(1.0, max(0.0, totalSeconds / 3600.0))
    }
    
    private var remainingMinutes: Int {
        let rem = 60 - minuteOfHour
        return max(0, rem)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if showRing {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 2)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: fontSize * 1.3, height: fontSize * 1.3)
            }
            
            Text("\(remainingMinutes)m \("left".localized)")
                .font(.system(size: fontSize, weight: .light, design: .default))
                .foregroundColor(.secondary)
        }
        .onReceive(timer) { newDate in
            currentDate = newDate
        }
    }
}
