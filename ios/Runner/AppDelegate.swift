import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var attitudeChannel: DeviceAttitudeChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Orientamento del telefono per l'AR del Mountain Finder.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailShareDeviceAttitude") {
      let channel = DeviceAttitudeChannel()
      attitudeChannel = channel

      let methodChannel = FlutterMethodChannel(
        name: "com.trailshare.app/attitude",
        binaryMessenger: registrar.messenger()
      )
      methodChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          result(channel.isAvailable)
        case "setLocation":
          // Su iOS la posizione non serve: il reference frame
          // `xTrueNorthZVertical` è già riferito al nord geografico ed è il
          // sistema ad applicare la declinazione.
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let eventChannel = FlutterEventChannel(
        name: "com.trailshare.app/attitude_events",
        binaryMessenger: registrar.messenger()
      )
      eventChannel.setStreamHandler(channel)
    }
  }
}

/// Orientamento completo del telefono, per sovrapporre le etichette delle cime
/// all'immagine della fotocamera.
///
/// Perché non la bussola: `CLHeading` dice dove punta il **bordo alto** del
/// telefono, non l'obiettivo posteriore, e non dice nulla sul roll. Quando si
/// alza il telefono verso una cima le due cose divergono. `CMDeviceMotion` dà
/// invece l'assetto completo, fuso da giroscopio, accelerometro e magnetometro.
///
/// Verso Dart mandiamo la matrice di rotazione **device → ENU** (Est, Nord, Su)
/// row-major, riferita al nord **geografico**: la conversione in
/// azimut/pitch/roll e la proiezione stanno in Dart, dove si testano.
class DeviceAttitudeChannel: NSObject, FlutterStreamHandler {
  private let motion = CMMotionManager()
  private var eventSink: FlutterEventSink?

  /// Convenzione della matrice di rotazione, dedotta a runtime — vedi
  /// `resolveConvention`. `nil` finché non c'è abbastanza inclinazione per
  /// decidere; nel frattempo si usa l'interpretazione corpo→riferimento.
  private var matrixIsBodyToRef: Bool?

  private var usingTrueNorth = true

  var isAvailable: Bool { motion.isDeviceMotionAvailable }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard motion.isDeviceMotionAvailable else {
      return FlutterError(
        code: "no_sensor",
        message: "CMDeviceMotion non disponibile",
        details: nil
      )
    }
    eventSink = events

    // `xTrueNorthZVertical` fa applicare al sistema la declinazione magnetica
    // (nelle Alpi 3,5-4,5°, cioè ~70 px di sfasamento a FOV 60°). Richiede i
    // servizi di localizzazione attivi: se non c'è, si ripiega sul nord
    // magnetico e lo si dichiara a Dart.
    let available = CMMotionManager.availableAttitudeReferenceFrames()
    let frame: CMAttitudeReferenceFrame
    if available.contains(.xTrueNorthZVertical) {
      frame = .xTrueNorthZVertical
      usingTrueNorth = true
    } else {
      frame = .xMagneticNorthZVertical
      usingTrueNorth = false
    }

    motion.deviceMotionUpdateInterval = 1.0 / 30.0
    // Coda principale: il sink di Flutter va richiamato sul platform thread.
    motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
      guard let self = self, let data = data else { return }
      self.emit(data)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    eventSink = nil
    return nil
  }

  private func emit(_ data: CMDeviceMotion) {
    let r = data.attitude.rotationMatrix
    resolveConvention(data)

    // Matrice corpo → riferimento. Il reference frame è (X = nord,
    // Z = verticale) e quindi, essendo destrorso, Y = ovest.
    let bodyToRef = matrixIsBodyToRef ?? true
    let row1: (Double, Double, Double)
    let row2: (Double, Double, Double)
    let row3: (Double, Double, Double)
    if bodyToRef {
      row1 = (r.m11, r.m12, r.m13)
      row2 = (r.m21, r.m22, r.m23)
      row3 = (r.m31, r.m32, r.m33)
    } else {
      row1 = (r.m11, r.m21, r.m31)
      row2 = (r.m12, r.m22, r.m32)
      row3 = (r.m13, r.m23, r.m33)
    }

    // Da (Nord, Ovest, Su) a (Est, Nord, Su): Est = −Ovest, Nord = Nord.
    let m: [Double] = [
      -row2.0, -row2.1, -row2.2,
      row1.0, row1.1, row1.2,
      row3.0, row3.1, row3.2,
    ]

    // Il valore nil si omette invece di infilarlo nel dizionario: un
    // `Optional.none` dentro un `[String: Any?]` non attraversa il codec
    // standard, e dall'altra parte una chiave assente si legge già come null.
    var payload: [String: Any] = [
      "m": m,
      "screenRotation": screenRotationDeg(),
      "trueNorth": usingTrueNorth,
    ]
    if let accuracy = accuracyDeg(data) {
      payload["accuracy"] = accuracy
    }
    eventSink?(payload)
  }

  /// Apple non documenta in modo esplicito se `rotationMatrix` mappa
  /// corpo→riferimento o riferimento→corpo, e le due letture sono l'una la
  /// trasposta dell'altra: sbagliarla significa etichette completamente fuori
  /// posto. Invece di scommettere, la deduciamo dai dati.
  ///
  /// `gravity` è espressa nel sistema del **device**, quindi la verticale del
  /// mondo vista dal device è −gravity. Le due letture della matrice danno due
  /// candidati per quella stessa verticale: teniamo quella che coincide.
  ///
  /// La decisione si prende una volta sola e solo quando il telefono è
  /// abbastanza inclinato da rendere i due candidati distinguibili — a telefono
  /// piatto coincidono entrambi con la verticale e la scelta sarebbe casuale.
  private func resolveConvention(_ data: CMDeviceMotion) {
    guard matrixIsBodyToRef == nil else { return }
    let g = data.gravity
    let len = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
    guard len > 0.5 else { return }
    let up = (x: -g.x / len, y: -g.y / len, z: -g.z / len)

    let r = data.attitude.rotationMatrix
    // corpo→riferimento ⇒ la verticale nel device è la terza RIGA.
    let candidateA = (x: r.m31, y: r.m32, z: r.m33)
    // riferimento→corpo ⇒ è la terza COLONNA.
    let candidateB = (x: r.m13, y: r.m23, z: r.m33)

    func distance(_ v: (x: Double, y: Double, z: Double)) -> Double {
      let dx = v.x - up.x, dy = v.y - up.y, dz = v.z - up.z
      return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
    let dA = distance(candidateA)
    let dB = distance(candidateB)
    // Serve una separazione netta, altrimenti si aspetta il prossimo campione.
    guard abs(dA - dB) > 0.2 else { return }
    matrixIsBodyToRef = dA < dB
  }

  /// Rotazione della UI rispetto all'orientamento naturale del dispositivo.
  /// Serve a Dart per sapere quale asse del device è "destra dello schermo":
  /// in landscape non è più l'asse X, e i due landscape sono opposti fra loro.
  private func screenRotationDeg() -> Int {
    let orientation = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?
      .interfaceOrientation ?? .portrait
    switch orientation {
    case .landscapeRight: return 90
    case .portraitUpsideDown: return 180
    case .landscapeLeft: return 270
    default: return 0
    }
  }

  /// Incertezza indicativa della bussola in gradi, dallo stato di calibrazione
  /// del magnetometro. `nil` = inaffidabile, va suggerita la calibrazione.
  private func accuracyDeg(_ data: CMDeviceMotion) -> Double? {
    switch data.magneticField.accuracy {
    case .high: return 5.0
    case .medium: return 15.0
    case .low: return 30.0
    default: return nil
    }
  }
}
