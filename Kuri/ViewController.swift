//
//  ViewController.swift
//  Kuri
//
//  Created by Tsuyoshi Yamaguchi on 2019/01/22.
//  Copyright © 2019 ronoya442. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation

private func AudioQueueInputCallback(
    _ inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef,
    inStartTime: UnsafePointer<AudioTimeStamp>,
    inNumberPacketDescriptions: UInt32,
    inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?)
{
    // Do nothing, because not recoding.
}


class ViewController: UIViewController {
    @IBOutlet weak var loudLabel: UILabel!
    
    @IBOutlet weak var peakTextField: UITextField!
    @IBOutlet weak var averageTextField: UITextField!
    @IBOutlet weak var timeTextField: UITextField!
    
    var queue: AudioQueueRef!
    var timer: Timer!
    var audioPlayer: AVAudioPlayer!
    var startTime: NSDate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.startUpdatingVolume()
        
        let sound = Bundle.main.path(forResource: "beep-02", ofType: "mp3")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: sound!))
            audioPlayer!.volume = 1.0
        }
        catch {
            
        }
        
        let session = AVAudioSession.sharedInstance()
        // オーディオ周りの認証要求
        session.requestRecordPermission {_ in
            do {
                // bluetooth機器として設定
                try session.setCategory(.playAndRecord, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetoothA2DP)
                try session.overrideOutputAudioPort(.none)
                try session.setActive(true)
            } catch {
            }            
        }
        
        // Bluetoothイヤホンを使っているとしてもiPhoneビルトインのマイクを使う
        for portDesc in session.availableInputs! {
            if(portDesc.portType == AVAudioSession.Port.builtInMic) {
                try! session.setPreferredInput(portDesc)
            }
        }

    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.stopUpdatingVolume()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Internal methods
    func startUpdatingVolume() {
        // Set data format
        var dataFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: AudioFormatFlags(kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0)
        
        // Observe input level
        var audioQueue: AudioQueueRef? = nil
        var error = noErr
        error = AudioQueueNewInput(
            &dataFormat,
            AudioQueueInputCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            .none,
            .none,
            0,
            &audioQueue)
        if error == noErr {
            self.queue = audioQueue
        }
        AudioQueueStart(self.queue, nil)
        
        // Enable level meter
        var enabledLevelMeter: UInt32 = 1
        AudioQueueSetProperty(self.queue, kAudioQueueProperty_EnableLevelMetering, &enabledLevelMeter, UInt32(MemoryLayout<UInt32>.size))
        
        // 10ms周期で音量の検出を繰り返し行う
        self.timer = Timer.scheduledTimer(timeInterval: 0.01,
                                          target: self,
                                          selector: #selector(ViewController.detectVolume(_:)),
                                          userInfo: nil,
                                          repeats: true)
        self.timer?.fire()
    }
    
    func stopUpdatingVolume()
    {
        // Finish observation
        self.timer.invalidate()
        self.timer = nil
        AudioQueueFlush(self.queue)
        AudioQueueStop(self.queue, false)
        AudioQueueDispose(self.queue, true)
    }
    
    @objc func detectVolume(_ timer: Timer)
    {
        // Get level
        var levelMeter = AudioQueueLevelMeterState()
        var propertySize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size)
        
        AudioQueueGetProperty(
            self.queue,
            kAudioQueueProperty_CurrentLevelMeterDB,
            &levelMeter,
            &propertySize)
        
        // Show the audio channel's peak and average RMS power.
        self.peakTextField.text = "".appendingFormat("%.2f", levelMeter.mPeakPower)
        self.averageTextField.text = "".appendingFormat("%.2f", levelMeter.mAveragePower)
        
        // 検出した音量が一定値を超えたら、タイマーを停止し & ラベルを表示する
        if (levelMeter.mPeakPower >= -30.0) {
            self.loudLabel.isHidden = false
            stopTimer()
        } else {
            self.loudLabel.isHidden = true
        }
    }
    
    func startTimer() {
        startTime = NSDate()
    }
    
    func stopTimer() {
        // タイマーを止めて、開始から停止までの時間を表示する
        if let time = startTime {
            let elapsed = -time.timeIntervalSinceNow
            timeTextField.text = "".appendingFormat("%.3f", elapsed)
            print(elapsed)
            startTime = nil
        }
    }
    
    @IBAction func beepButtonTouched(_ sender: UIButton) {
        // ボタンがタップされたら、音を鳴らすと同時にタイマーをスタートする
        startTimer()
        audioPlayer.play()
    }
}

