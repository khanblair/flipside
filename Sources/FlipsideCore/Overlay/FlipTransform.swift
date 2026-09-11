import QuartzCore

/// Builds the `CATransform3D` used to animate the card window's flip (spec §8.2).
public enum FlipTransform {
    /// Returns a perspective transform rotated around the Y axis.
    ///
    /// - Parameters:
    ///   - angleDegrees: Rotation angle in degrees. `0` is the resting (front-facing) orientation.
    ///   - perspectiveDistance: Distance used to derive the `m34` perspective component
    ///     (`transform.m34 = -1.0 / perspectiveDistance`), per the spec's standard trick.
    public static func transform(angleDegrees: CGFloat, perspectiveDistance: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m34 = -1.0 / perspectiveDistance
        let angleRadians = angleDegrees * .pi / 180
        return CATransform3DRotate(t, angleRadians, 0, 1, 0)
    }
}
