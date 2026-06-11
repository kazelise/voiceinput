# Liquid Glass — Native Apple APIs (macOS 26/27) + kube.io Web Technique Reference

## Part A — Native SwiftUI API (PRIMARY for this app; all @available(macOS 26.0, *))

```swift
nonisolated func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()   // a Capsule
) -> some View

struct Glass {
    static var regular: Glass    // adaptive: blurs, adjusts luminance, works on any background
    static var clear: Glass      // highly transparent, minimal adaptivity — media-rich backgrounds
    static var identity: Glass   // no effect (conditional disabling without layout churn)
    func tint(_ color: Color?) -> Glass            // infuses color into material
    func interactive(_ isEnabled: Bool = true) -> Glass  // press scale/bounce/shimmer
}
```

Usage:
```swift
Text("Hello").padding().glassEffect()
Image(systemName: "scribble").frame(width: 44, height: 44)
    .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16))
```

Grouping/morphing (glass cannot sample other glass — siblings must share a container):
```swift
@Namespace private var ns
GlassEffectContainer(spacing: 40) {
    HStack(spacing: 40) {
        Image(systemName: "eraser.fill").frame(width: 80, height: 80)
            .glassEffect().glassEffectID("eraser", in: ns)
        if isExpanded {
            Image(systemName: "pencil").frame(width: 80, height: 80)
                .glassEffect().glassEffectID("pencil", in: ns)  // morphs out of neighbors
        }
    }
}
.animation(.spring, value: isExpanded)
```
Also: `.glassEffectUnion(id:namespace:)`, `.glassEffectTransition(.matchedGeometry/.materialize/.identity)`.

Button styles: `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` (+ `.tint`, `.buttonBorderShape`, `.controlSize`). Known artifact: .glassProminent + .circle may need `.clipShape(Circle())`.

New-design modifiers for a native-Tahoe/GoldenGate feel: `.backgroundExtensionEffect()` (extends content under sidebars), `.scrollEdgeEffectStyle(_:for:)`, `ToolbarSpacer(.fixed/.flexible)`, `.containerBackground(.clear, for: .navigation)`. NavigationSplitView + edge-to-edge sidebar = the macOS 27 layout direction.

AppKit equivalent (for NSPanel content): 
```swift
@available(macOS 26.0, *)
class NSGlassEffectView: NSView {
    var contentView: NSView?            // REQUIRED: set this, don't add subviews directly
    var cornerRadius: CGFloat
    var tintColor: NSColor?
    var style: NSGlassEffectView.Style  // .regular / .clear
}
class NSGlassEffectContainerView: NSView { var contentView: NSView?; var spacing: CGFloat }
```

### macOS 26.x behavior notes
- Glass auto-adapts to background, light/dark, accessibility (Reduce Transparency → frosty/opaque; Increase Contrast → borders; Reduce Motion → muted animation). Test all three.
- macOS 26.1+: System Settings → Appearance has user "Liquid Glass: Clear / Tinted" toggle — system glass APIs inherit it for free.

### macOS 27 "Golden Gate" (announced WWDC June 8, 2026)
- System-wide Liquid Glass OPACITY SLIDER (ultra-clear → fully tinted). Design consequence: don't hardcode opacity; treat in-app opacity control as an offset (scrim) on top of system glass.
- Refinements: darkened edge ring around glass, brighter specular highlights, more uniform refraction, better diffusion of busy backgrounds, tighter window corner radii, unified top toolbars, edge-to-edge (non-floating) sidebars.
- Same API surface as 26 (glassEffect/GlassEffectContainer/NSGlassEffectView) — adopt now, renders better on 27 automatically. Liquid Glass becomes mandatory with Xcode 27 SDK.

## Part B — USER-ADJUSTABLE transparency (no public opacity knob on Glass)

**Approach B (RECOMMENDED — precise, linear): glass + scrim overlay in the same shape.**
```swift
content
    .padding(16)
    .background {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            if !reduceTransparency && panelOpacity < 0.99 {
                Color.clear.glassEffect(.regular, in: shape)
            }
            shape.fill(Color(nsColor: .windowBackgroundColor)
                .opacity(reduceTransparency ? 1 : panelOpacity))  // 0 = pure glass, 1 = solid
        }
    }
```
- At opacity ≈ 1 drop the glass layer (saves GPU).
- Do NOT put `.opacity()` on the glassEffect view itself — fades panel AND content.
- Composes with the macOS 27 system slider (system controls glass, app controls scrim).

Approach A (alternative): `Glass.tint(color.opacity(x))` — tint alpha controls how strongly glass is painted over, but system modulates by background luminance (not perfectly linear). Variant switch: `.clear` when slider low, `.regular` when higher.

Approach D (required): respect `@Environment(\.accessibilityReduceTransparency)` → clamp opaque.

## Part C — kube.io CSS/SVG technique (VISUAL REFERENCE for the glass box aesthetic)

Pipeline: bezel height profile f(x) → Snell's-law ray trace (n=1.5) → 1D displacement table → swept around rounded-rect SDF into 2D displacement map (R=X, G=Y, 128=neutral) → SVG feDisplacementMap + specular rim via feBlend screen → backdrop-filter.

Key aesthetic takeaways to replicate natively ON TOP of system glass:
1. **Squircle bezel profile** `(1-(1-x)^4)^(1/4)` — flat center, refraction concentrated at edges. Apple's look.
2. **Refraction at the rim only** — the center of the panel is essentially clean blur; edges bend background inward. Native glassEffect already does this; don't fight it.
3. **Specular rim light**: thin (~1.5 px) white rim, intensity = |edge-normal · light-direction| (light at ~60°), quadratic alpha falloff `sqrt(1-(1-edgeRatio)^2)`. Natively: overlay shape stroke with angular gradient brightest at light angle, screen-ish blending, 1–1.5 pt width.
4. Displacement formula (if ever drawing custom refraction, e.g. Metal/Canvas): refracted dir t from Snell; lateral offset Δ(x) = t_x · (h / t_y) where h = f(x)·bezelWidth + glassThickness; normalize by max.
5. Chromatic aberration extension: 3 displacement passes at scale ×1.02/×1.0/×0.98 isolated to R/G/B then recombined — subtle color fringe at edges. (Native glass already shows slight edge dispersion on 26.x; more on 27.)

Sources: kube.io/blog/liquid-glass-css-svg, developer.apple.com docs for glassEffect/GlassEffectContainer/NSGlassEffectView, WWDC25 310 & 323, macOS 27 Golden Gate coverage (MacRumors/9to5Mac, 2026-06-08).
