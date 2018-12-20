//
//  Recordings.swift
//  MyPiano
//
//  Created by elliott on 12/11/18.
//  Copyright © 2018 Elliott Griffin. All rights reserved.
//

import UIKit
import AudioKit
import AudioKitUI

public class Recordings: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var player: AVAudioPlayer!
    var numberOfRecordings:Int = 0
    
    @IBOutlet weak var myTableView: UITableView!
    

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let number:Int = UserDefaults.standard.object(forKey: "myNumber") as? Int {
            numberOfRecordings = number
        }
    }
    //Get Directory Path
    func getDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = paths[0]
        return documentDirectory
    }
    

    
    //Display Alerts
    func displayAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "dismiss", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfRecordings
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = String(indexPath.row + 1)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let path = getDirectory().appendingPathComponent("\(indexPath.row + 1).m4a")
        player = try! AVAudioPlayer(contentsOf: path)
        player.play()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
