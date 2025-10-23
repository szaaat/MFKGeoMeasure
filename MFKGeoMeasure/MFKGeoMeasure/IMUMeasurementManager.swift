//
//  IMUMeasurementManager.swift
//  MFKGeoMeasure
//
//  Created by Szamosi Attila on 2025. 10. 19..
//

import CoreMotion
import simd
import Combine

class IMUMeasurementManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var timer: Timer?
    
    @Published var currentPosition = SIMD3<Double>(0, 0, 0)
    @Published var currentAttitude = SIMD3<Double>(0, 0, 0)
    @Published var accuracyEstimate: Double = 0.0
    @Published var isCalibrated: Bool = false
    
    private var referencePoint: MeasurementPoint?
    private var driftCorrection = SIMD3<Double>(0, 0, 0)
    private var lastUpdateTime: Date?
    private var velocity = SIMD3<Double>(0, 0, 0)
    
    private var accelerationFilter = LowPassFilter(cutoffFrequency: 0.1)
    private var gyroFilter = LowPassFilter(cutoffFrequency: 0.1)
    
    func startIMUMeasurement(from reference: MeasurementPoint? = nil) {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        referencePoint = reference
        currentPosition = SIMD3<Double>(0, 0, 0)
        driftCorrection = SIMD3<Double>(0, 0, 0)
        accuracyEstimate = 0.1
        isCalibrated = reference != nil
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
        
        lastUpdateTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: motionManager.deviceMotionUpdateInterval, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }
    
    func stopIMUMeasurement() {
        timer?.invalidate()
        timer = nil
        motionManager.stopDeviceMotionUpdates()
    }
    
    func calibrate(to knownPoint: MeasurementPoint) {
        let expectedPosition = positionFromReference(to: knownPoint)
        driftCorrection = expectedPosition - currentPosition
        accuracyEstimate = 0.05
        isCalibrated = true
    }
    
    func setReferencePoint(_ point: MeasurementPoint) {
        referencePoint = point
        currentPosition = SIMD3<Double>(0, 0, 0)
        driftCorrection = SIMD3<Double>(0, 0, 0)
        isCalibrated = true
    }
    
    private func updatePosition() {
        guard let motion = motionManager.deviceMotion,
              let lastTime = lastUpdateTime else { return }
        
        let currentTime = Date()
        let deltaTime = currentTime.timeIntervalSince(lastTime)
        
        let filteredAcceleration = accelerationFilter.filter(SIMD3<Double>(
            x: motion.userAcceleration.x,
            y: motion.userAcceleration.y,
            z: motion.userAcceleration.z
        ))
        
        let filteredRotationRate = gyroFilter.filter(SIMD3<Double>(
            x: motion.rotationRate.x,
            y: motion.rotationRate.y,
            z: motion.rotationRate.z
        ))
        
        updatePositionWithIMU(
            acceleration: filteredAcceleration,
            rotationRate: filteredRotationRate,
            attitude: motion.attitude,
            deltaTime: deltaTime
        )
        
        accuracyEstimate += 0.01 * deltaTime
        
        lastUpdateTime = currentTime
    }
    
    private func updatePositionWithIMU(acceleration: SIMD3<Double>,
                                       rotationRate: SIMD3<Double>,
                                       attitude: CMAttitude,
                                       deltaTime: Double) {
        
        let rotationMatrix = attitude.rotationMatrix
        
        let worldAcceleration = SIMD3<Double>(
            x: acceleration.x * rotationMatrix.m11 + acceleration.y * rotationMatrix.m12 + acceleration.z * rotationMatrix.m13,
            y: acceleration.x * rotationMatrix.m21 + acceleration.y * rotationMatrix.m22 + acceleration.z * rotationMatrix.m23,
            z: acceleration.x * rotationMatrix.m31 + acceleration.y * rotationMatrix.m32 + acceleration.z * rotationMatrix.m33
        )
        
        let gravity = SIMD3<Double>(0, 0, -9.81)
        let netAcceleration = worldAcceleration - gravity
        
        velocity += netAcceleration * deltaTime
        
        currentPosition += velocity * deltaTime + 0.5 * netAcceleration * pow(deltaTime, 2)
        
        currentPosition += driftCorrection * deltaTime
        
        currentAttitude = SIMD3<Double>(
            x: attitude.roll,
            y: attitude.pitch,
            z: attitude.yaw
        )
    }
    
    func getCurrentMeasurement() -> MeasurementPoint? {
        guard let reference = referencePoint else { return nil }
        
        let correctedPosition = currentPosition
        
        return MeasurementPoint(
            coordinate: calculateCoordinate(from: correctedPosition, reference: reference),
            height: reference.height + correctedPosition.z,
            accuracy: accuracyEstimate,
            mode: .imu
        )
    }
    
    private func calculateCoordinate(from position: SIMD3<Double>, reference: MeasurementPoint) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6371000.0
        
        let deltaNorth = position.x
        let deltaEast = position.y
        
        let deltaLat = deltaNorth / earthRadius * (180 / .pi)
        let deltaLon = deltaEast / (earthRadius * cos(reference.coordinate.latitude * .pi / 180)) * (180 / .pi)
        
        return CLLocationCoordinate2D(
            latitude: reference.coordinate.latitude + deltaLat,
            longitude: reference.coordinate.longitude + deltaLon
        )
    }
    
    private func positionFromReference(to point: MeasurementPoint) -> SIMD3<Double> {
        guard let reference = referencePoint else { return SIMD3<Double>(0, 0, 0) }
        
        let earthRadius: Double = 6371000.0
        
        let deltaLat = point.coordinate.latitude - reference.coordinate.latitude
        let deltaLon = point.coordinate.longitude - reference.coordinate.longitude
        
        let deltaNorth = deltaLat * .pi / 180 * earthRadius
        let deltaEast = deltaLon * .pi / 180 * earthRadius * cos(reference.coordinate.latitude * .pi / 180)
        let deltaHeight = point.height - reference.height
        
        return SIMD3<Double>(deltaNorth, deltaEast, deltaHeight)
    }
}

class LowPassFilter {
    private let cutoffFrequency: Double
    private var previousValue: SIMD3<Double>?
    
    init(cutoffFrequency: Double) {
        self.cutoffFrequency = cutoffFrequency
    }
    
    func filter(_ newValue: SIMD3<Double>) -> SIMD3<Double> {
        guard let previous = previousValue else {
            previousValue = newValue
            return newValue
        }
        
        let dt = 1.0 / 60.0
        let RC = 1.0 / (2.0 * .pi * cutoffFrequency)
        let alpha = dt / (RC + dt)
        
        let filtered = previous + alpha * (newValue - previous)
        previousValue = filtered
        return filtered
    }
}
