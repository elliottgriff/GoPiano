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

class ViewController: UIViewController, AKKeyboardDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            print("bluetooth enabled")
            
        }
    }
    
    
    var midiSample = AKMIDISampler()
    var recorder: AKNodeRecorder!
    var player = AKPlayer()
    var tape = try? AKAudioFile()
    var mix = AKMixer()
    var playingMix = AKMixer()
//    var outputFile: AVAudioFile!
    var keyboardView = Keyboard(width: 1, height: 0, firstOctave: 3, octaveCount: 1)
    var recordings: Recordings!
    var recState = RecordState.readyToRecord
    var playState = PlayState.readyToPlay
    var numberOfRecordings: Int = 0
    var timer = Timer()
    var time = 0
    
    
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var recButton: UIButton!
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet private weak var octaveUp: UIButton!
    @IBOutlet private weak var octaveDown: UIButton!
    @IBOutlet private weak var octaveCountOutlet: UIButton!
    @IBOutlet private weak var switchOctaveOutlet: UISwitch!
    
    
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
            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetoothA2DP)
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
        
        if keyboardView.octaveCount == 2 && keyboardView.firstOctave == 6 {
            keyboardView.firstOctave += -1
        }
        
        
        loadSound()
        setupKeyboardUI()
        setupButtonsUI()

        
        
        if let number:Int = UserDefaults.standard.object(forKey: "myNumber") as? Int {
            numberOfRecordings = number
        }
    }
    
    
    func playingEnded() {
        DispatchQueue.main.async {
            self.setupUIForPlaying()
        }
    }
    
    //MARK:  Buttons
    
    @IBAction func octaveSwitchPressed(_ sender: UISwitch) {
        if keyboardView.octaveCount == 1 {
            keyboardView.octaveCount += 1
        } else if keyboardView.octaveCount == 2 {
            keyboardView.octaveCount += -1
        }
        viewDidLoad()
    }
    

    @IBAction func octaveCountPressed(_ sender: UIButton) {
        
        if keyboardView.octaveCount == 1 {
            keyboardView.octaveCount += 1
            octaveCountOutlet.setBackgroundImage(#imageLiteral(resourceName: "2button"), for: .normal)
        } else if keyboardView.octaveCount == 2 {
            keyboardView.octaveCount += -1
            octaveCountOutlet.setBackgroundImage(#imageLiteral(resourceName: "1button"), for: .normal)
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
//                playButton.setTitle("STOP", for: .normal)
                playButton.setBackgroundImage(#imageLiteral(resourceName: "pausePurple"), for: .normal)
                playState = .playing

            
            case .playing :
                player.stop()
//                playButton.setTitle("PLAY", for: .normal)
                playButton.setBackgroundImage(#imageLiteral(resourceName: "playPurple"), for: .normal)
                playState = .readyToPlay
        }
    }
    
    @IBAction @objc func recButtonTouched(sender: UIButton) {
        switch recState {
        case .readyToRecord :
            

            time = 0
            timer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(ViewController.action), userInfo: nil, repeats: true)
            
//            recButton.setTitle("STOP", for: .normal)
            recState = .recording
            do {
                try recorder.reset()
                try recorder.record()
            } catch {
                AKLog("Error recording")
            }
            recButton.setBackgroundImage(#imageLiteral(resourceName: "stopPurple"), for: .normal)
//            recButton.layer.borderColor = #colorLiteral(red: 0.5807225108, green: 0.066734083, blue: 0, alpha: 1)
            

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
            
            
            
//            numberOfRecordings += 1
            
//            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("recorded.caf")
//            let format = AVAudioFormat(commonFormat: .pcmFormatFloat64, sampleRate: 44100, channels: 2, interleaved: false)!
            
//            let fileName = getDirectory().appendingPathComponent("\(numberOfRecordings).caf")
//            let settings = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 12000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
//            outputFile = try! AVAudioFile(forWriting: fileName, settings: settings)
//
//            let fileTape = try! AKAudioFile(forWriting: fileName, settings: settings)
//            try! AudioKit.renderToFile(fileTape, duration: Double((player.audioFile!.duration)))
//            try! AudioKit.renderToFile(fileTape, duration: Double((player.audioFile!.duration)))
//
//
//            try! AudioKit.start()
//            playButton.setTitle("PLAY", for: .normal)
            playButton.setBackgroundImage(#imageLiteral(resourceName: "playPurple"), for: .normal)
            recButton.setBackgroundImage(#imageLiteral(resourceName: "recordPurple"), for: .normal)
//            playButton.layer.borderColor = #colorLiteral(red: 0.2745098174, green: 0.4862745106, blue: 0.1411764771, alpha: 1)
//            recButton.layer.borderColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
            
            
//            recButton.setTitle("RECORD", for: .normal)
//            recButton.layer.borderColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
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
//        do {
//            if recorder.isRecording {
//                try recorder.reset()
//                try recorder.record()
//            } else {
//                try recorder.reset()
//                recButton.layer.borderColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
//            }
//        } catch {
//            print("error reseting while recording")
//        }
        player.load(audioFile: recorder.audioFile!)

        setupUIForPlaying()
        playButton.isUserInteractionEnabled = false
//        playButton.layer.borderColor = #colorLiteral(red: 0.5807225108, green: 0.066734083, blue: 0, alpha: 1)
        recButton.setBackgroundImage(#imageLiteral(resourceName: "recordPurple"), for: .normal)
        playButton.setBackgroundImage(#imageLiteral(resourceName: "playPurple"), for: .normal)
        time = 0
        infoLabel.text = "00:00:00"
        
    }
    
    
    struct Constants {
        static let empty = ""
    }
    
    @objc func action() {
        let miliseconds = Int(time) % 100
        let seconds = Int(time) / 100 % 60
        let minutes = Int(time) / 6000 % 60
        
        time += 1
        infoLabel.text = String(format:"%02i:%02i:%02i", minutes, seconds, miliseconds)
    }
    
    
    func loadSound() {
        try! midiSample.loadMelodicSoundFont("gpiano", preset: 0)
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
    
    
    func disablePlayButtons () {
        if player.audioFile?.duration == 0 {
            playButton.isHighlighted = true
            playButton.isEnabled = false
        } else {
            print("won't disable Play button, there is a File to play")
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
    
    //Get Directory Path
    func getDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = paths[0]
        return documentDirectory
    }

//    //Display Alerts
    func displayAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "dismiss", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
//    func saveFile() {
//        let shit = Recordings()
//
//
//        AudioKit.output = mix
//        do {
//            try AudioKit.start()
//        } catch {
//            print("error starting in saveFile")
//        }
//        shit.numberOfRecordings += 1
//        let fileName = getDirectory().appendingPathComponent("\(shit.numberOfRecordings).caf")
//        let settings = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 12000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
//
//        //            start recording
//
//        outputFile = try! AVAudioFile(forWriting: fileName, settings: settings)
//        do {
//            try AudioKit.renderToFile(outputFile, duration: self.player.duration)
//            try AudioKit.renderToFile(outputFile, duration: self.player.duration)
//        } catch {
//            print("nothing to render")
//        }
//
//        UserDefaults.standard.set(shit.numberOfRecordings, forKey: "myNumber")
//    }
    
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
        
        switchOctaveOutlet.translatesAutoresizingMaskIntoConstraints = false
        switchOctaveOutlet.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        switchOctaveOutlet.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: buttonContainerView.leadingAnchor, multiplier: 5).isActive = true
//        switchOctaveOutlet.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.1).isActive = true
//        switchOctaveOutlet.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.5).isActive = true
        switchOctaveOutlet.layer.cornerRadius = 15
        switchOctaveOutlet.layer.borderWidth = 1
        switchOctaveOutlet.layer.borderColor = #colorLiteral(red: 0.3647058904, green: 0.06666667014, blue: 0.9686274529, alpha: 1)
        
        octaveDown.translatesAutoresizingMaskIntoConstraints = false
        octaveDown.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        octaveDown.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: switchOctaveOutlet.trailingAnchor, multiplier: 4).isActive = true
        octaveDown.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.065).isActive = true
        octaveDown.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.65).isActive = true
        octaveDown.layer.cornerRadius = 15
        octaveDown.layer.borderWidth = 2
        octaveDown.layer.borderColor = #colorLiteral(red: 0.803833425, green: 0.8039723635, blue: 0.8038246036, alpha: 1)
        
        
        octaveUp.translatesAutoresizingMaskIntoConstraints = false
        octaveUp.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        octaveUp.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: octaveDown.trailingAnchor, multiplier: 2.5).isActive = true
        octaveUp.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.065).isActive = true
        octaveUp.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.65).isActive = true
        octaveUp.layer.cornerRadius = 15
        octaveUp.layer.borderWidth = 2
        octaveUp.layer.borderColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
        
        
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        infoLabel.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: octaveUp.trailingAnchor, multiplier: 2.5).isActive = true
        infoLabel.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.175).isActive = true
        infoLabel.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        infoLabel.layer.masksToBounds = true
        infoLabel.layer.cornerRadius = 10
        infoLabel.layer.borderWidth = 4
        infoLabel.layer.borderColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
        
        
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        resetButton.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: infoLabel.trailingAnchor, multiplier: 2.5).isActive = true
        resetButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        resetButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        resetButton.layer.masksToBounds = true
        resetButton.layer.cornerRadius = 15
        resetButton.layer.borderWidth = 2
        resetButton.layer.borderColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
        
        
        recButton.translatesAutoresizingMaskIntoConstraints = false
        recButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        recButton.leadingAnchor.constraint(equalToSystemSpacingAfter: resetButton.trailingAnchor, multiplier: 2.5).isActive = true
        recButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        recButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
//        recButton.layer.masksToBounds = true
        recButton.layer.cornerRadius = 15
        recButton.layer.borderWidth = 2
        recButton.layer.borderColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
//        if recorder.isRecording {
//            recButton.layer.borderColor = #colorLiteral(red: 0.5807225108, green: 0.066734083, blue: 0, alpha: 1)
//        } else {
//            recButton.layer.borderColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
//        }
        
        
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.centerYAnchor.constraint(equalTo: buttonContainerView.centerYAnchor).isActive = true
        playButton.leadingAnchor.constraint(lessThanOrEqualToSystemSpacingAfter: recButton.trailingAnchor, multiplier: 2.5).isActive = true
        playButton.widthAnchor.constraint(equalTo: buttonContainerView.widthAnchor, multiplier: 0.075).isActive = true
        playButton.heightAnchor.constraint(equalTo: buttonContainerView.heightAnchor, multiplier: 0.75).isActive = true
        playButton.layer.cornerRadius = 15
//        playButton.layer.borderWidth = 4
        playButton.layer.borderWidth = 2
        playButton.layer.borderColor = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
        if player.audioFile?.duration == 0 && recorder.isRecording {
            playButton.isUserInteractionEnabled = false
        } else if player.audioFile?.duration == 0 {
            playButton.isUserInteractionEnabled = false
//            playButton.layer.borderColor = #colorLiteral(red: 0.5807225108, green: 0.066734083, blue: 0, alpha: 1)
//            playButton.backgroundColor = #colorLiteral(red: 0.5807225108, green: 0.066734083, blue: 0, alpha: 1)
        } else {
            playButton.isUserInteractionEnabled = true
//            playButton.layer.borderColor = #colorLiteral(red: 0.2745098174, green: 0.4862745106, blue: 0.1411764771, alpha: 1)
//            playButton.backgroundColor = #colorLiteral(red: 0.2745098174, green: 0.4862745106, blue: 0.1411764771, alpha: 1)
        }
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
