import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'dataset.dart';
import 'dictionary.dart';
import 'dicom_tag.dart';
import 'element.dart';
import 'parser.dart';

class DicomImageError implements Exception {
  DicomImageError(this.message);
  final String message;
  @override
  String toString() => 'DicomImageError: $message';
}

class WindowLevel {
  const WindowLevel({required this.center, required this.width});
  final double center;
  final double width;

  WindowLevel copyWith({double? center, double? width}) => WindowLevel(
        center: center ?? this.center,
        width: width ?? this.width,
      );
}

class ValueRange {
  const ValueRange({required this.min, required this.max});
  final double min;
  final double max;
}

class ImageInfo {
  ImageInfo({
    required this.rows,
    required this.columns,
    required this.samplesPerPixel,
    required this.bitsAllocated,
    required this.bitsStored,
    required this.pixelRepresentationSigned,
    required this.planarConfiguration,
    required this.photometric,
    required this.numberOfFrames,
    required this.rescaleSlope,
    required this.rescaleIntercept,
  });

  int rows;
  int columns;
  final int samplesPerPixel;
  final int bitsAllocated;
  final int bitsStored;
  final bool pixelRepresentationSigned;
  final int planarConfiguration;
  final String photometric;
  final int numberOfFrames;
  final double rescaleSlope;
  final double rescaleIntercept;
}

/// Decoded pixel data with window/level rendering.
class DicomImage {
  DicomImage(this.info);

  final ImageInfo info;
  int frameCount = 0;
  WindowLevel defaultWindow = const WindowLevel(center: 128, width: 256);
  ValueRange valueRange = const ValueRange(min: 0, max: 255);
  bool isGrayscale = false;
  final List<Int32List> grayFrames = [];
  final List<Uint8List> renderedFrames = []; // RGBA bytes
  int storedMin = 0;
  int storedMax = 0;

  bool get isColor => info.samplesPerPixel >= 3;
  bool get supportsWindowing => isGrayscale;

  static Future<DicomImage> decode(DicomFile file) async {
    final ds = file.dataset;
    final pixelElement = file.get(Tag.pixelData);
    if (pixelElement == null) {
      throw DicomImageError('This DICOM object contains no image pixel data.');
    }

    final rows = ds.intValue(Tag.rows) ?? 0;
    final cols = ds.intValue(Tag.columns) ?? 0;
    if (rows <= 0 || cols <= 0) {
      throw DicomImageError('missing image dimensions');
    }

    final info = ImageInfo(
      rows: rows,
      columns: cols,
      samplesPerPixel: ds.intValue(Tag.samplesPerPixel) ?? 1,
      bitsAllocated: ds.intValue(Tag.bitsAllocated) ?? 16,
      bitsStored: ds.intValue(Tag.bitsStored) ??
          ds.intValue(Tag.bitsAllocated) ??
          16,
      pixelRepresentationSigned:
          (ds.intValue(Tag.pixelRepresentation) ?? 0) == 1,
      planarConfiguration: ds.intValue(Tag.planarConfiguration) ?? 0,
      photometric:
          (ds.string(Tag.photometricInterp) ?? 'MONOCHROME2').toUpperCase(),
      numberOfFrames: math.max(1, ds.intValue(Tag.numberOfFrames) ?? 1),
      rescaleSlope: ds.doubleValue(Tag.rescaleSlope) ?? 1,
      rescaleIntercept: ds.doubleValue(Tag.rescaleIntercept) ?? 0,
    );

    final image = DicomImage(info);
    if (pixelElement.isEncapsulated) {
      image._decodeEncapsulated(pixelElement, file.transferSyntax);
    } else {
      image._decodeNative(pixelElement, file);
    }
    return image;
  }

  void _decodeEncapsulated(DicomElement element, String transferSyntax) {
    if (!DicomDictionary.isNativelyDecodableJpeg(transferSyntax)) {
      throw DicomImageError(
        '${DicomDictionary.transferSyntaxName(transferSyntax)} compression is not supported.',
      );
    }
    final frames = <Uint8List>[];
    for (final fragment in element.fragments) {
      final decoded = img.decodeJpg(fragment);
      if (decoded == null) continue;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
      frames.add(Uint8List.fromList(rgba));
      info.columns = decoded.width;
      info.rows = decoded.height;
    }
    if (frames.isEmpty) {
      throw DicomImageError('compressed frames could not be decoded');
    }
    renderedFrames.addAll(frames);
    frameCount = frames.length;
    isGrayscale = false;
  }

  void _decodeNative(DicomElement element, DicomFile file) {
    final ds = file.dataset;
    final pixels = element.value;
    final dv = ByteData.sublistView(pixels);
    final little = element.littleEndian ? Endian.little : Endian.big;
    final pixelsPerFrame = info.rows * info.columns;

    if (isColor) {
      _decodeColorFrames(pixels);
      return;
    }

    final bytesPerSample = math.max(1, info.bitsAllocated ~/ 8);
    final bytesPerFrame = pixelsPerFrame * bytesPerSample;
    final mask = info.bitsStored >= 31 ? 0x7fffffff : ((1 << info.bitsStored) - 1);
    final signBit = 1 << (info.bitsStored - 1);

    final frames = <Int32List>[];
    var minV = 1 << 30;
    var maxV = -(1 << 30);

    for (var f = 0; f < info.numberOfFrames; f++) {
      final base = f * bytesPerFrame;
      if (base + bytesPerFrame > pixels.lengthInBytes) break;
      final frame = Int32List(pixelsPerFrame);
      for (var i = 0; i < pixelsPerFrame; i++) {
        var v = bytesPerSample == 1
            ? dv.getUint8(base + i)
            : dv.getUint16(base + i * 2, little);
        v &= mask;
        if (info.pixelRepresentationSigned && (v & signBit) != 0) {
          v -= (mask + 1);
        }
        frame[i] = v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      frames.add(frame);
    }

    if (frames.isEmpty) throw DicomImageError('empty pixel data');
    if (minV > maxV) {
      minV = 0;
      maxV = 0;
    }

    grayFrames.addAll(frames);
    frameCount = frames.length;
    storedMin = minV;
    storedMax = maxV;
    isGrayscale = true;
    defaultWindow = _defaultWindow(ds, info, minV, maxV);

    final lo = minV * info.rescaleSlope + info.rescaleIntercept;
    final hi = maxV * info.rescaleSlope + info.rescaleIntercept;
    valueRange = ValueRange(min: math.min(lo, hi), max: math.max(lo, hi));
  }

  void _decodeColorFrames(Uint8List pixels) {
    final pixelsPerFrame = info.rows * info.columns;
    final samples = info.samplesPerPixel;
    final bytesPerFrame = pixelsPerFrame * samples;

    for (var f = 0; f < info.numberOfFrames; f++) {
      final base = f * bytesPerFrame;
      if (base + bytesPerFrame > pixels.lengthInBytes) break;
      final out = Uint8List(pixelsPerFrame * 4);
      if (info.planarConfiguration == 0) {
        for (var i = 0; i < pixelsPerFrame; i++) {
          final s = base + i * samples;
          out[i * 4] = pixels[s];
          out[i * 4 + 1] = pixels[s + 1];
          out[i * 4 + 2] = pixels[s + 2];
          out[i * 4 + 3] = 255;
        }
      } else {
        final plane = pixelsPerFrame;
        for (var i = 0; i < pixelsPerFrame; i++) {
          out[i * 4] = pixels[base + i];
          out[i * 4 + 1] = pixels[base + plane + i];
          out[i * 4 + 2] = pixels[base + 2 * plane + i];
          out[i * 4 + 3] = 255;
        }
      }
      renderedFrames.add(out);
    }
    if (renderedFrames.isEmpty) {
      throw DicomImageError('empty color pixel data');
    }
    frameCount = renderedFrames.length;
    isGrayscale = false;
  }

  /// Returns RGBA bytes for [frame], or null if out of range.
  Uint8List? render(int frame, WindowLevel window) {
    if (frame < 0 || frame >= frameCount) return null;
    if (!isGrayscale) return renderedFrames[frame];
    return _renderGray(frame, window);
  }

  Uint8List _renderGray(int frame, WindowLevel window) {
    final pixels = grayFrames[frame];
    final lut = _buildLut(window);
    final out = Uint8List(pixels.length * 4);
    final base = storedMin;
    for (var i = 0; i < pixels.length; i++) {
      final idx = pixels[i] - base;
      final g = (idx >= 0 && idx < lut.length) ? lut[idx] : 0;
      final o = i * 4;
      out[o] = g;
      out[o + 1] = g;
      out[o + 2] = g;
      out[o + 3] = 255;
    }
    return out;
  }

  Uint8List _buildLut(WindowLevel window) {
    final n = storedMax - storedMin + 1;
    if (n <= 0) return Uint8List(0);
    final lut = Uint8List(n);
    final width = math.max(1.0, window.width);
    final center = window.center;
    final low = center - 0.5 - (width - 1) / 2;
    final high = center - 0.5 + (width - 1) / 2;
    final slope = info.rescaleSlope;
    final intercept = info.rescaleIntercept;
    final invert = info.photometric == 'MONOCHROME1';
    for (var i = 0; i < n; i++) {
      final stored = storedMin + i;
      final m = stored * slope + intercept;
      double y;
      if (m <= low) {
        y = 0;
      } else if (m > high) {
        y = 255;
      } else {
        y = ((m - (center - 0.5)) / (width - 1) + 0.5) * 255;
      }
      var b = y.round().clamp(0, 255);
      if (invert) b = 255 - b;
      lut[i] = b;
    }
    return lut;
  }

  static WindowLevel _defaultWindow(
    DicomDataset ds,
    ImageInfo info,
    int storedMin,
    int storedMax,
  ) {
    final c = ds.doubles(Tag.windowCenter);
    final w = ds.doubles(Tag.windowWidth);
    if (c.isNotEmpty && w.isNotEmpty && w[0] > 0) {
      return WindowLevel(center: c[0], width: w[0]);
    }
    final lo = storedMin * info.rescaleSlope + info.rescaleIntercept;
    final hi = storedMax * info.rescaleSlope + info.rescaleIntercept;
    return WindowLevel(
      center: (lo + hi) / 2,
      width: math.max(1.0, hi - lo),
    );
  }

  Future<ui.Image> toUiImage(int frame, WindowLevel window) async {
    final rgba = render(frame, window);
    if (rgba == null) {
      throw DicomImageError('frame out of range');
    }
    final completer = ui.ImmutableBuffer.fromUint8List(rgba);
    final buffer = await completer;
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: info.columns,
      height: info.rows,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
}
