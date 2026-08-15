import ARKit
import SwiftUI

/// Thin wrapper that displays the live camera feed for an existing `ARSession`.
/// Purely optional for the MVP — smile detection works identically whether or
/// not this preview is shown on screen.
struct CameraPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
