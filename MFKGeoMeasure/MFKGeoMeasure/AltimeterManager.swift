//
//  AltimeterManager.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 31.
//

import Foundation
import CoreMotion
import Combine

class AltimeterManager: ObservableObject {
    
    private let altimeter = CMAltimeter()
    
    /// A mérés kezdete óta számított relatív magasságváltozás méterben.
    @Published var relativeAltitude: Double = 0.0
    
    /// Az aktuális légnyomás kilopascalban (kPa).
    @Published var currentPressure: Double = 0.0
    
    /// Jelzi, hogy a barométer elérhető-e az eszközön.
    @Published var isAvailable: Bool = CMAltimeter.isRelativeAltitudeAvailable()
    
    /**
     Elindítja a relatív magasság és légnyomás frissítéseinek figyelését.
     */
    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("Altimeter is not available on this device.")
            isAvailable = false
            return
        }
        
        isAvailable = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else {
                if let error = error {
                    print("Altimeter error: \(error.localizedDescription)")
                }
                return
            }
            
            // Közzétesszük a relatív magasságot (méter)
            self.relativeAltitude = data.relativeAltitude.doubleValue
            
            // Közzétesszük a nyomást (kPa)
            self.currentPressure = data.pressure.doubleValue
        }
    }
    
    /**
     Leállítja a magasság- és légnyomásadatok figyelését.
     */
    func stop() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.stopRelativeAltitudeUpdates()
        }
        // Visszaállítjuk az értékeket, amikor leállítjuk
        relativeAltitude = 0.0
        currentPressure = 0.0
    }
}

