import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard UserDefaults.standard.bool(forKey: "parkPrivateSnapshot"),
          !AppDelegate.authenticating,
          let window = window, privacyCover == nil else { return }
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.isUserInteractionEnabled = false
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
