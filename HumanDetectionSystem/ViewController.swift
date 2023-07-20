//
//  ViewController.swift
//  FaceDetectionSystem
//
//  Created by Cindy Amanda Onggirawan on 13/07/23.
//

import UIKit
import AVFoundation
import Vision
import Firebase
import CoreLocation
import WeatherKit

class ViewController: UIViewController, CLLocationManagerDelegate {
    // MARK: - Variables
    private var drawings: [CAShapeLayer] = []
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let captureSession = AVCaptureSession()
    
    // Using 'lazy' keyword because the 'captureSession' needs to be loaded before we can use the preview layer
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    
    private let label = UILabel()
    private var numberOfPassengers: Int = 0
    private var documentCount: Int = 0
    private var timer: Timer?
    private let dateFormatter = DateFormatter()
    private var date: String = "00-00-0000"
    private var time: String = "00:00:00"
    private var unixTimeInterval: TimeInterval = Date().timeIntervalSince1970
    
    // Get weather info
    private let locationManager = CLLocationManager()
    private let service = WeatherService()
    private var weatherResult: Weather?
    private var condition: String = "Fetching..."
    private var outdoorTemperature: String = "Fetching..."
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view
        getUserLocation()
        getFromFirebase()
        
        addCameraInput()
        showCameraFeed()
        
        getCameraFrames()
        captureSession.startRunning()
        
        // Start the timer to save data every 5 seconds
        startTimer()
    }
    
    // This account for when the container's 'view' changes
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        previewLayer.frame = view.frame
        
        // Show number
        addLabel()
    }
    
    // MARK: - Helper Functions
    
    private func addCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInWideAngleCamera], mediaType: .video, position: .back).devices.first else {
            fatalError("No camera detected. Please use a real camera not a simulator.")
        }
        
        // You should wrap this in a 'do-catch' block, but this will be good enough for the demo
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        captureSession.addInput(cameraInput)
    }
    
    private func showCameraFeed() {
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.frame
    }
    
    private func getCameraFrames() {
        videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value: kCVPixelFormatType_32BGRA)] as [String: Any]
        
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        // You do not want to process the frames on the Main Thread so we off load to another thread
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        
        captureSession.addOutput(videoDataOutput)
        
        guard let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported else {
            return
        }
        
        connection.videoOrientation = .portrait
    }
    
    private func detectPerson(image: CVPixelBuffer) {
        let personDetectionRequest = VNDetectHumanRectanglesRequest { vnRequest, error in
            DispatchQueue.main.async {
                if let results = vnRequest.results as? [VNHumanObservation], results.count > 0 {
                    self.numberOfPassengers = results.count
//                    print("✅ Detected \(self.number) person!")
                    self.handlePersonDetectionResults(observedPeople: results)
                } else {
                    self.numberOfPassengers = 0
//                    print("❌ No person was detected")
                    self.clearDrawings()
                }
            }
        }
        
        let imageResultHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .leftMirrored, options: [:])
        try? imageResultHandler.perform([personDetectionRequest])
    }
    
    private func handlePersonDetectionResults(observedPeople: [VNHumanObservation]) {
        clearDrawings()
        
        // Create the boxes
        let peopleBoundingBoxes: [CAShapeLayer] = observedPeople.map({ (observedPerson: VNHumanObservation) -> CAShapeLayer in
            
            let personBoundingBoxOnScreen = previewLayer.layerRectConverted(fromMetadataOutputRect: observedPerson.boundingBox)
            let personBoundingBoxPath = CGPath(rect: personBoundingBoxOnScreen, transform: nil)
            let personBoundingBoxShape = CAShapeLayer()
            
            // Set properties of the box shape
            personBoundingBoxShape.path = personBoundingBoxPath
            personBoundingBoxShape.fillColor = UIColor.clear.cgColor
            personBoundingBoxShape.strokeColor = UIColor.green.cgColor
            
            return personBoundingBoxShape
        })
        
        // Add boxes to the view layer and the array
        peopleBoundingBoxes.forEach { personBoundingBox in
            view.layer.addSublayer(personBoundingBox)
            drawings = peopleBoundingBoxes
        }
    }
      
    private func clearDrawings() {
        drawings.forEach({ drawing in drawing.removeFromSuperlayer() })
    }
    
    private func addLabel() {
        label.removeFromSuperview()
        
//        label.text = "Date: \(self.date) \nTime: \(self.time) \nCondition: \(self.condition) \nTemperature: \(self.outdoorTemperature) \nPeople: \(self.numberOfPassengers)"
        label.text = "Date: \(self.unixTimeInterval) \nCondition: \(self.condition) \nTemperature: \(self.outdoorTemperature) \nPeople: \(self.numberOfPassengers)"
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = UIColor.green
        label.backgroundColor = UIColor.white
        label.textAlignment = .center
        label.frame = CGRect(x: (view.bounds.width - 200) / 2,
                             y: 40,
                             width: 240,
                             height: 100)
        
        view.addSubview(label)
    }
    
    // MARK: - Firebase
    
    private func getFromFirebase() {
        let db = Firestore.firestore()
        db.collection("train-1").document("carriage-1").collection("history").getDocuments { querySnapshot, error in
            if let error = error {
                print("Error getting documents: \(error.localizedDescription)")
                return
            }
            
            if let count = querySnapshot?.documents.count {
                self.documentCount = count
            } else {
                return
            }
        }
    }
    
    private func saveToFirebase() {
        let db = Firestore.firestore()
        let data: [String: Any] = [
            "date": unixTimeInterval,
            "number_of_passengers": numberOfPassengers,
            "outdoor_temperature": outdoorTemperature,
            "weather_condition" : condition
        ]
        
        documentCount += 1
        
        let formattedNumber: String
        if documentCount > 0 && documentCount < 10 {
            formattedNumber = String(format: "00%d", documentCount)
        } else if documentCount >= 10 && documentCount < 100 {
            formattedNumber = String(format: "0%d", documentCount)
        } else {
            formattedNumber = String(format: "%d", documentCount)
        }

        let customID = "\(unixTimeInterval)"
        
        db.collection("train-1").document("carriage-1").collection("history").document(customID).setData(data) { error in
            if let error = error {
                print("Error saving number of passengers: \(error.localizedDescription)")
            } else {
                print("Data saved successfully!")
            }
        }
        
        db.collection("train-1").document("carriage-1").setData(data) { error in
            if let error = error {
                print("Error saving number of passengers: \(error.localizedDescription)")
            } else {
                print("Data saved successfully!")
            }
        }
    }
    
    // MARK: - Timer
    
    // Function to start the timer
    func startTimer() {
        // Invalidate the timer if it's already running
        timer?.invalidate()

        // Create a new timer
        timer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(timerHandler), userInfo: nil, repeats: true)
    }
    
    @objc func timerHandler() {
        self.unixTimeInterval = Date().timeIntervalSince1970
        
        self.label.text = "Date: \(self.unixTimeInterval) \nCondition: \(self.condition) \nTemperature: \(self.outdoorTemperature) \nPeople: \(self.numberOfPassengers)"
        
        saveToFirebase()
    }
    
    // MARK: - Weather
    
    func getUserLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
    }
    
    func getWeather(location: CLLocation) {
        Task {
            do {
                weatherResult = try await service.weather(for: location)
                
                DispatchQueue.main.async {
                    if let unwrapped = self.weatherResult?.currentWeather {
//                        self.dateFormatter.dateFormat = "dd-MM-yyyy"
//                        let dateString = self.dateFormatter.string(from: unwrapped.date)
//
//                        self.dateFormatter.dateFormat = "HH:mm:ss"
//                        let timeString = self.dateFormatter.string(from: unwrapped.date)
//
//                        self.date = dateString
//                        self.time = timeString
                        self.unixTimeInterval = Date().timeIntervalSince1970
                        self.condition = unwrapped.condition.description
                        self.outdoorTemperature = unwrapped.temperature.description
                    }
//                    self.label.text = "Date: \(self.date) \nTime: \(self.time) \nCondition: \(self.condition) \nTemperature: \(self.outdoorTemperature) \nPeople: \(self.numberOfPassengers)"
                    self.label.text = "Date: \(self.unixTimeInterval) \nCondition: \(self.condition) \nTemperature: \(self.outdoorTemperature) \nPeople: \(self.numberOfPassengers)"
                }
            } catch {
                print(String(describing: error))
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            return
        }
        locationManager.stopUpdatingLocation()
        getWeather(location: location)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("Unable to get image from the sample buffer")
            return
        }
        
        detectPerson(image: frame)
    }
}
