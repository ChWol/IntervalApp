import SwiftUI
import Combine

struct HourProgressView: View {
    @State private var currentDate: Date = Date()
    @Environment(\.colorScheme) private var colorScheme
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    private var calendar: Calendar { Calendar.current }
    
    private var startHour: Int {
        calendar.component(.hour, from: currentDate)
    }
    
    private var nextHour: Int {
        (startHour + 1) % 24
    }
    
    private var minuteOfHour: Int {
        calendar.component(.minute, from: currentDate)
    }
    
    private var secondOfMinute: Int {
        calendar.component(.second, from: currentDate)
    }
    
    private var progress: Double {
        let totalSeconds = Double(minuteOfHour * 60 + secondOfMinute)
        return min(1.0, max(0.0, totalSeconds / 3600.0))
    }
    
    private var remainingMinutes: Int {
        max(0, 60 - minuteOfHour)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header row: Start Time | Remaining Countdown | End Time
            HStack {
                Text(String(format: "%02d:00", startHour))
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("\(remainingMinutes)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.primary)
                    Text("MIN LEFT".localized)
                        .font(.system(size: 9, weight: .light, design: .default))
                        .tracking(1.5)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%02d:00", nextHour))
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // Ultra-fine timeline progress track
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Background track hairline
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .frame(height: 2)
                    
                    // Quarter-hour tick indicators
                    HStack {
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 4)
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 6)
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 4)
                        Spacer()
                    }
                    
                    // Filled progress bar
                    Capsule()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: max(4, w * CGFloat(progress)), height: 2)
                    
                    // Minimalist indicator dot
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.primary.opacity(0.3), radius: 2)
                        .offset(x: max(0, min(w - 6, w * CGFloat(progress) - 3)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
        .onReceive(timer) { newDate in
            currentDate = newDate
        }
    }
}
