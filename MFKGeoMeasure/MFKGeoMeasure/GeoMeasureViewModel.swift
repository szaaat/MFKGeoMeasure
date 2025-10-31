//
//  GeoMeasureViewModel.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import SwiftUI
import CoreLocation
import CoreMotion
import MapKit
import AVFoundation
import Combine

enum MeasurementMode: String, Codable {
    case gps
    case imu
}

class GeoMeasureViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var mode: MeasurementMode = .gps
    @Published var currentHeight: Double?
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var points: [MeasurementPoint] = []
    @Published var showImportSheet: Bool = false
    @Published var imuReferencePoint: MeasurementPoint?
    
    // --- HOZZÁADVA: Barométer tulajdonságok ---
    @Published var currentPressure: Double? // A UI számára
    private let altimeterManager = AltimeterManager()
    private var altimeterCancellable: AnyCancellable?
    private var pressureCancellable: AnyCancellable?
    // --- HOZZÁADÁS VÉGE ---
    
    private var locationManager = CLLocationManager()
    private var motionManager = CMMotionManager()
    private var geoidModel = GeoidModel()
    
    let imuManager = IMUMeasurementManager()
    let layerManager = MapLayerManager()
    let exportManager = ExportManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
        locationManager.activityType = .otherNavigation
        // --- HOZZÁADVA: Barométer figyelők beállítása ---
        if altimeterManager.isAvailable {
            setupAltimeterBindings()
        }
        // --- HOZZÁADÁS VÉGE ---
    }
    
    // --- HOZZÁADVA: Új privát függvény a barométer adatok kezelésére ---
    private func setupAltimeterBindings() {
        // 1. A nyomásadat átadása a UI-nak
        pressureCancellable = altimeterManager.$currentPressure
            .receive(on: RunLoop.main)
            .sink { [weak self] pressure in
                self?.currentPressure = (pressure > 0) ? pressure : nil
            }

        // 2. A relatív magasságadat továbbítása az IMU Managernek (ha IMU módban vagyunk)
        altimeterCancellable = altimeterManager.$relativeAltitude
            .receive(on: RunLoop.main)
            .sink { [weak self] relativeAltitude in
                guard let self = self else { return }

                if self.mode == .imu {
                    // Továbbítjuk a stabil vertikális adatot az IMU-nak
                    self.imuManager.updateVerticalWithBarometer(relativeAltitude: relativeAltitude)

                    // Frissítjük a fő kijelzőn látható magasságot is
                    if let referenceHeight = self.imuReferencePoint?.height {
                        self.currentHeight = referenceHeight + relativeAltitude
                    }
                }
            }
    }
    // --- HOZZÁADÁS VÉGE ---
    
    func toggleMode() {
        switch mode {
        case .gps:
            stopGPS()
            if let lastPoint = points.last {
                startIMUWithReference(lastPoint)
            } else {
                // Need manual reference if no points
            }
            mode = .imu
        case .imu:
            // --- MÓDOSÍTVA ---
            stopIMU() // Különválasztva az IMU és Barométer leállítása
            // --- MÓDOSÍTÁS VÉGE ---
            startGPS()
            mode = .gps
        }
    }
    
    // MARK: - GPS Mode
    func startGPS() {
        locationManager.startUpdatingLocation()
    }
    
    func stopGPS() {
        locationManager.stopUpdatingLocation()
    }
    
    // --- HOZZÁADVA: Új függvény az IMU és a barométer leállítására ---
    func stopIMU() {
        imuManager.stopIMUMeasurement()
        if altimeterManager.isAvailable {
            altimeterManager.stop()
        }
        imuReferencePoint = nil
    }
    // --- HOZZÁADÁS VÉGE ---
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentCoordinate = loc.coordinate
        let ellipsoidalHeight = loc.altitude
        let N = geoidModel.value(atLatitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        currentHeight = ellipsoidalHeight - N
    }
    
    // MARK: - IMU Mode
    func startIMUWithReference(_ point: MeasurementPoint) {
        imuReferencePoint = point
        imuManager.setReferencePoint(point)
        imuManager.startIMUMeasurement(from: point)
        // --- HOZZÁADVA: Barométer indítása IMU módban ---
        if altimeterManager.isAvailable {
            altimeterManager.start()
        }
        // --- HOZZÁADÁS VÉGE ---
        mode = .imu
    }
    
    func calibrateIMU(to point: MeasurementPoint) {
        imuManager.calibrate(to: point)
    }
    
    // MARK: - Capture Point
    func captureCurrentPoint() {
        var newPoint: MeasurementPoint?
        switch mode {
        case .gps:
            if let coord = currentCoordinate, let height = currentHeight {
                newPoint = MeasurementPoint(coordinate: coord, height: height, accuracy: locationManager.location?.horizontalAccuracy, mode: .gps)
            }
        case .imu:
            // --- MÓDOSÍTVA: A magasság már a barométerből jön ---
            // Az IMU manager a barométer adatot használja a Z tengelyhez
            newPoint = imuManager.getCurrentMeasurement()
            // --- MÓDOSÍTÁS VÉGE ---
        }
        if let point = newPoint {
            points.append(point)
            playSuccessSound()
        }
    }
    
    func deletePoint(at offsets: IndexSet) {
        points.remove(atOffsets: offsets)
    }
    
    func shouldSwitchToIMU() -> Bool {
        let gpsAccuracy = locationManager.location?.horizontalAccuracy ?? 0
        return gpsAccuracy > 5.0
    }
    
    private func playSuccessSound() {
        AudioServicesPlaySystemSound(1104) // Beep sound
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate)) // Vibration
    }
}
