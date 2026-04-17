// shake-to-find: マウスを振ったらカーソル位置に大きなカーソル画像を
// フェードイン→フェードアウトで重ねる (KDE Plasma / macOS 風)。
//
// - XInput2 RawMotion でイベント駆動
// - shake 判定: path_length / displacement 比 + 最小速度
// - overlay: ARGB32 visual + override_redirect + Shape(INPUT空) で click-through
// - カーソル素材: xcursor クレートで別色 flavor を読み込み → 事前スケール済みキャッシュ

#![warn(clippy::pedantic)]
// 画像処理やアニメ算出で f64↔整数 cast が大量に出る。意図した truncation / 精度損失。
// カーソル座標も u32→i32 wrap の心配はない（画像サイズはせいぜい数百 px）。
#![allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss,
    clippy::cast_lossless,
    clippy::cast_possible_wrap,
    clippy::similar_names,
    clippy::single_match_else,
    clippy::too_many_lines,
    clippy::missing_errors_doc,
    clippy::missing_panics_doc
)]

use std::collections::VecDeque;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};

use serde::Deserialize;
use x11rb::connection::{Connection, RequestConnection};
use x11rb::protocol::Event;
use x11rb::protocol::shape::{self, ConnectionExt as _, SK, SO};
use x11rb::protocol::xfixes::ConnectionExt as _;
use x11rb::protocol::xinput::{self, ConnectionExt as _};
use x11rb::protocol::xproto::{
    ClipOrdering, ColormapAlloc, ConfigureWindowAux, ConnectionExt as _, CreateGCAux,
    CreateWindowAux, EventMask, ImageFormat, VisualClass, WindowClass,
};

// ---------- Tuning constants ----------

/// アニメーション描画間隔 (ms)。50fps 相当。
const FRAME_INTERVAL_MS: u64 = 20;
/// 振り判定に必要な最小サンプル数。
const MIN_SAMPLES: usize = 4;
/// 事前スケール段階数。大きいほどサイズ変化が連続的に見える。
const SCALE_STEPS: usize = 30;

// ---------- Config ----------

#[derive(Deserialize, Debug, Clone)]
#[serde(default)]
struct Shake {
    window_ms: u64,
    ratio_threshold: f64,
    min_path_px: f64,
    min_avg_speed: f64,
    cooldown_ms: u64,
}

impl Default for Shake {
    fn default() -> Self {
        Self {
            window_ms: 400,
            ratio_threshold: 4.0,
            min_path_px: 300.0,
            min_avg_speed: 600.0,
            cooldown_ms: 1500,
        }
    }
}

#[derive(Deserialize, Debug, Clone)]
#[serde(default)]
struct CursorCfg {
    theme: String,
    shape: String,
    base_size: u32,
    peak_scale: f64,
    duration_ms: u64,
}

impl Default for CursorCfg {
    fn default() -> Self {
        Self {
            theme: "catppuccin-mocha-mauve-cursors".into(),
            shape: "left_ptr".into(),
            base_size: 48,
            peak_scale: 2.5,
            duration_ms: 400,
        }
    }
}

#[derive(Deserialize, Debug, Clone, Default)]
#[serde(default)]
struct Config {
    shake: Shake,
    cursor: CursorCfg,
}

fn load_config() -> Config {
    // config_dir が決まらない環境（XDG も HOME もない）ではファイル読み込みを諦めて
    // デフォルト設定で起動する。/tmp など world-writable なパスを参照して、
    // 他ユーザーの影響を受けないようにする。
    let Some(config_dir) = dirs::config_dir() else {
        eprintln!("[info] no config directory available — using defaults");
        return Config::default();
    };
    let path: PathBuf = config_dir.join("shake-to-find/config.toml");
    match std::fs::read_to_string(&path) {
        Ok(s) => match toml::from_str::<Config>(&s) {
            Ok(c) => {
                eprintln!("[info] loaded config from {}", path.display());
                c
            }
            Err(e) => {
                eprintln!(
                    "[warn] parse error on {}: {e} — using defaults",
                    path.display()
                );
                Config::default()
            }
        },
        Err(_) => {
            eprintln!("[info] no config at {} — using defaults", path.display());
            Config::default()
        }
    }
}

// ---------- Cursor image ----------

#[derive(Clone)]
struct CursorImage {
    width: u32,
    height: u32,
    /// hot point（カーソル先端が指す座標）。スケール時はここもスケールする。
    xhot: u32,
    yhot: u32,
    /// X11 little-endian ARGB32 の並び (= BGRA バイト列)、pre-multiplied alpha
    bgra: Vec<u8>,
}

fn load_cursor(theme_name: &str, shape: &str, base_size: u32) -> Result<CursorImage, String> {
    let theme = xcursor::CursorTheme::load(theme_name);
    let path = theme
        .load_icon(shape)
        .ok_or_else(|| format!("cursor icon '{shape}' not found in theme '{theme_name}'"))?;
    let data = std::fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let images =
        xcursor::parser::parse_xcursor(&data).ok_or_else(|| "parse_xcursor failed".to_string())?;
    if images.is_empty() {
        return Err("no images in cursor file".into());
    }
    let mut sizes: Vec<u32> = images.iter().map(|i| i.width).collect();
    sizes.sort_unstable();
    sizes.dedup();
    eprintln!("[info] cursor available sizes: {sizes:?}");
    // base_size=0 → 利用可能な最大サイズ。それ以外は最も近いサイズ。
    // 大きいサイズをベースにしてからスケールすると、ジャギが減る。
    let best = if base_size == 0 {
        images.iter().max_by_key(|i| i.width).unwrap().clone()
    } else {
        images
            .iter()
            .min_by_key(|i| (i.width as i64 - base_size as i64).abs())
            .unwrap()
            .clone()
    };
    // xcursor は pixels_rgba ([R,G,B,A]) を提供。X11 ARGB32 は native-endian u32 AARRGGBB なので
    // little-endian 上でのバイト配置は [B,G,R,A]。順序を入れ替える。
    let mut bgra = vec![0u8; best.pixels_rgba.len()];
    for i in (0..best.pixels_rgba.len()).step_by(4) {
        bgra[i] = best.pixels_rgba[i + 2]; // B
        bgra[i + 1] = best.pixels_rgba[i + 1]; // G
        bgra[i + 2] = best.pixels_rgba[i]; // R
        bgra[i + 3] = best.pixels_rgba[i + 3]; // A
    }
    Ok(CursorImage {
        width: best.width,
        height: best.height,
        xhot: best.xhot,
        yhot: best.yhot,
        bgra,
    })
}

/// Bilinear 補間で倍率 factor にリサイズ。
/// pre-multiplied alpha を保ったまま補間できるので、この pipeline でそのまま使える。
fn scale_bilinear(src: &CursorImage, factor: f64) -> CursorImage {
    let nw = ((src.width as f64) * factor).round().max(1.0) as u32;
    let nh = ((src.height as f64) * factor).round().max(1.0) as u32;
    let sw = src.width;
    let sh = src.height;
    let max_x = (sw - 1) as f64;
    let max_y = (sh - 1) as f64;
    let mut dst = vec![0u8; (nw as usize) * (nh as usize) * 4];

    for y in 0..nh {
        let fy = ((y as f64) / factor).clamp(0.0, max_y);
        let y0 = fy.floor() as u32;
        let y1 = (y0 + 1).min(sh - 1);
        let wy = fy - y0 as f64;

        for x in 0..nw {
            let fx = ((x as f64) / factor).clamp(0.0, max_x);
            let x0 = fx.floor() as u32;
            let x1 = (x0 + 1).min(sw - 1);
            let wx = fx - x0 as f64;

            let i00 = ((y0 * sw + x0) * 4) as usize;
            let i01 = ((y0 * sw + x1) * 4) as usize;
            let i10 = ((y1 * sw + x0) * 4) as usize;
            let i11 = ((y1 * sw + x1) * 4) as usize;
            let di = ((y * nw + x) * 4) as usize;

            for c in 0..4 {
                let p00 = src.bgra[i00 + c] as f64;
                let p01 = src.bgra[i01 + c] as f64;
                let p10 = src.bgra[i10 + c] as f64;
                let p11 = src.bgra[i11 + c] as f64;
                let top = p00 * (1.0 - wx) + p01 * wx;
                let bot = p10 * (1.0 - wx) + p11 * wx;
                let v = top * (1.0 - wy) + bot * wy;
                dst[di + c] = v.round().clamp(0.0, 255.0) as u8;
            }
        }
    }

    CursorImage {
        width: nw,
        height: nh,
        xhot: ((src.xhot as f64) * factor).round() as u32,
        yhot: ((src.yhot as f64) * factor).round() as u32,
        bgra: dst,
    }
}

/// α を掛けて pre-multiplied 済み BGRA を再スケール (pre * a)。
/// 事前確保したバッファに書き込んで毎フレームの allocate を回避する。
fn apply_alpha_into(src: &CursorImage, a: f64, out: &mut Vec<u8>) {
    out.clear();
    out.extend_from_slice(&src.bgra);
    let a = a.clamp(0.0, 1.0);
    for px in out.chunks_exact_mut(4) {
        for c in px.iter_mut() {
            *c = ((*c as f64) * a) as u8;
        }
    }
}

// ---------- Animation schedule ----------

/// t ∈ [0, duration] に対して (scale, alpha) を返す。
/// 配分: 拡大 0..15% (cubic ease-out) / 保持 15..50% / 戻り 50..100% (cubic ease-in-out)
/// 戻り区間を長めに取り、ease-in-out で両端を滑らかにして「スッと戻る」感を出す。
fn frame_params(t_ms: u64, duration_ms: u64, peak_scale: f64) -> (f64, f64) {
    let t = (t_ms as f64 / duration_ms as f64).clamp(0.0, 1.0);
    if t < 0.15 {
        let u = t / 0.15;
        let eased = 1.0 - (1.0 - u).powi(3);
        (1.0 + (peak_scale - 1.0) * eased, eased)
    } else if t < 0.50 {
        (peak_scale, 1.0)
    } else {
        let u = (t - 0.50) / 0.50;
        // cubic ease-in-out
        let eased = if u < 0.5 {
            4.0 * u * u * u
        } else {
            1.0 - (-2.0 * u + 2.0).powi(3) / 2.0
        };
        let scale = peak_scale - (peak_scale - 1.0) * eased;
        // alpha は scale より少し遅れてフェード（最後の 30% で消える）
        let alpha_u = ((u - 0.4) / 0.6).clamp(0.0, 1.0);
        let alpha_eased = 1.0 - (1.0 - alpha_u).powi(2);
        (scale, 1.0 - alpha_eased)
    }
}

// ---------- Overlay ----------

struct OverlayResources {
    visual_id: u32,
    depth: u8,
    colormap: u32,
}

fn find_argb_visual<C: Connection>(
    conn: &C,
    screen_idx: usize,
) -> Result<OverlayResources, Box<dyn std::error::Error>> {
    let screen = &conn.setup().roots[screen_idx];
    let depth_32 = screen
        .allowed_depths
        .iter()
        .find(|d| d.depth == 32)
        .ok_or("no 32-bit depth available (compositor running?)")?;
    let visual = depth_32
        .visuals
        .iter()
        .find(|v| v.class == VisualClass::TRUE_COLOR)
        .ok_or("no TrueColor visual at depth 32")?;
    let colormap = conn.generate_id()?;
    conn.create_colormap(ColormapAlloc::NONE, colormap, screen.root, visual.visual_id)?;
    Ok(OverlayResources {
        visual_id: visual.visual_id,
        depth: 32,
        colormap,
    })
}

fn show_overlay<C: Connection>(
    conn: &C,
    screen_idx: usize,
    res: &OverlayResources,
    scaled_frames: &[CursorImage],
    duration_ms: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let screen = &conn.setup().roots[screen_idx];
    let root = screen.root;

    let win = conn.generate_id()?;
    let gc = conn.generate_id()?;

    // 途中のエラーで本物のカーソルが隠れたまま残らないよう、hide_cursor 後の処理は
    // 別関数に閉じ込めて、戻り値に関わらず最後に show_cursor / destroy_window / free_gc
    // を必ず呼ぶ。ID が未使用な場合は X サーバ側でエラーになるが握り潰す。
    let result = run_overlay(conn, res, scaled_frames, duration_ms, root, win, gc);

    let _ = conn.xfixes_show_cursor(root);
    let _ = conn.destroy_window(win);
    let _ = conn.free_gc(gc);
    let _ = conn.flush();

    result
}

fn run_overlay<C: Connection>(
    conn: &C,
    res: &OverlayResources,
    scaled_frames: &[CursorImage],
    duration_ms: u64,
    root: u32,
    win: u32,
    gc: u32,
) -> Result<(), Box<dyn std::error::Error>> {
    // ピーク画像サイズで window を作り、その中で描画を差し替える
    let peak = scaled_frames.last().unwrap();
    let ww = peak.width as u16;
    let wh = peak.height as u16;
    let peak_xhot = peak.xhot as i32;
    let peak_yhot = peak.yhot as i32;

    let initial = conn.query_pointer(root)?.reply()?;
    let initial_wx = initial.root_x as i32 - peak_xhot;
    let initial_wy = initial.root_y as i32 - peak_yhot;

    let values = CreateWindowAux::new()
        .background_pixel(0)
        .border_pixel(0)
        .colormap(res.colormap)
        .override_redirect(1)
        .event_mask(EventMask::NO_EVENT);
    conn.create_window(
        res.depth,
        win,
        root,
        initial_wx as i16,
        initial_wy as i16,
        ww,
        wh,
        0,
        WindowClass::INPUT_OUTPUT,
        res.visual_id,
        &values,
    )?;

    // click-through: input shape を空に
    conn.shape_rectangles(SO::SET, SK::INPUT, ClipOrdering::UNSORTED, win, 0, 0, &[])?;
    conn.create_gc(gc, win, &CreateGCAux::new())?;
    conn.map_window(win)?;
    conn.xfixes_hide_cursor(root)?;
    conn.flush()?;

    let peak_scale = peak_scale_of(scaled_frames);
    let frame_interval = Duration::from_millis(FRAME_INTERVAL_MS);
    let total = Duration::from_millis(duration_ms);
    let start = Instant::now();
    let mut frame_buf: Vec<u8> = Vec::with_capacity(peak.bgra.len());

    while start.elapsed() < total {
        let t_ms = start.elapsed().as_millis() as u64;
        let (scale, alpha) = frame_params(t_ms, duration_ms, peak_scale);
        let img = pick_frame(scaled_frames, scale);
        apply_alpha_into(img, alpha, &mut frame_buf);

        // マウスを振った後もオーバーレイが追従するよう毎フレーム query_pointer で座標を取る。
        // 20ms 周期・μs オーダの round-trip なので実測で CPU / X server 負荷は無視できる。
        // RawMotion delta を積分する手もあるが相対誤差が蓄積しうるため採用見送り。
        let pointer = conn.query_pointer(root)?.reply()?;
        let wx = pointer.root_x as i32 - peak_xhot;
        let wy = pointer.root_y as i32 - peak_yhot;
        conn.configure_window(win, &ConfigureWindowAux::new().x(wx).y(wy))?;

        conn.clear_area(false, win, 0, 0, ww, wh)?;

        // img の hot を peak hot 位置に合わせる（= pointer と一致）
        let ox = peak_xhot - img.xhot as i32;
        let oy = peak_yhot - img.yhot as i32;

        conn.put_image(
            ImageFormat::Z_PIXMAP,
            win,
            gc,
            img.width as u16,
            img.height as u16,
            ox as i16,
            oy as i16,
            0,
            res.depth,
            &frame_buf,
        )?;
        conn.flush()?;
        thread::sleep(frame_interval);
    }

    Ok(())
}

fn peak_scale_of(frames: &[CursorImage]) -> f64 {
    // frames[last] が peak（caller が昇順で渡す前提）
    let base = frames.first().unwrap();
    let peak = frames.last().unwrap();
    peak.width as f64 / base.width as f64
}

/// 目標 scale に最も近い事前計算フレームを選ぶ
fn pick_frame(frames: &[CursorImage], target_scale: f64) -> &CursorImage {
    let base_w = frames[0].width as f64;
    frames
        .iter()
        .min_by(|a, b| {
            let sa = (a.width as f64 / base_w - target_scale).abs();
            let sb = (b.width as f64 / base_w - target_scale).abs();
            sa.partial_cmp(&sb).unwrap_or(std::cmp::Ordering::Equal)
        })
        .expect("scaled_frames must not be empty")
}

// ---------- Main ----------

#[derive(Clone, Copy)]
struct Sample {
    t: Instant,
    x: f64,
    y: f64,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cfg = load_config();
    eprintln!("[info] shake={:?}", cfg.shake);
    eprintln!("[info] cursor={:?}", cfg.cursor);

    // カーソル画像と事前スケール配列を用意
    let base = load_cursor(&cfg.cursor.theme, &cfg.cursor.shape, cfg.cursor.base_size)?;
    eprintln!("[info] loaded cursor {}x{}", base.width, base.height);
    let peak = cfg.cursor.peak_scale.max(1.1);
    // 11段階くらいスケールを用意
    // 各フレーム ~240x240 ARGB = 230KB * 30 = 7MB 程度
    let mut scaled_frames: Vec<CursorImage> = (0..=SCALE_STEPS)
        .map(|i| {
            let factor = 1.0 + (peak - 1.0) * (i as f64 / SCALE_STEPS as f64);
            scale_bilinear(&base, factor)
        })
        .collect();
    // `first()` が base、`last()` が peak になるよう幅の昇順にそろえる
    // （`peak_scale_of` と `pick_frame` がこの順序前提）
    scaled_frames.sort_by(|a, b| a.width.cmp(&b.width));
    eprintln!(
        "[info] scaled frames: {}..{} px",
        scaled_frames.first().unwrap().width,
        scaled_frames.last().unwrap().width
    );

    let (conn, screen_num) = x11rb::connect(None)?;
    let root = conn.setup().roots[screen_num].root;

    // Shape 拡張利用可能か
    let _ = conn.extension_information(shape::X11_EXTENSION_NAME)?;

    // XFixes は HideCursor/ShowCursor 前に version 確認が必要
    let xfixes_ver = conn.xfixes_query_version(5, 0)?.reply()?;
    eprintln!(
        "[info] XFixes {}.{}",
        xfixes_ver.major_version, xfixes_ver.minor_version
    );

    // ARGB32 visual 準備
    let overlay_res = find_argb_visual(&conn, screen_num)?;

    // XInput2 を有効化
    let ver = conn.xinput_xi_query_version(2, 2)?.reply()?;
    eprintln!("[info] XInput {}.{}", ver.major_version, ver.minor_version);

    let event_mask = xinput::EventMask {
        deviceid: xinput::Device::ALL_MASTER.into(),
        mask: vec![xinput::XIEventMask::RAW_MOTION],
    };
    conn.xinput_xi_select_events(root, &[event_mask])?;
    conn.flush()?;

    let window_dur = Duration::from_millis(cfg.shake.window_ms);
    let cooldown = Duration::from_millis(cfg.shake.cooldown_ms);
    let mut samples: VecDeque<Sample> = VecDeque::with_capacity(64);
    let mut last_fired = Instant::now()
        .checked_sub(cooldown)
        .unwrap_or_else(Instant::now);

    eprintln!("[info] listening for raw motion events");

    loop {
        let event = conn.wait_for_event()?;
        if !matches!(event, Event::XinputRawMotion(_)) {
            continue;
        }
        let reply = conn.query_pointer(root)?.reply()?;
        let now = Instant::now();
        samples.push_back(Sample {
            t: now,
            x: f64::from(reply.root_x),
            y: f64::from(reply.root_y),
        });
        while let Some(front) = samples.front() {
            if now.duration_since(front.t) > window_dur {
                samples.pop_front();
            } else {
                break;
            }
        }

        if now.duration_since(last_fired) < cooldown || samples.len() < MIN_SAMPLES {
            continue;
        }

        // path / displacement / speed
        let mut path = 0.0f64;
        let mut prev = *samples.front().unwrap();
        for s in samples.iter().skip(1) {
            let dx = s.x - prev.x;
            let dy = s.y - prev.y;
            path += (dx * dx + dy * dy).sqrt();
            prev = *s;
        }
        let first = samples.front().unwrap();
        let last = samples.back().unwrap();
        let dx = last.x - first.x;
        let dy = last.y - first.y;
        let disp = (dx * dx + dy * dy).sqrt().max(1.0);
        let ratio = path / disp;
        let elapsed = now.duration_since(first.t).as_secs_f64().max(0.001);
        let avg_speed = path / elapsed;

        if path >= cfg.shake.min_path_px
            && avg_speed >= cfg.shake.min_avg_speed
            && ratio >= cfg.shake.ratio_threshold
        {
            eprintln!(
                "[fire] path={path:.0}px disp={disp:.0}px ratio={ratio:.2} speed={avg_speed:.0}px/s"
            );
            if let Err(e) = show_overlay(
                &conn,
                screen_num,
                &overlay_res,
                &scaled_frames,
                cfg.cursor.duration_ms,
            ) {
                eprintln!("[error] overlay failed: {e}");
            }
            last_fired = Instant::now();
            samples.clear();
        }
    }
}
