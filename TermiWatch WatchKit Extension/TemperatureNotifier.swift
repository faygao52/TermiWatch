import CoreLocation
import Foundation
import PMKCoreLocation
import PMKFoundation
import PromiseKit

func OpenWeatherMapAPIKey() -> String {
  return Bundle.main.object(
    forInfoDictionaryKey: "OpenWeatherMapAPIKey"
  ) as! String
}

func OpenWeatherMapURL(
  coordinate: CLLocationCoordinate2D,
  apiKey: String = OpenWeatherMapAPIKey()
) -> URL {
  return URL(
    string: "https://api.openweathermap.org/data/2.5/weather?"
      + "lat=\(coordinate.latitude)"
      + "&lon=\(coordinate.longitude)"
      + "&APPID=\(apiKey)"
  )!
}

let disabledCachingConfig: (URLSessionConfiguration) -> Void = {
  $0.requestCachePolicy = .reloadIgnoringLocalCacheData
  $0.urlCache = nil
}

struct Weather: Codable {
  let main: String
  let description: String
}

struct OpenWeatherMapResponse: Codable {
  struct MainResponse: Codable {
    let temp: Double
  }
 
  let main: MainResponse
  let weather: [Weather]
}

public struct WeatherInfo {
  var weather: Weather?
  var temperature: Measurement<UnitTemperature>
}

func temperatureInKelvin(at coordinate: CLLocationCoordinate2D)
  -> Promise<WeatherInfo> {
  return Promise { seal in
    let sessionConfig = URLSessionConfiguration.default
    disabledCachingConfig(sessionConfig)

    URLSession(configuration: sessionConfig).dataTask(
      .promise,
      with: OpenWeatherMapURL(coordinate: coordinate)
    ).compactMap {
      try JSONDecoder().decode(OpenWeatherMapResponse.self, from: $0.data)
    }.done {
      let temperatureInKelvin = Measurement(
        value: $0.main.temp,
        unit: UnitTemperature.kelvin
      )

      let weatherInfo = WeatherInfo(
        weather: $0.weather.first,
        temperature: temperatureInKelvin
      )
      seal.fulfill(weatherInfo)
    }.catch {
      print("Error:", $0)
    }
  }
}

public class TemperatureNotifier {
  public static let TemperatureDidChangeNotification = Notification.Name(
    rawValue: "TemperatureNotifier.TemperatureDidChangeNotification"
  )

  public static let shared = TemperatureNotifier()
  private init() {}

  public private(set) var weatherInfo: WeatherInfo?
  private var timer: Timer?

  public var isStarted: Bool {
    return timer != nil && timer!.isValid
  }

  public func start(withTimeInterval interval: TimeInterval = 600) {
    timer?.invalidate()

    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in
      CLLocationManager.requestLocation().lastValue.then {
        temperatureInKelvin(at: $0.coordinate)
      }.done { currentTemperature in
          if currentTemperature.temperature == self?.weatherInfo?.temperature {
          return
        }
        self?.weatherInfo = currentTemperature

        NotificationCenter.default.post(
          Notification(
            name: TemperatureNotifier.TemperatureDidChangeNotification,
            object: self?.weatherInfo,
            userInfo: nil
          )
        )
      }.catch {
        print("Error:", $0.localizedDescription)
      }
    }

    timer!.fire()
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }
}
