//
//  ViewController.swift
//  MyPiano
//
//  Created by elliott on 9/21/18.
//  Copyright © 2018 Elliott Griffin. All rights reserved.
//

import UIKit
import AudioKit
import AudioKitUI
import CoreBluetooth
import ReplayKit

class ViewController: UIViewController, AKKeyboardDelegate, CBCentralManagerDelegate, CBPeripheralDelegate, RPPreviewViewControllerDelegate {
    
    var centralManager : CBCentralManager?
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
            print("bluetooth enabled")
        } else {
            print("blueooth is powered off")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        centralManager?.stopScan()
        centralManager?.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    
    
    
    var midiSample = AKMIDISampler()
    var recorder: AKNodeRecorder!
    var player = AKPlayer()
    var tape = try? AKAudioFile()
    var mix = AKMixer()
    var playingMix = AKMixer()
    var keyboardView = Keyboard(width: 1, height: 0, firstOctave: 3, octaveCount: 1)
    var recState = RecordState.readyToRecord
    var playState = PlayState.readyToPlay
    var numberOfRecordings: Int = 0
    var timer = Timer()
    var time = 0
    let screenRecorder = RPScreenRecorder.shared()
        private var isRecording = false
    
    
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var recButton: UIButton!
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet private weak var octaveUp: UIButton!
    @IBOutlet private weak var octaveDown: UIButton!
    @IBOutlet private weak var switchOctaveOutlet: UISwitch!
    @IBOutlet private weak var saveButton: UIButton!
    
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    enum RecordState {
        case readyToRecord
        case recording
    }
    
    enum PlayState {
        case readyToPlay
        case playing
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        do {
            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetooth)
        } catch {
            print("error session")
        }
        
        AKSettings.defaultToSpeaker = true
        AKSettings.audioInputEnabled = true
        
        let reverb = AKReverb(midiSample)
        reverb.loadFactoryPreset(.mediumRoom)
        mix = AKMixer(reverb)
        
        AudioKit.output = mix
        
        AKSettings.bufferLength = .medium
        
        do {
            recorder = try AKNodeRecorder(node: mix)
        } catch {
            print("error setting up recorder")
        }
        
        
        if let file = recorder.audioFile {
            AKSettings.defaultToSpeaker = true
            player = AKPlayer(audioFile: file)
            playingMix = AKMixer(player, mix)
            AudioKit.output = playingMix
            recorder = try? AKNodeRecorder(node: playingMix)
            
        }
        
        player.isLooping = true
        player.completionHandler = playingEnded
        
        
        do {
            try AudioKit.start()
        } catch {
            print("error starting")
        }
    }
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadSound()
        setupKeyboardUI()
        setupButtonsUI()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        if keyboardView.octaveCount == 2 && keyboardView.firstOctave == 6 {
            keyboardView.firstOctave += -1
        }
        
    }
    
    
    func playingEnded() {
        DispatchQueue.main.async {
            self.setupUIForPlaying()
        }
    }
    
    //MARK:  Buttons
    
    @IBAction func saveButtonPressed(_ sender: UIButton) {
        
        if !isRecording {
            startScreenRecording()
        } else {
            stopScreenRecording()
        }
        
    }
    
    
    @IBAction func octaveSwitchPressed(_ sender: UISwitch) {
        if keyboardView.octaveCount == 1 {
            keyboardView.octaveCount += 1
        } else if keyboardView.octaveCount == 2 {
            keyboardView.octaveCount += -1
        }
        viewDidLoad()
    }
    

    @IBAction func upOctavePress(_ sender: UIButton) {
        if keyboardView.octaveCount == 2 && keyboardView.firstOctave == 5 {
            print("It's over 9,000!")
        } else if keyboardView.firstOctave == 6 {
            print("It's over 9,000!")
            
        } else {
            keyboardView.firstOctave += 1
        }
    }

    @IBAction func downOctavePressed(_ sender: UIButton) {
         if keyboardView.firstOctave == 0 {
            print("the Tao is like water...")
        } else {
            keyboardView.firstOctave += -1
        }
    }
    
    @IBAction func playButtonTouched(_ sender: UIButton) {
        switch playState {
            case .readyToPlay :
                player.play()
                playButton.setBackgroundImage(#imageLiteral(resourceName: "pauseRed"), for: .normal)
                playState = .playing

            
            case .playing :
                player.stop()
                playButton.setBackgroundImage(#imageLiteral(resourceName: "playRed"), for: .normal)
                playState = .readyToPlay
        }
    }
    
    @IBAction @objc func recButtonTouched(sender: UIButton) {
        switch recState {
        case .readyToRecord :
            

            time = 0
            timer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(ViewController.action), userInfo: nil, repeats: true)
            
            recState = .recording
            do {
                try recorder.reset()
                try recorder.record()
            } catch {
                AKLog("Error recording")
            }
            recButton.setBackgroundImage(#imageLiteral(resourceName: "stopRed"), for: .normal)
            

        case .recording :
            
            if let tape = recorder.audioFile {
                player.load(audioFile: tape)
            }
            
            if let _ = player.audioFile?.duration {
                recorder.stop()
                timer.invalidate()
            }
            
            
                tape?.exportAsynchronously(name: "temp.caf",
                                          baseDir: .temp,
                                          exportFormat: .caf) {_, exportError in
                                            if let error = exportError {
                                                AKLog("Export Failed \(error)")
                                            } else {
                                                AKLog("Export succeeded")
                                            }
                    }
            
            
            playButton.setBackgroundImage(#imageLiteral(resourceName: "playRed"), for: .normal)
            recButton.setBackgroundImage(#imageLiteral(resourceName: "recordRed"), for: .normal)
            finishedRecording()
            }
    }
    
    
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        playButton.isUserInteractionEnabled = false
        do {
            try recorder.reset()
            recorder.stop()
            timer.invalidate()
        } catch {
            print("error resetting")
        }
        finishedRecording()
        player.load(audioFile: recorder.audioFile!)

        setupUIForPlaying()
        playButton.isUserInteractionEnabled = false
        recButton.setBackgroundImage(#imageLiteral(resourceName: "recordRed"), for: .normal)
        playButton.setBackgroundImage(#imageLiteral(resourceName: "playRed"), for: .normal)
        time = 0
        infoLabel.text = "00:00:00"
        
    }
    
    
    struct Constants {
        static let empty = ""
    }
    
    func startScreenRecording() {
        
        guard screenRecorder.isAvailable else {
            print("screen recording not available")
            return
        }
        
        screenRecorder.startRecording { [unowned self] (error) in
            
            guard error == nil else {
                print("error starting screen recording")
                return
            }
            
            print("started screen recording successfully")
            self.isRecording = true
            DispatchQueue.main.async {
            self.saveButton.setBackgroundImage(#imageLiteral(resourceName: "saveBlack"), for: .normal)
            }
        }
        
        
    }
    
    func stopScreenRecording() {
        
        saveButton.setBackgroundImage(#imageLiteral(resourceName: "saveRed"), for: .normal)
        
        screenRecorder.stopRecording { [unowned self] (preview, error) in
            print("stopped screen recording")
            
            guard preview != nil else {
                print("preview controller not available")
                return
            }

            let alert = UIAlertController(title: "Saving Finished", message: nil, preferredStyle: .alert)

            let deleteAction = UIAlertAction(title: "Delete", style: .destructive, handler: { (UIAlertAction) in
                self.screenRecorder.discardRecording(handler: {() -> Void in
                    print("Screen Recording successfully deleted")
                })
            })
            
            let editAction = UIAlertAction(title: "Save", style: .default, handler: { (action: UIAlertAction) -> Void in
                preview?.previewControllerDelegate = self
                self.present(preview!, animated: true, completion: nil)
            })

            alert.addAction(editAction)
            alert.addAction(deleteAction)
            self.present(alert, animated: true, completion: nil)
            
            self.isRecording = false
            
        }
    
    }
    
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
    }
    
    
    @objc func action() {
        let miliseconds = Int(time) % 100
        let seconds = Int(time) / 100 % 60
        let minutes = Int(time) / 6000 % 60
        
        time += 1
        infoLabel.text = String(format:"%02i:%02i:%02i", minutes, seconds, miliseconds)
    }
    
    
    func loadSound() {
        do {
            try midiSample.loadMelodicSoundFont("gpiano", preset: 0)
        } catch {
            print("couldnt load soundFont")
        }
    }
    
    public func noteOn(note: MIDINoteNumber) {
        do {
            try midiSample.play(noteNumber: note, velocity: 100, channel: 0)
        } catch {
            print("error sampling")
        }
    }
    
    public func noteOff(note: MIDINoteNumber) {
        do {
            try midiSample.stop(noteNumber: note, channel: 0)
        } catch {
            print("error stopping sample")
        }
    }
    
    func finishedRecording() {
        recState = .readyToRecord
        playButton.isUserInteractionEnabled = true
        if player.isPlaying {
            print("already playing")
        } else {
            playState = .readyToPlay
        }
    }
    
    func setupUIForPlaying () {
        playState = .readyToPlay
    }
    
    
    
    public func setupButtonsUI() {
        let buttonContainerView = UIView()
        buttonContainerView.translatesAutoresizingMaskIntoConstraints = false
        buttonContainerView.backgroundColor = UIColor(patternImage: UIImage(named: "lightWood.png")!)
        view.addSubview(buttonContainerView)
        buttonContainerView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        buttonContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        buttonContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        buttonContainerView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.20).isActive = true
        buttonContainerView.addSubview(switchOctaveOutlet)
        buttonContainerView.addSubview(octaveDown)
        buttonContainerView.addSubview(octaveUp)
        buttonContainerView.addSubview(infoLabel)
        buttonContainerView.addSubview(resetButton)
        buttonContainerView.addSubview(recButton)
        buttonContainerView.addSubview(playButton)
        buttonContainerView.addSubview(saveButton)
        
        switchOctaveOutlet.translatesAutoresizingMaskIntoConstraints = false
        switchOctaveOutlet.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        switchOctaveOutlet.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: buttonContainerView.leadingAnchor, multiplier: 4).isActive = true
        switchOctaveOutlet.layer.cornerRadius = 15
        switchOctaveOutlet.layer.borderWidth = 1
        switchOctaveOutlet.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        octaveDown.translatesAutoresizingMaskIntoConstraints = false
        octaveDown.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        octaveDown.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: switchOctaveOutlet.trailingAnchor, multiplier: 2.5).isActive = true
        octaveDown.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.065).isActive = true
        octaveDown.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.65).isActive = true
        octaveDown.layer.cornerRadius = 15
        octaveDown.layer.borderWidth = 2
        octaveDown.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        
        octaveUp.translatesAutoresizingMaskIntoConstraints = false
        octaveUp.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        octaveUp.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: octaveDown.trailingAnchor, multiplier: 2.5).isActive = true
        octaveUp.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.065).isActive = true
        octaveUp.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.65).isActive = true
        octaveUp.layer.cornerRadius = 15
        octaveUp.layer.borderWidth = 2
        octaveUp.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        infoLabel.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: octaveUp.trailingAnchor, multiplier: 2.5).isActive = true
        infoLabel.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.175).isActive = true
        infoLabel.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        infoLabel.layer.masksToBounds = true
        infoLabel.layer.cornerRadius = 10
        infoLabel.layer.borderWidth = 4
        infoLabel.layer.borderColor = #colorLiteral(red: 0.921431005, green: 0.9214526415, blue: 0.9214410186, alpha: 1)
        infoLabel.adjustsFontSizeToFitWidth = true
        
        
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        resetButton.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: infoLabel.trailingAnchor, multiplier: 2.5).isActive = true
        resetButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        resetButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        resetButton.layer.masksToBounds = true
        resetButton.layer.cornerRadius = 15
        resetButton.layer.borderWidth = 2
        resetButton.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        
        recButton.translatesAutoresizingMaskIntoConstraints = false
        recButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        recButton.leadingAnchor.constraint(equalToSystemSpacingAfter: resetButton.trailingAnchor, multiplier: 2.5).isActive = true
        recButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        recButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        recButton.layer.cornerRadius = 15
        recButton.layer.borderWidth = 2
        recButton.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        playButton.leadingAnchor.constraint(lessThanOrEqualToSystemSpacingAfter: recButton.trailingAnchor, multiplier: 2.5).isActive = true
        playButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        playButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        playButton.layer.cornerRadius = 15
        playButton.layer.borderWidth = 2
        playButton.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        if player.audioFile?.duration == 0 && recorder.isRecording {
            playButton.isUserInteractionEnabled = false
        } else if player.audioFile?.duration == 0 {
            playButton.isUserInteractionEnabled = false
        } else {
            playButton.isUserInteractionEnabled = true

        }
        
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        saveButton.leadingAnchor.constraint(lessThanOrEqualToSystemSpacingAfter: playButton.trailingAnchor, multiplier: 2.5).isActive = true
        saveButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        saveButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        saveButton.layer.cornerRadius = 15
        saveButton.layer.borderWidth = 2
        saveButton.layer.borderColor = #colorLiteral(red: 0.6666666865, green: 0.6666666865, blue: 0.6666666865, alpha: 1)
        
        
    }
    
    public func setupKeyboardUI() {
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(keyboardView)
        let keyboardYconstraint = NSLayoutConstraint(item: keyboardView, attribute: .centerY, relatedBy: .equal, toItem: self.view, attribute: .centerY, multiplier: 1.20, constant: 0)
        let keyboardHeightConstraint = NSLayoutConstraint(item: keyboardView, attribute: .height, relatedBy: .equal, toItem: self.view, attribute: .height, multiplier: 0.80, constant: 0)
        let keyboardWidthConstraint = NSLayoutConstraint(item: keyboardView, attribute: .width, relatedBy: .equal, toItem: self.view, attribute: .width, multiplier: 1.01, constant: 0)
        
        
        keyboardView.delegate = self
        keyboardView.polyphonicMode = true
        NSLayoutConstraint.activate([keyboardYconstraint, keyboardHeightConstraint, keyboardWidthConstraint])
    }
}
