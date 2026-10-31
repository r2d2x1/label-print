use ptouch_core::{PrintQuality, PtouchDevice, tape};
use serde_json::{Value, json};
use std::{
    ffi::{CString, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
    time::Duration,
};

fn response(f: impl FnOnce() -> Result<Value, String>) -> *mut c_char {
    let value = match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => json!({"ok": false, "message": error}),
        Err(_) => {
            json!({"ok": false, "message": "Printer backend failed unexpectedly. Reconnect the printer before retrying."})
        }
    };
    CString::new(value.to_string()).unwrap().into_raw()
}

fn connected<T>(f: impl FnOnce(&mut PtouchDevice) -> Result<T, String>) -> Result<T, String> {
    let mut device = PtouchDevice::open(0x04f9, 0x202d).map_err(|e| e.to_string())?;
    let result = (|| {
        device
            .set_job_timeout(Duration::from_secs(90))
            .map_err(|e| e.to_string())?;
        device.init().map_err(|e| e.to_string())?;
        f(&mut device)
    })();
    let closed = device.close().map_err(|e| e.to_string());
    match result {
        Ok(value) => {
            closed?;
            Ok(value)
        }
        Err(error) => Err(error),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn label_backend_status() -> *mut c_char {
    response(|| {
        connected(|device| {
            let status = device.status().ok_or("Printer returned no status")?;
            if status.has_error() {
                return Err(status.error_description());
            }
            Ok(
                json!({"ok": true, "message": "Ready", "tapeMM": status.media_width,
                  "printableDots": device.tape_width_px(), "model": "PT-2430PC"}),
            )
        })
    })
}

// Output one raster column per label x coordinate. Physical tape margins must
// stay white; reject ink outside the printable band rather than silently crop.
fn raster(
    pixels: &[u8],
    width: usize,
    height: usize,
    printable: usize,
    head: usize,
) -> Result<Vec<Vec<u8>>, String> {
    if width == 0
        || height == 0
        || head % 8 != 0
        || printable > height
        || printable > head
        || width.checked_mul(height) != Some(pixels.len())
    {
        return Err("Invalid bitmap dimensions".into());
    }
    let top = (height - printable) / 2;
    for y in 0..height {
        if (y < top || y >= top + printable)
            && pixels[y * width..(y + 1) * width].iter().any(|v| *v < 128)
        {
            return Err(
                "Artwork extends beyond the printable tape area. Move it inside the dashed guides."
                    .into(),
            );
        }
    }
    let offset = head / 2 - printable / 2;
    let mut lines = vec![vec![0; head / 8]; width];
    for (x, line) in lines.iter_mut().enumerate() {
        for i in 0..printable {
            if pixels[(top + printable - 1 - i) * width + x] < 128 {
                let pin = offset + i;
                line[head / 8 - 1 - pin / 8] |= 1 << (pin % 8);
            }
        }
    }
    Ok(lines)
}

// Keep intermediate copies in chain mode; request pre-cut to trim the initial
// leader and separate labels. Only the final copy needs a full feed/eject.
fn print_options(copy: u16, copies: u16, cut: bool) -> (bool, bool) {
    (!cut || copy + 1 < copies, cut)
}

/// # Safety
/// pixels must address count readable bytes and remain valid throughout call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn label_backend_print(
    pixels: *const u8,
    count: usize,
    width: u32,
    height: u32,
    tape_mm: u8,
    copies: u16,
    cut: u8,
) -> *mut c_char {
    response(|| {
        if pixels.is_null()
            || copies == 0
            || copies > 99
            || width < 180
            || width > 7100
            || height == 0
            || height > 171
            || count != width as usize * height as usize
        {
            return Err("Invalid print request".into());
        }
        let expected_height = (tape_mm as f64 * 180.0 / 25.4).round() as u32;
        if height != expected_height || ![6, 9, 12, 18, 24].contains(&tape_mm) {
            return Err("Unsupported tape or bitmap height".into());
        }
        let pixels = unsafe { std::slice::from_raw_parts(pixels, count) };
        connected(|device| {
            let status = device.status().ok_or("No printer status")?;
            if status.has_error() {
                return Err(status.error_description());
            }
            if status.media_width != tape_mm {
                return Err(format!(
                    "Loaded tape is {} mm; document requires {} mm",
                    status.media_width, tape_mm
                ));
            }
            let printable = tape::tape_pixels(tape_mm, 180)
                .ok_or("Unsupported tape")?
                .min(device.max_px());
            let lines = raster(
                pixels,
                width as usize,
                height as usize,
                printable as usize,
                device.max_px() as usize,
            )?;
            for copy in 0..copies {
                let (chain, precut) = print_options(copy, copies, cut != 0);
                // All leading/trailing design whitespace is already in the
                // bitmap. Reset firmware feed on EVERY page, including copies.
                device.print_raster_with_margin(&lines, chain, precut, PrintQuality::Standard, 0)
                    .map_err(|e| format!("Copy {}: {}. Some tape may already have printed; the job will not retry automatically.", copy + 1, e))?;
            }
            Ok(
                json!({"ok": true, "message": format!("Printed {} label(s)", copies),
                "rasterColumns": width, "rasterLengthMM": width as f64 * 25.4 / 180.0,
                "feedMarginDots": 0}),
            )
        })
    })
}

/// # Safety
/// message must be an unfreed pointer returned by this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn label_backend_free(message: *mut c_char) {
    if !message.is_null() {
        drop(unsafe { CString::from_raw(message) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_column_order_and_vertical_orientation() {
        let mut pixels = vec![255; 2 * 12];
        pixels[2 * 2] = 0; // first column, first printable row
        pixels[9 * 2 + 1] = 0; // second column, last printable row
        let lines = raster(&pixels, 2, 12, 8, 16).unwrap();
        assert_eq!(lines, vec![vec![8, 0], vec![0, 16]]);
    }
    #[test]
    fn centered_artwork_keeps_equal_feed_direction_margins() {
        for width in [180_usize, 283] {
            let mut pixels = vec![255; width * 85];
            let left = (width - 80) / 2;
            for y in 28..57 {
                for x in left..left + 80 {
                    pixels[y * width + x] = 0;
                }
            }
            let lines = raster(&pixels, width, 85, 76, 128).unwrap();
            let first = lines.iter().position(|line| line.iter().any(|b| *b != 0)).unwrap();
            let last = lines.iter().rposition(|line| line.iter().any(|b| *b != 0)).unwrap();
            assert_eq!(lines.len(), width);
            assert_eq!(first, left);
            assert_eq!(last, left + 79);
            assert!(first.abs_diff(width - 1 - last) <= 1);
        }
    }
    #[test]
    fn rejects_ink_in_unprintable_margin() {
        let mut pixels = vec![255; 12];
        pixels[0] = 0;
        assert!(
            raster(&pixels, 1, 12, 8, 16)
                .unwrap_err()
                .contains("printable")
        );
    }
    #[test]
    fn auto_cut_enables_pre_cut_and_only_ejects_the_last_copy() {
        assert_eq!(print_options(0, 1, true), (false, true));
        assert_eq!(print_options(0, 3, true), (true, true));
        assert_eq!(print_options(1, 3, true), (true, true));
        assert_eq!(print_options(2, 3, true), (false, true));
        assert_eq!(print_options(0, 1, false), (true, false));
        use ptouch_core::{DeviceFlags, device, protocol};
        let flags = device::find_device(0x04f9, 0x202d).unwrap().flags;
        assert!(flags.contains(DeviceFlags::HAS_PRECUT));
        let options = protocol::JobOptions {
            media_width: 12,
            chain_print: false,
            precut: true,
            ..Default::default()
        };
        let lines = vec![vec![1; 16]; 425];
        let job = protocol::build_print_job(&lines, flags, &options);
        assert_eq!(job[0], protocol::cmd_raster_start(flags));
        assert_eq!(job[1], vec![0x1b, 0x69, 0x4d, 0x40]);
        assert_eq!(
            job.iter()
                .filter(|bytes| bytes.first() == Some(&0x47))
                .count(),
            425
        );
        assert_eq!(job.last().unwrap(), &vec![0x1a]);
    }

    #[test]
    fn explicit_feed_margin_is_present_without_changing_raster_length() {
        use ptouch_core::{device, protocol};
        let flags = device::find_device(0x04f9, 0x202d).unwrap().flags;
        let options = protocol::JobOptions {
            media_width: 12,
            precut: true,
            ..Default::default()
        };
        let mut lines = vec![vec![0; 16]; 283];
        lines[14][8] = 1;
        lines[100][8] = 2;
        let job = protocol::build_print_job_with_margin(&lines, flags, &options, Some(0));
        assert!(
            job.contains(&protocol::cmd_page_flags(0)),
            "The bitmap already includes the label margins, but no explicit zero feed-margin command was emitted: {:?}",
            &job[..3]
        );
        let count = job
            .iter()
            .filter(|bytes| bytes.first() == Some(&0x47) || *bytes == &vec![0x5a])
            .count();
        assert_eq!(count, 283);
    }

    #[test]
    fn invalid_requests_do_not_touch_usb() {
        let ptr = unsafe { label_backend_print(std::ptr::null(), 0, 0, 0, 12, 1, 1) };
        let text = unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().unwrap();
        assert!(text.contains("Invalid print request"));
        unsafe {
            label_backend_free(ptr);
        }
    }
}
