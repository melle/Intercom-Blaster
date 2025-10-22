# Intercom Blaster

Intercom Blaster is a macOS status-bar companion that listens for HTTP triggers and immediately blasts live video right in your face.

![Intercom Blaster Logo](Intercom.png)

## But why?

I added a VoIP intercom with video support and wanted to peek at the feed without picking up the call. When the doorbell rings, my smart‑home controller (OpenHAB) fires a POST request at Intercom Blaster, which pops up a stream window so I can decide whether to answer the door or pretend I’m not home.

## The name...

Years ago on a German podcast (likely *Bits und so*), a Coding Monkeys developer mentioned an internal tool that could blast images to colleagues’ screens; they dubbed it “Retina Blaster.” I wanted the same “instant reveal” idea—just with video—so “Intercom Blaster” stuck.

## How?

The app exposes a minimal HTTP endpoint. POST an MPEG/H.264-compatible stream URL (including RTSP) and it opens a playback window instantly:

```
curl -X POST http://your.macOS.host:9900/play \
     -H "Content-Type: text/plain" \
     -d "rtsp://192.168.7.160/live/ch00_0"
```

If the body matches the configured regex, playback starts right away.

## Features

- Headless macOS SwiftUI app with status-item menu.
- Embedded TCP server (Network framework) parsing minimal HTTP POST `/play` requests.
- Regex-based URL validation with persistence in user defaults.
- RTSP and HTTP stream playback using VLCKit (`VLCMediaPlayer`).
- Settings panel for configuring port, regex, and observing last URL.
- Bonjour announcement as `_intercomblaster._tcp` for easy discovery.

## Building
```bash
swift build
```

To run tests:
```bash
swift test
```

To launch the app from the command line:
```bash
swift run IntercomBlaster
```

You can also open `IntercomBlaster.xcworkspace` in Xcode for an IDE experience.

## Dependencies
- Swift 6.2, macOS 14+
- `VLCKit.xcframework` (3.6.0) vendored in `Vendor/`

## License

Intercom Blaster is released under the MIT License (see [LICENSE](LICENSE)).

VLCKit retains its own licensing terms. Refer to `Vendor/VLCKit.xcframework/` for details.
