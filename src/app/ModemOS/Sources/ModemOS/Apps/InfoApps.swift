import SwiftUI
import MapKit
import CoreLocation
import CoreMotion
import EventKit
import Charts

// MARK: - Maps

/// iOS 17's SwiftUI Map; iOS 16 gets MapKit's own view with the same location, compass and scale.
struct MapsApp: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            ModernMapsApp()
        } else {
            LegacyMapView().ignoresSafeArea()
        }
    }
}

private struct LegacyMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        LocationProvider.shared.start()
        let map = MKMapView()
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.setUserTrackingMode(.follow, animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {}
}

@available(iOS 17.0, *)
private struct ModernMapsApp: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var location = LocationProvider.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var satellite = false

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: $selected) {
                UserAnnotation()
                ForEach(results, id: \.self) { item in
                    Marker(item.name ?? "", coordinate: item.placemark.coordinate)
                        .tag(item)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()

            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(os.t("Search places"), text: $query)
                        .submitLabel(.search)
                        .onSubmit(search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .glass(Capsule(), tint: 1.5)

                Button {
                    satellite.toggle()
                } label: {
                    Image(systemName: satellite ? "map" : "globe.europe.africa.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 46, height: 46)
                        .glass(Circle(), tint: 1.5)
                }
            }
            .padding(.horizontal, 14)

            if let item = selected {
                VStack {
                    Spacer()
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name ?? "").font(.system(size: 20, weight: .bold))
                            Text(item.placemark.title ?? "").font(.system(size: 14)).foregroundColor(.secondary)
                            Button(os.t("Directions")) {
                                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                            }
                            .buttonStyle(OSButtonStyle(.filled))
                        }
                    }
                    .padding(14)
                }
            }
        }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
    }

    private func search() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let here = location.location {
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000)
        }
        MKLocalSearch(request: request).start { response, error in
            results = response?.mapItems ?? []
            OSLogger.shared.log("Maps", "Search \"\(query)\": \(results.count) results")
            if let first = results.first {
                withAnimation {
                    position = .region(MKCoordinateRegion(center: first.placemark.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000))
                }
            }
        }
    }
}

// MARK: - Weather (live data from Open-Meteo for where the phone is)

struct WeatherReport: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let wind_speed_10m: Double
        let weather_code: Int
        let is_day: Int
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
    }

    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily
}

final class WeatherModel: ObservableObject {
    @Published private(set) var report: WeatherReport?
    @Published private(set) var place = ""
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var fetchedFor: CLLocation?

    func fetch(for location: CLLocation) {
        if let last = fetchedFor, last.distance(from: location) < 2000, report != nil { return }
        fetchedFor = location
        loading = true
        let c = location.coordinate
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)"
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=7")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.loading = false
                if let data = data, let report = try? JSONDecoder().decode(WeatherReport.self, from: data) {
                    self.report = report
                    self.error = nil
                    OSLogger.shared.log("Weather", "Updated: \(Int(report.current.temperature_2m))°")
                } else {
                    self.error = error?.localizedDescription ?? "Could not load the weather"
                    OSLogger.shared.log("Weather", self.error ?? "", level: .error)
                }
            }
        }
        .resume()
        CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
            DispatchQueue.main.async {
                self.place = marks?.first?.locality ?? marks?.first?.name ?? ""
            }
        }
    }

    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func name(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }
}

struct WeatherApp: View {
    @EnvironmentObject private var os: OSSettings
    @ObservedObject private var location = LocationProvider.shared
    @StateObject private var weather = WeatherModel()

    var body: some View {
        ZStack {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if !location.allowed && location.authorization != .notDetermined {
                PermissionView(
                    symbol: "location.fill",
                    title: "Weather needs your location",
                    message: "Allow location access to show the weather where you are.",
                    denied: true,
                    request: {}
                )
                .foregroundColor(.white)
            } else if let report = weather.report {
                forecast(report)
            } else if let error = weather.error {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 44))
                    Text(os.t(error)).multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                .padding(30)
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(os.t("Finding your location…")).foregroundColor(.white)
                }
            }
        }
        .onAppear {
            location.start()
            if let here = location.location { weather.fetch(for: here) }
        }
        .onDisappear { location.stop() }
        .onChange(of: location.location) { here in
            if let here = here { weather.fetch(for: here) }
        }
    }

    private var skyColors: [Color] {
        guard let report = weather.report else { return [rgb(70, 130, 220), rgb(120, 180, 240)] }
        if report.current.is_day == 0 { return [rgb(15, 25, 60), rgb(45, 60, 110)] }
        switch report.current.weather_code {
        case 0, 1, 2: return [rgb(50, 130, 240), rgb(130, 200, 250)]
        case 61...67, 80...82, 95...99: return [rgb(60, 70, 90), rgb(110, 125, 150)]
        default: return [rgb(100, 130, 170), rgb(160, 185, 210)]
        }
    }

    private func forecast(_ report: WeatherReport) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(weather.place.isEmpty ? os.t("My location") : weather.place)
                        .font(.system(size: 30, weight: .semibold))
                    Text("\(Int(report.current.temperature_2m.rounded()))°")
                        .font(OSSettings.shared.display(96, weight: .light))
                    Label(os.t(WeatherModel.name(report.current.weather_code)), systemImage: WeatherModel.symbol(report.current.weather_code, day: report.current.is_day == 1))
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                    if let high = report.daily.temperature_2m_max.first, let low = report.daily.temperature_2m_min.first {
                        Text("H:\(Int(high.rounded()))°  L:\(Int(low.rounded()))°").font(.system(size: 17, weight: .medium))
                    }
                }
                .padding(.top, 20)

                hourly(report)

                VStack(spacing: 0) {
                    ForEach(0..<report.daily.time.count, id: \.self) { index in
                        HStack {
                            Text(dayName(report.daily.time[index], index))
                                .frame(width: 90, alignment: .leading)
                            Image(systemName: WeatherModel.symbol(report.daily.weather_code[index]))
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 36)
                            Spacer()
                            Text("\(Int(report.daily.temperature_2m_min[index].rounded()))°").opacity(0.7)
                            Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 80, height: 5)
                            Text("\(Int(report.daily.temperature_2m_max[index].rounded()))°")
                        }
                        .font(.system(size: 17, weight: .medium))
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 12) {
                    tile("thermometer.medium", "Feels like", "\(Int(report.current.apparent_temperature.rounded()))°")
                    tile("humidity.fill", "Humidity", "\(Int(report.current.relative_humidity_2m))%")
                    tile("wind", "Wind", "\(Int(report.current.wind_speed_10m.rounded())) km/h")
                }
                Text("Open-Meteo.com").font(.system(size: 11)).opacity(0.6)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .environment(\.colorScheme, .dark)
    }

    private func hourly(_ report: WeatherReport) -> some View {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let start = report.hourly.time.firstIndex { (formatter.date(from: $0 + ":00") ?? .distantPast) > now.addingTimeInterval(-3600) } ?? 0
        let range = start..<min(start + 24, report.hourly.time.count)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(range), id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(index == start ? os.t("Now") : String(report.hourly.time[index].suffix(5).prefix(2)))
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: WeatherModel.symbol(report.hourly.weather_code[index]))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 20))
                        Text("\(Int(report.hourly.temperature_2m[index].rounded()))°")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .padding(16)
        }
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func tile(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(os.t(title), systemImage: symbol).font(.system(size: 12, weight: .semibold)).opacity(0.75)
            Text(value).font(.system(size: 22, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dayName(_ string: String, _ index: Int) -> String {
        if index == 0 { return os.t("Today") }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: string) else { return string }
        let formatter = DateFormatter()
        formatter.locale = os.language.locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).capitalized
    }
}

// MARK: - Calendar

final class CalendarModel: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var allowed = false
    let store = EKEventStore()

    func load(for day: Date) {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { allowed = status == .fullAccess } else { allowed = status == .authorized }
        guard allowed else { return }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func request(then day: Date) {
        let done: (Bool, Error?) -> Void = { _, _ in DispatchQueue.main.async { self.load(for: day) } }
        if #available(iOS 17.0, *) { store.requestFullAccessToEvents(completion: done) } else { store.requestAccess(to: .event, completion: done) }
    }
}

struct CalendarApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var model = CalendarModel()
    @State private var month = Date()
    @State private var selected = Date()

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 12) {
            HStack {
                AppTitle(title: monthTitle, subtitle: nil)
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .padding(.horizontal, 10)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .padding(.trailing, 20)
            }
            .font(.system(size: 20, weight: .semibold))

            HStack {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { pair in
                    Text(pair.element).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { pair in
                    if let day = pair.element {
                        let isToday = calendar.isDateInToday(day)
                        let isSelected = calendar.isDate(day, inSameDayAs: selected)
                        Button {
                            selected = day
                            model.load(for: day)
                        } label: {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 17, weight: isToday ? .bold : .regular))
                                .foregroundColor(isToday ? .white : (isSelected ? Color.osAccent : .primary))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle().fill(isToday ? Color.red : (isSelected ? Color.osAccent.opacity(0.18) : Color.clear))
                                )
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .padding(.horizontal, 12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTitle).font(.system(size: 17, weight: .semibold))
                if !model.allowed {
                    Button(os.t("Show my events")) { model.request(then: selected) }
                } else if model.events.isEmpty {
                    Text(os.t("No events")).foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.events, id: \.eventIdentifier) { event in
                                HStack(spacing: 10) {
                                    Capsule().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title ?? "").font(.system(size: 16, weight: .semibold))
                                        Text(event.isAllDay ? os.t("All day") : timeRange(event)).font(.system(size: 13)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { model.load(for: selected) }
    }

    private var formatterLocale: Locale { os.language.locale }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = formatterLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: month).capitalized
    }

    private var selectedTitle: String {
        let formatter = DateFormatter()
        formatter.locale = formatterLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: selected).capitalized
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = formatterLocale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The days of the shown month, padded with nils so the first one sits under its weekday.
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let padding = (weekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: padding)
        for offset in 0..<count {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    private func shift(_ months: Int) {
        Haptics.tap()
        withAnimation(.easeInOut(duration: 0.2)) {
            month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    private func timeRange(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = os.clock24h ? "HH:mm" : "h:mm a"
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }
}

// MARK: - Health (steps from the motion coprocessor)

final class HealthModel: ObservableObject {
    struct Day: Identifiable {
        let id: Date
        let steps: Int
    }

    @Published private(set) var steps = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var floors = 0
    @Published private(set) var week: [Day] = []
    @Published private(set) var available = CMPedometer.isStepCountingAvailable()
    @Published private(set) var denied = false

    private let pedometer = CMPedometer()

    func start() {
        guard available else { return }
        let today = Calendar.current.startOfDay(for: Date())
        pedometer.startUpdates(from: today) { data, error in
            DispatchQueue.main.async {
                if let error = error as NSError?, error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                    self.denied = true
                    return
                }
                guard let data = data else { return }
                self.steps = data.numberOfSteps.intValue
                self.distance = data.distance?.doubleValue ?? 0
                self.floors = data.floorsAscended?.intValue ?? 0
            }
        }
        loadWeek()
    }

    func stop() {
        pedometer.stopUpdates()
    }

    private func loadWeek() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [Day] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for back in 0..<7 {
            guard let start = calendar.date(byAdding: .day, value: -back, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            group.enter()
            pedometer.queryPedometerData(from: start, to: min(end, Date())) { data, _ in
                lock.lock()
                days.append(Day(id: start, steps: data?.numberOfSteps.intValue ?? 0))
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.week = days.sorted { $0.id < $1.id }
        }
    }
}

struct HealthApp: View {
    @EnvironmentObject private var os: OSSettings
    @StateObject private var health = HealthModel()
    private let goal = 6000

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AppTitle(title: "Health", subtitle: os.t("Today"))

                if !health.available {
                    Text(os.t("Step counting is not available on this device")).foregroundColor(.secondary).padding()
                } else if health.denied {
                    PermissionView(
                        symbol: "figure.walk",
                        title: "Health needs Motion & Fitness",
                        message: "Allow Motion & Fitness access to count your steps.",
                        denied: true,
                        request: {}
                    )
                } else {
                    ZStack {
                        Circle().stroke(Color.pink.opacity(0.15), lineWidth: 22)
                        Circle()
                            .trim(from: 0, to: min(1, CGFloat(health.steps) / CGFloat(goal)))
                            .stroke(Color.pink, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.8, dampingFraction: 0.8), value: health.steps)
                        VStack(spacing: 4) {
                            Image(systemName: "figure.walk").font(.system(size: 28)).foregroundColor(.pink)
                            Text("\(health.steps)").font(.system(size: 44, weight: .bold)).monospacedDigit()
                            Text(os.t("of") + " \(goal) " + os.t("steps")).font(.system(size: 14)).foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 230, height: 230)
                    .padding(.vertical, 10)

                    HStack(spacing: 12) {
                        stat("point.topleft.down.to.point.bottomright.curvepath.fill", String(format: "%.2f km", health.distance / 1000), "Distance")
                        stat("stairs", "\(health.floors)", "Floors")
                        stat("flame.fill", "\(Int(Double(health.steps) * 0.04)) kcal", "Energy")
                    }
                    .padding(.horizontal, 16)

                    if !health.week.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(os.t("Last 7 days")).font(.system(size: 17, weight: .semibold))
                                Chart(health.week) { day in
                                    BarMark(
                                        x: .value("Day", day.id, unit: .day),
                                        y: .value("Steps", day.steps)
                                    )
                                    .foregroundStyle(Color.pink.gradient)
                                    .cornerRadius(6)
                                }
                                .frame(height: 170)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear { health.start() }
        .onDisappear { health.stop() }
    }

    private func stat(_ symbol: String, _ value: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundColor(.pink)
            Text(value).font(.system(size: 17, weight: .bold))
            Text(os.t(title)).font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.osCard))
    }
}
