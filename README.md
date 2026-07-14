# DICOM Viewer (Flutter)

A Flutter port of the dependency-free [dicom-web](../dicom-web) viewer: a
from-scratch DICOM parser, a pixel decoder with window/level, and an interactive
viewer for browsing imported series.

The original web app is unchanged — this project lives alongside it.

## Running

```bash
cd dicom-flutter
flutter pub get
flutter run -d macos   # or chrome / ios / android
```

## Features

- **Library** — import a folder of DICOM files. Files are recognised by content
  (any extension, or none). Each folder becomes one **series**; slices are
  sorted naturally by filename and stored under the app documents directory.
- **Viewer**
  - Slice slider (or frame scrubbing for multi-frame files)
  - Pinch / scroll-wheel zoom; drag for window/level or pan
  - Double-tap to reset the view
  - Corner overlays (patient, modality, dimensions, W/L, slice/frame)
- **Metadata inspector** — searchable list of every parsed data element

## Architecture (`lib/`)

| Path | Responsibility |
| --- | --- |
| `dicom/` | Part 10 parser + pixel decoder (port of `js/`) |
| `data/library_db.dart` | Persistent library (files on disk + JSON index) |
| `state/` | Library and viewer controllers |
| `ui/` | Library screen, viewer screen, widgets |

## Supported encodings

- Uncompressed: Explicit/Implicit VR, little- and big-endian; 8/16-bit signed
  and unsigned grayscale (MONOCHROME1/2) and RGB; multi-frame; rescale + W/L.
- Encapsulated: Baseline / Extended **JPEG** (via `package:image`).

## Limitations

- JPEG Lossless, JPEG 2000 and RLE are not decoded (metadata still available).
- Linear window/level only (no VOI LUT sequence support).
