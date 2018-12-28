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

class ViewController: UIViewController, AKKeyboardDelegate, AVAudioRecorderDelegate{
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func noteOn(note: MIDINoteNumber) {
        do {
            try midiSample.play(noteNumber: note, velocity: 100, channel: 0)
        } catch {
            print("cannot play note")
        }
    }
    
    func noteOff(note: MIDINoteNumber) {
        do {
            try midiSample.stop(noteNumber: note, channel: 0)
        } catch {
            print("cannot stop note")
        }
    }
    
    var recordingSession: AVAudioSession!
    var audioRecorder: AVAudioRecorder!
    
    
    
    var midiSample = AKMIDISampler()
    var recorder: AKNodeRecorder!
    var player: AKPlayer!
    var tape = try! AKAudioFile()
    var mix = AKMixer()
    var playingMix = AKMixer()
    var numberOfRecordings:Int = 0
    var outputFile: AVAudioFile?
    var keyboardView: Keyboard?
    var recordings: Recordings?
    var timer = Timer()
    var counter = 0
    var keyboardy = Keyboard(width: 1,
                            height: 0,
                            firstOctave: 2,
                            octaveCount: 1)
    
    
    var recState = RecordState.readyToRecord
    var playState = PlayState.readyToPlay
    
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var recButton: UIButton!
    @IBOutlet private weak var playButton: UIButton!
    @IBOutlet weak var octaveUp: UIButton!
    @IBOutlet weak var octaveDown: UIButton!
    
    
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
            try midiSample.loadMelodicSoundFont("gpiano", preset: 0)
        } catch {
            print("error playing")
        }
        
        AKAudioFile.cleanTempDirectory()
        
        AKSettings.bufferLength = .medium
        
//        do {
//            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetoothA2DP)
//        } catch {
//            AKLog("Could not set session category.")
//        }
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
        
        
        recorder = try? AKNodeRecorder(node: mix)
        
        if let file = recorder.audioFile {
            AKSettings.defaultToSpeaker = true
            player = AKPlayer(audioFile: file)
            playingMix = AKMixer(player, mix)
            AudioKit.output = playingMix
            recorder = try? AKNodeRecorder(node: playingMix)
        }
        
        player.isLooping = true
        player.completionHandler = playingEnded
        
        AudioKit.output = mix

        do {
            try AudioKit.start()
        } catch {
            print("error starting")
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        playButton.isEnabled = false
        setupUIForRecording()
        setupKeyboardUI()
        AudioKit.engine.reset()
    }
    
    
    func playingEnded() {
        DispatchQueue.main.async {
            self.setupUIForPlaying ()
        }
    }
    
    //MARK:  Buttons
    
    @IBAction func upOctavePress(_ sender: UIButton) {
        if keyboardy.firstOctave == 6 {
            print("it's over 9,000!")
        } else {
            keyboardy.firstOctave += 1
        }
        
    }
    
    @IBAction func downOctavePressed(_ sender: UIButton) {
        if keyboardy.firstOctave == 0 {
            print("the Tao is like water...")
        } else {
            keyboardy.firstOctave += -1
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
//            updateCounter()

            recState = .recording
            do {
                try recorder.record()
            } catch {
                AKLog("Error recording")
            }
            
//            outputFile = try! AVAudioFile(forWriting: self.exportURL, settings: self.recorder.audioFile!.fileFormat.settings)
//            try! AudioKit.renderToFile(outputFile!, duration: (self.recorder.audioFile?.duration)!, prerender: {
//                self.player.play()
//            })
//
//            outputFile = try! AVAudioFile(forWriting: self.exportURL, settings: self.recorder.audioFile!.fileFormat.settings)
//            try! AudioKit.renderToFile(outputFile!, duration: (self.recorder.audioFile?.duration)!, prerender: {
//                self.player.play()
//            })

            
        case .recording :
            if let tape = recorder.audioFile {
                player.load(audioFile: tape)
            }
            
            if let _ = player.audioFile?.duration {
                recorder.stop()

                
                //            start recording
                

                
                tape.exportAsynchronously(name: "temp.caf",
                                          baseDir: .temp,
                                          exportFormat: .caf) {_, exportError in
                                            if let error = exportError {
                                                AKLog("Export Failed \(error)")
                                            } else {
                                                AKLog("Export succeeded")
                                            }
                }

                
                let recordedDuration = player != nil ? player.audioFile?.duration  : 0
                infoLabel.text = "\(String(format: "%0.01f", recordedDuration!)) sec."
                recState = .readyToRecord
                recButton.setTitle("RECORD", for: .normal)
                playButton.isEnabled = true
                if player.isPlaying {
                    print("already playing")
                } else {
                    playState = .readyToPlay
                }
            }
        }
    }
    
    
    struct Constants {
        static let empty = ""
    }
    
//    @objc func updateCounter() {
//        counter += 1
//
//        infoLabel.text = "\(String(format: "%0.01f", timer)) sec."
//    }
    
    
    func setupButtonNames() {
        recButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        playButton.setTitle(Constants.empty, for: UIControl.State.disabled)
    }
    
    func setupUIForRecording () {
        recState = .readyToRecord
        infoLabel.text = "0.00 sec."
        recButton.setTitle("RECORD", for: .normal)
    }
    
    func setupUIForPlaying () {
        let recordedDuration = player != nil ? player.audioFile?.duration  : 0
        infoLabel.text = "\(String(format: "%0.01f", recordedDuration!)) sec."
        playButton.setTitle("PLAY", for: .normal)
        playState = .readyToPlay
    }
    
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        clearTmpDir()
        do {
            try recorder.reset()
        } catch { AKLog("Errored resetting.") }
        AudioKit.engine.reset()
        setupUIForPlaying()
        
        
//        AKAudioFile.cleanTempDirectory()
        

        setupUIForRecording()
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
    
    func saveFile() {
        
//        try! AudioKit.start()
        numberOfRecordings += 1
        let fileName = getDirectory().appendingPathComponent("\(numberOfRecordings).wav")
        let settings = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 12000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        
        //            start recording
        
        outputFile = try! AVAudioFile(forWriting: fileName, settings: settings)
        try! AudioKit.renderToFile(outputFile!, duration: self.player.duration, prerender: {
            self.player.play()
        })
        
        outputFile = try! AVAudioFile(forWriting: fileName, settings: settings)
        try! AudioKit.renderToFile(outputFile!, duration: self.player.duration, prerender: {
            self.player.play()
        })
        
        UserDefaults.standard.set(numberOfRecordings, forKey: "myNumber")
        recordings?.myTableView.reloadData()
        
    }
    
    public func setupKeyboardUI() {
        let keyboard = keyboardy
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(keyboard)
        let keyboardYconstraint = NSLayoutConstraint(item: keyboard, attribute: .centerY, relatedBy: .equal, toItem: self.view, attribute: .centerY, multiplier: 1.20, constant: 0)
        let keyboardHeightConstraint = NSLayoutConstraint(item: keyboard, attribute: .height, relatedBy: .equal, toItem: self.view, attribute: .height, multiplier: 0.80, constant: 0)
        let keyboardWidthConstraint = NSLayoutConstraint(item: keyboard, attribute: .width, relatedBy: .equal, toItem: self.view, attribute: .width, multiplier: 1.01, constant: 0)
        
        
        keyboard.delegate = self
        keyboard.polyphonicMode = true
        NSLayoutConstraint.activate([keyboardYconstraint, keyboardHeightConstraint, keyboardWidthConstraint])
    }
    
    let exportURL: URL = {
        let documentsURL = FileManager.default.temporaryDirectory
        return documentsURL.appendingPathComponent("exported_song.wav")
    }()
    
    func clearTmpDir(){
        
        var removed: Int = 0
        do {
            let tmpDirURL = URL(string: NSTemporaryDirectory())!
            let tmpFiles = try FileManager.default.contentsOfDirectory(at: tmpDirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            print("\(tmpFiles.count) temporary files found")
            for url in tmpFiles {
                removed += 1
                try FileManager.default.removeItem(at: url)
            }
            print("\(removed) temporary files removed")
        } catch {
            print(error)
            print("\(removed) temporary files removed")
        }
    }
}
