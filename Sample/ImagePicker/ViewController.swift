//
//  ViewController.swift
//  ImagePicker
//
//  Created by NoodleKim on 2022/08/22.
//

import UIKit
import Photos
import PhotosUI

class ViewController: UIViewController {

    @IBOutlet weak var collectionView: UICollectionView!
    var imagesAndVideos: PHFetchResult<PHAsset>!

    private var compressionAudioSettings: [String: Any] {

        var stereoChannelLayout = AudioChannelLayout()
        memset(&stereoChannelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        stereoChannelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let channelLayoutAsData = Data(bytes: &stereoChannelLayout, count: MemoryLayout<AudioChannelLayout>.size)

        return [
            AVFormatIDKey         : kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey   : 96000, // 96Kbps
            AVSampleRateKey       : 48000, //48k
            AVChannelLayoutKey    : channelLayoutAsData,
            AVNumberOfChannelsKey : 2
        ]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        checkAuthorizationForPhotoLibraryAndGet()
    }

    private func getPhotosAndVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate",ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        imagesAndVideos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        collectionView.reloadData()
    }

    private func checkAuthorizationForPhotoLibraryAndGet(){
        let status = PHPhotoLibrary.authorizationStatus()

        if (status == .authorized) {
            getPhotosAndVideos()
        } else {
            PHPhotoLibrary.requestAuthorization({ (newStatus) in
                if (newStatus == PHAuthorizationStatus.authorized) {
                    self.getPhotosAndVideos()
                }
            })
        }
    }

}

extension ViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        .init(width: 80, height: 80)
    }
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return imagesAndVideos.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AssetCell", for: indexPath) as? AssetCell else {
                fatalError("failed to dequeueReusableCellWithIdentifier(\"Cell\")")
        }
        let asset = imagesAndVideos.object(at: indexPath.section)

        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.isSynchronous = true
        manager.requestImage(for: asset, targetSize: .init(width: 80, height: 80), contentMode: .aspectFill, options: option, resultHandler: {(result, info)->Void in
            cell.imageView.image = result
        })
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        let asset = imagesAndVideos.object(at: indexPath.item)
        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avasset, AVAudioMix, dic in

            guard let avasset = avasset else { return }
            self.reencode(asset: avasset) { result in
                switch result {
                case let .success(url):
                    print("success url: \(url)")

                    let convertedAsset = AVURLAsset(url: url)
                    guard let audioAssetTrack = convertedAsset.tracks(withMediaType: .audio).first else { return }
                    print("sample rate: \(String(describing: (audioAssetTrack.formatDescriptions.first as! CMAudioFormatDescription).audioStreamBasicDescription?.mSampleRate))")
                    print("estimatedDataRate: \(String(describing: audioAssetTrack.estimatedDataRate))")
                    print("bit rate: \(String(describing: convertedAsset.bitrate))")

                    print("asset url: \(String(describing: url))")


                    let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory() + "out.mp4")
                    print("path: \(outputUrl.absoluteString)")
                    if FileManager.default.fileExists(atPath: outputUrl.path) {
                        try? FileManager.default.removeItem(atPath: outputUrl.path)
                    }

                    let exportSession = AVAssetExportSession(asset: convertedAsset, presetName: AVAssetExportPresetPassthrough)!
                    exportSession.outputFileType = .mp4
                    exportSession.outputURL = outputUrl

                    exportSession.exportAsynchronously {
                        guard case exportSession.status = AVAssetExportSession.Status.completed else { return }
                        DispatchQueue.main.async {
                            // Present a UIActivityViewController to share audio file
                            guard let outputURL = exportSession.outputURL else { return }
                            print("outputUrl: \(String(describing: outputURL))")
                        }
                    }

                case let .failure(error):
                    print("error: \(error)")
                }
            }
        }
    }

    private func reencode(asset: AVAsset, completion: @escaping ((Result<URL, Error>) -> Void)) {
        let dispatchGroup = DispatchGroup()
        let mainSerializationQueue = DispatchQueue(label: "\(self) serialization queue")

        let rwAudioSerializationQueue = DispatchQueue(label: "\(self) rw audio serialization queue")

        let filepath = NSTemporaryDirectory() + UUID().uuidString + ".mp4"
        let outputURL = URL(fileURLWithPath: filepath)
        if FileManager.default.fileExists(atPath: filepath) {
            do {
                try FileManager.default.removeItem(atPath: filepath)
            } catch {
                fatalError("")
            }
        }

        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {

            mainSerializationQueue.async {
                let assetReader: AVAssetReader
                let assetWriter: AVAssetWriter

                do {
                    assetReader = try AVAssetReader(asset: asset)
                    assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                } catch {
                    return
                }


                // MARK: - Audio Track
                /// If the reader and writer were successfully initialized, grab the audio and video asset tracks that will be used.
                guard let assetAudioTrack = asset.tracks(withMediaType: .audio).first else {
                    fatalError("assetAudioTrack nil")
                }

                /// If there is an audio track to read, set the decompression to Linear PCM and create the asset reader output.
                let decompressionAudioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM]
                let assetReaderAudioOutput = AVAssetReaderTrackOutput(track: assetAudioTrack, outputSettings: decompressionAudioSettings)
                guard assetReader.canAdd(assetReaderAudioOutput) else {
                    fatalError("Can't add ...")
                }

                assetReader.add(assetReaderAudioOutput)


                let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: self.compressionAudioSettings)
                guard assetWriter.canAdd(assetWriterAudioInput) else {
                    fatalError("Can't add ...")
                }
                assetWriter.add(assetWriterAudioInput)

                // MARK: - Reencoding the Asset
                /// Attempt to start the asset reader.
                guard assetReader.startReading() else {
                    completion(.failure(VideoExporterError.completeWithError))
                    return
                }
                /// If the reader started successfully, attempt to start the asset writer.
                guard assetWriter.startWriting() else {
                    completion(.failure(VideoExporterError.completeWithError))
                    return
                }

                assetWriter.startSession(atSourceTime: .zero)

                dispatchGroup.enter()
                assetWriterAudioInput.requestMediaDataWhenReady(on: rwAudioSerializationQueue) {
                    while assetWriterAudioInput.isReadyForMoreMediaData {
                        if let sampleBuffer = assetReaderAudioOutput.copyNextSampleBuffer() {
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            print("presentationTime", presentationTime.seconds)
                            assetWriterAudioInput.append(sampleBuffer)
                        } else {
                            assetWriterAudioInput.markAsFinished()
                            dispatchGroup.leave()
                            break
                        }
                    }

                    print("Audio Input ", terminator: "")
                    switch assetReader.status {
                    case .cancelled:
                        print("cancelled")
                    case .completed:
                        print("completed")
                    case .reading:
                        print("reading")
                    case .failed:
                        print("failed")
                    case .unknown:
                        print("unknown")
                    @unknown default:
                        fatalError()
                    }
                }

                dispatchGroup.notify(queue: mainSerializationQueue, work: DispatchWorkItem {
                    assetWriter.finishWriting {
                        print("Finish writing completed")
                        completion(.success(outputURL))
                    }
                })
            }
        }
    }

}

extension AVURLAsset {

    var fileSize : Int? {
        let keys: Set<URLResourceKey> = [.totalFileSizeKey, .fileSizeKey]
        let resourceValues = try? url.resourceValues(forKeys: keys)
        return resourceValues?.fileSize ?? resourceValues?.totalFileSize
    }

    // kbps
    var bitrate : Int {

        if (fileSize ?? 0) > 0 && duration.seconds > 0 {
            return Int(Double(fileSize ?? 0) * 8 / 1000 / duration.seconds)
        }
        return 0
    }
}

enum VideoExporterError: Error {
    case completeWithError
}
