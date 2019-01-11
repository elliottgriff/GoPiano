//
//  Recordings.swift
//  MyPiano
//
//  Created by elliott on 1/4/19.
//  Copyright © 2019 Elliott Griffin. All rights reserved.
//

import Foundation
import AudioKit
import AudioKitUI

class Recordings : UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var home: ViewController!
    var filePlayer: AKPlayer!
    var numberOfRecordings: Int = 0
    
    
    @IBOutlet weak var myTableView: UITableView!
    @IBOutlet weak var keyboardButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        do {
//            try AudioKit.start()
//        } catch {
//            print("error starting on recordings page")
//        }
        
        UserDefaults.standard.set(home.numberOfRecordings, forKey: "myNumber")


        
    }
    
    
    @IBAction func keyboardPagePressed(_ sender: UIButton) {
        print("keyboard page pressed")
    }
    
    func getDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = paths[0]
        return documentDirectory
    }
    
     func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return home.numberOfRecordings
    }
    
     func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = String(indexPath.row + 1)
        return cell
    }
    
     func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let path = getDirectory().appendingPathComponent("\(indexPath.row + 1).caf")
//            try AudioKit.start()
            filePlayer = AKPlayer(url: path)
            filePlayer.play()
            print("tried to play")
    }
}
