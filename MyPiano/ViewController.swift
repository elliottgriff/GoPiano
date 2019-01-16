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

class ViewController: UIViewController, AKKeyboardDelegate {
    
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
    @IBOutlet private weak var octaveCount: UIButton!
    
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
            try AKSettings.setSession(category: .playAndRecord)
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
        
        view.backgroundColor = UIColor(patternImage: UIImage(named: "wood_background.png")!)
        
        if keyboardView.octaveCount == 2 && keyboardView.firstOctave == 6 {
            keyboardView.firstOctave += -1
        }
        
        loadSound()
        setupKeyboardUI()
        setupButtonsUI()
        disablePlayButtons()
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

    @IBAction func octaveCountPressed(_ sender: UIButton) {
        
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
                playButton.setTitle("STOP", for: .normal)
                playState = .playing

            
            case .playing :
                player.stop()
                playButton.setTitle("PLAY", for: .normal)
                playState = .readyToPlay
        }
    }
    
    @IBAction @objc func recButtonTouched(sender: UIButton) {
        switch recState {
        case .readyToRecord :
            

            time = 0
            timer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(ViewController.action), userInfo: nil, repeats: true)
            
            recButton.setTitle("STOP", for: .normal)
            recState = .recording
            do {
                try recorder.reset()
                try recorder.record()
            } catch {
                AKLog("Error recording")
            }
            

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
            playButton.setTitle("PLAY", for: .normal)
            recButton.setTitle("RECORD", for: .normal)
            finishedRecording()
            }
    }
    
    
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        do {
            if recorder.isRecording {
                try recorder.reset()
                try recorder.record()
            } else {
                try recorder.reset()
            }
        } catch {
            print("error reseting while recording")
        }

        setupUIForPlaying()
        playButton.isHighlighted = true
        playButton.isEnabled = false
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
        playButton.isEnabled = true
        playButton.isHighlighted = false
        if player.isPlaying {
            print("already playing")
        } else {
            playState = .readyToPlay
        }
    }
    
    func setupUIForPlaying () {
        playButton.setTitle("PLAY", for: .normal)
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
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        playButton.leadingAnchor.constraint(lessThanOrEqualToSystemSpacingAfter: recButton.trailingAnchor, multiplier: 5).isActive = true
        playButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.1).isActive = true
        playButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        playButton.layer.cornerRadius = 10
        
        recButton.translatesAutoresizingMaskIntoConstraints = false
        recButton.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        recButton.leadingAnchor.constraint(equalToSystemSpacingAfter: view.leadingAnchor, multiplier: 70).isActive = true
        recButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.15).isActive = true
        recButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        recButton.layer.cornerRadius = 10
        
        octaveCount.translatesAutoresizingMaskIntoConstraints = false
        octaveCount.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        octaveCount.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.leadingAnchor, multiplier: 5).isActive = true
        octaveCount.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.1).isActive = true
        octaveCount.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        octaveCount.layer.cornerRadius = 10
        
        octaveUp.translatesAutoresizingMaskIntoConstraints = false
        octaveUp.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        octaveUp.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.leadingAnchor, multiplier: 27.5).isActive = true
        octaveUp.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.075).isActive = true
        octaveUp.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        octaveUp.layer.cornerRadius = 10
        
        octaveDown.translatesAutoresizingMaskIntoConstraints = false
        octaveDown.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        octaveDown.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.leadingAnchor, multiplier: 17.5).isActive = true
        octaveDown.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.075).isActive = true
        octaveDown.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        octaveDown.layer.cornerRadius = 10
        
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        resetButton.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.leadingAnchor, multiplier: 57.5).isActive = true
        resetButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.075).isActive = true
        resetButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        resetButton.layer.cornerRadius = 10
        
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1).isActive = true
        infoLabel.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: view.leadingAnchor, multiplier: 37.5).isActive = true
        infoLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.175).isActive = true
        infoLabel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.15).isActive = true
        infoLabel.layer.cornerRadius = 10
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
