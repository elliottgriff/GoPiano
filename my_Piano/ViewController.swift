//
//  ViewController.swift
//  my_Piano
//
//  Created by elliott on 9/21/18.
//  Copyright © 2018 Elliott Griffin. All rights reserved.
//

import UIKit
import AudioKit
import AudioKitUI

class ViewController: UIViewController, AKKeyboardDelegate {
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    var midiSample = AKMIDISampler()
    var recorder = try! AKNodeRecorder()
    var player: AKPlayer!
    var tape = try! AKAudioFile()
    var mix = AKMixer()
    
    var state = State.readyToRecord
    
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var recButton: UIButton!
    @IBOutlet private weak var upOctaveButton: UIButton!
    @IBOutlet private weak var downOctaveButton: UIButton!
    
    
    enum State {
        case readyToRecord
        case recording
        case readyToPlay
        case playing
        
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        AKAudioFile.cleanTempDirectory()
        
        AKSettings.bufferLength = .medium
        
        do {
            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetoothA2DP)
        } catch {
            AKLog("Could not set session category.")
        }
        
        AKSettings.defaultToSpeaker = true
        AKSettings.audioInputEnabled = true
        
        do {
            try midiSample.loadMelodicSoundFont("gpiano", preset: 0)
        } catch {
            print("error playing")
        }
        
        let reverb = AKReverb(midiSample)
        reverb.loadFactoryPreset(.mediumRoom)
        mix = AKMixer(reverb)
        
        recorder = try! AKNodeRecorder(node: mix)
        
        if let file = recorder.audioFile {
            player = AKPlayer(audioFile: file)
        }
        
        player.isLooping = true
        //        player.buffering = .always
        player.completionHandler = playingEnded
        
        AudioKit.output = mix
        do {
            try AudioKit.start()
        } catch {
            AKLog("AudioKit did not start!")
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupButtonNames()
        setupUIForRecording()
        setupKeyboardUI()
        
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
    
    func playingEnded() {
        DispatchQueue.main.async {
            self.setupUIForPlaying ()
        }
    }
    
    //MARK:  Buttons
    
    
    
    @IBAction func upButtonPressed(_ sender: UIButton) {
        
    }
    
    
    @IBAction func downButtonPressed(_ sender: UIButton) {
        
    }
    
    
    
    @IBAction func recButtonTouched(sender: UIButton) {
        switch state {
        case .readyToRecord :
            recButton.setTitle("STOP", for: .normal)
            state = .recording
            do {
                try recorder.record()
            } catch { AKLog("Errored recording.") }
            
            
        case .recording :
            tape = recorder.audioFile!
            player.load(audioFile: tape)
            
            
            if let _ = player.audioFile?.duration {
                recorder.stop()
                tape.exportAsynchronously(name: "test.caf",
                                          baseDir: .temp,
                                          exportFormat: .caf) {_, exportError in
                                            if let error = exportError {
                                                AKLog("Export Failed \(error)")
                                            } else {
                                                AKLog("Export succeeded")
                                            }
                }
                setupUIForPlaying()
            }
        case .readyToPlay :
            player.play()
            recButton.setTitle("STOP", for: .normal)
            state = .playing
            
        case .playing :
            player.stop()
            setupUIForPlaying()
        }
    }
    
    struct Constants {
        static let empty = ""
    }
    
    
    func setupButtonNames() {
        recButton.setTitle(Constants.empty, for: UIControl.State.disabled)
    }
    
    func setupUIForRecording () {
        state = .readyToRecord
        infoLabel.text = "0.0"
        recButton.setTitle("RECORD", for: .normal)
        resetButton.isHidden = false
        resetButton.isEnabled = true
        recorder = try! AKNodeRecorder(node: mix)
    }
    
    func setupUIForPlaying () {
        let recordedDuration = player != nil ? player.audioFile?.duration  : 0
        infoLabel.text = "\(String(format: "%0.01f", recordedDuration!))"
        recButton.setTitle("PLAY", for: .normal)
        state = .readyToPlay
        resetButton.isHidden = false
        resetButton.isEnabled = true
        //        player.load(audioFile: recorder.audioFile!)
        AudioKit.output = player
    }
    
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        do {
            try recorder.reset()
        } catch { AKLog("Errored resetting.") }
        
        //        player.load(audioFile: recorder.audioFile!)
        setupUIForRecording()
    }
    
    
    private func setupKeyboardUI() {
        let keyboard = Keyboard(width: 1,
                                height: 0,
                                firstOctave: 4,
                                octaveCount: 1)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(keyboard)
        let keyboardYconstraint = NSLayoutConstraint(item: keyboard, attribute: .centerY, relatedBy: .equal, toItem: self.view, attribute: .centerY, multiplier: 1.20, constant: 0)
        let keyboardHeightConstraint = NSLayoutConstraint(item: keyboard, attribute: .height, relatedBy: .equal, toItem: self.view, attribute: .height, multiplier: 0.80, constant: 0)
        let keyboardWidthConstraint = NSLayoutConstraint(item: keyboard, attribute: .width, relatedBy: .equal, toItem: self.view, attribute: .width, multiplier: 1.01, constant: 0)
        
        
        keyboard.delegate = self
        keyboard.polyphonicMode = true
        NSLayoutConstraint.activate([keyboardYconstraint, keyboardHeightConstraint, keyboardWidthConstraint])
    }
}

