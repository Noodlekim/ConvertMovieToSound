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

    override func viewDidLoad() {
        super.viewDidLoad()
        checkAuthorizationForPhotoLibraryAndGet()
    }

    private func getPhotosAndVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate",ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d || mediaType = %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
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
                }else {

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
        let asset = imagesAndVideos.object(at: indexPath.item)

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

            let composition = AVMutableComposition()
            do {
                guard let audioAssetTrack = avasset?.tracks(withMediaType: AVMediaType.audio).first else { return }
                guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
                try audioCompositionTrack.insertTimeRange(audioAssetTrack.timeRange, of: audioAssetTrack, at: CMTime.zero)
            } catch {
                print(error)
            }

            let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory() + "out.m4a")
            print("path: \(outputUrl.absoluteString)")
            if FileManager.default.fileExists(atPath: outputUrl.path) {
                try? FileManager.default.removeItem(atPath: outputUrl.path)
            }

            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
            exportSession.outputFileType = AVFileType.mp4
            exportSession.outputURL = outputUrl

            exportSession.exportAsynchronously {
                guard case exportSession.status = AVAssetExportSession.Status.completed else { return }
                DispatchQueue.main.async {
                    // Present a UIActivityViewController to share audio file
                    guard let outputURL = exportSession.outputURL else { return }
                    let activityViewController = UIActivityViewController(activityItems: [outputURL], applicationActivities: [])
                    self.present(activityViewController, animated: true, completion: nil)
                }
            }
        }
    }
}
