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
    
    @IBAction func recButtonTouched(sender: UIButton) {
        switch recState {
        case .readyToRecord :
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
            recButton.setTitle("RECORD", for: .normal)
            finishedRecording()
            }
    }
    
    
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        do {
            try recorder.reset()
        } catch { AKLog("Errored resetting.") }
        setupUIForPlaying()
        playButton.isHighlighted = true
        playButton.isEnabled = false
        infoLabel.text = "0.0 sec."
        infoLabel.layer.cornerRadius = 10
        
    }
    
    
    struct Constants {
        static let empty = ""
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
    
    func setupButtonNames() {
        recButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        playButton.setTitle(Constants.empty, for: UIControl.State.disabled)
    }
    
    func disablePlayButtons () {
        playButton.isHighlighted = true
        playButton.isEnabled = false
    }
    
    func finishedRecording() {
        
        let recordedDuration = player.audioFile?.duration
        infoLabel.text = "\(String(format: "%0.001f", recordedDuration!)) sec."
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
        let recordedDuration = player.audioFile?.duration
        infoLabel.text = "\(String(format: "%0.001f", recordedDuration!)) sec."
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
