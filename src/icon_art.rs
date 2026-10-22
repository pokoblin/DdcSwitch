// Procedurally drawn app icon (a monitor with a "switch" double arrow).
// Shared by build.rs (to produce the .ico embedded in the exe) and the app
// (to create the tray icon at the exact size the shell asks for).

const DARK: [f32; 3] = [38.0, 50.0, 56.0];
const MID: [f32; 3] = [84.0, 110.0, 122.0];
const SCREEN_TOP: [f32; 3] = [41.0, 182.0, 246.0];
const SCREEN_BOTTOM: [f32; 3] = [30.0, 110.0, 229.0];
const WHITE: [f32; 3] = [255.0, 255.0, 255.0];

/// Returns `size * size` pixels as straight-alpha RGBA, rows top-down.
#[allow(dead_code)]
pub fn render_icon_rgba(size: u32) -> Vec<u8> {
    const SS: u32 = 4;
    let s = size as f32;
    // Keep arrow strokes at least ~1.3px wide so the glyph survives at 16x16.
    let stroke = (0.08f32).max(1.3 / s);
    let mut out = Vec::with_capacity((size * size * 4) as usize);
    for py in 0..size {
        for px in 0..size {
            let mut acc = [0.0f32; 3];
            let mut hits = 0u32;
            for sy in 0..SS {
                for sx in 0..SS {
                    let u = (px as f32 + (sx as f32 + 0.5) / SS as f32) / s;
                    let v = (py as f32 + (sy as f32 + 0.5) / SS as f32) / s;
                    if let Some(c) = shade(u, v, stroke) {
                        acc[0] += c[0];
                        acc[1] += c[1];
                        acc[2] += c[2];
                        hits += 1;
                    }
                }
            }
            if hits == 0 {
                out.extend_from_slice(&[0, 0, 0, 0]);
            } else {
                let n = hits as f32;
                out.push((acc[0] / n).round() as u8);
                out.push((acc[1] / n).round() as u8);
                out.push((acc[2] / n).round() as u8);
                out.push((255.0 * n / (SS * SS) as f32).round() as u8);
            }
        }
    }
    out
}

fn shade(u: f32, v: f32, stroke: f32) -> Option<[f32; 3]> {
    let mut c = None;
    // stand base + neck
    if in_rrect(u, v, 0.5, 0.885, 0.24, 0.05, 0.035) {
        c = Some(DARK);
    }
    if (0.43..=0.57).contains(&u) && (0.70..=0.86).contains(&v) {
        c = Some(MID);
    }
    // bezel + screen
    if in_rrect(u, v, 0.5, 0.42, 0.48, 0.33, 0.08) {
        c = Some(DARK);
    }
    if in_rrect(u, v, 0.5, 0.41, 0.40, 0.25, 0.04) {
        let t = ((v - 0.16) / 0.50).clamp(0.0, 1.0);
        c = Some([
            SCREEN_TOP[0] + (SCREEN_BOTTOM[0] - SCREEN_TOP[0]) * t,
            SCREEN_TOP[1] + (SCREEN_BOTTOM[1] - SCREEN_TOP[1]) * t,
            SCREEN_TOP[2] + (SCREEN_BOTTOM[2] - SCREEN_TOP[2]) * t,
        ]);
    }
    // ⇄ arrows
    if in_arrow(u, v, 0.25, 0.75, 0.32, stroke) || in_arrow(u, v, 0.75, 0.25, 0.51, stroke) {
        c = Some(WHITE);
    }
    c
}

fn in_rrect(u: f32, v: f32, cx: f32, cy: f32, hw: f32, hh: f32, r: f32) -> bool {
    let qx = (u - cx).abs() - (hw - r);
    let qy = (v - cy).abs() - (hh - r);
    let outside = (qx.max(0.0).powi(2) + qy.max(0.0).powi(2)).sqrt();
    outside + qx.max(qy).min(0.0) - r <= 0.0
}

/// Horizontal arrow from `tail` to `tip` (either direction) at height `y`.
fn in_arrow(u: f32, v: f32, tail: f32, tip: f32, y: f32, stroke: f32) -> bool {
    let dir = if tip > tail { 1.0 } else { -1.0 };
    let head_len = 0.17;
    let head_half = 0.12;
    // distance from the tip along the arrow, positive towards the tail
    let d = (tip - u) * dir;
    let shaft_len = (tip - tail).abs();
    if d >= head_len * 0.8 && d <= shaft_len && (v - y).abs() <= stroke / 2.0 {
        return true;
    }
    // triangular head: half-height grows linearly from 0 at the tip
    d >= 0.0 && d <= head_len && (v - y).abs() <= head_half * d / head_len
}
