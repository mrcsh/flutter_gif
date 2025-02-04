/*
  author: Saytoonz
  email: saytoonz05@gmail.com
  time: 2022-04-18 09:54
*/

library flutter_gif;

import 'dart:io';
import 'dart:ui' as ui show Codec;
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// cache gif fetched image
class GifCache {
  final caches = <String, List<ImageInfo>>{};

  void clear() {
    caches.clear();
  }

  bool evict(final Object key) {
    final List<ImageInfo>? pendingImage = caches.remove(key);

    if (pendingImage != null) {
      return true;
    }

    return false;
  }
}

/// control gif
class FlutterGifController extends AnimationController {
  FlutterGifController({
    required super.vsync,
    super.value,
    super.reverseDuration,
    super.duration,
    final AnimationBehavior? animationBehavior,
  }) : super.unbounded(
          animationBehavior: animationBehavior ?? AnimationBehavior.normal,
        );

  @override
  void reset() {
    value = 0.0;
  }
}

class GifImage extends StatefulWidget {
  const GifImage({
    super.key,
    required this.image,
    required this.controller,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.onFetchCompleted,
    this.color,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
  });

  final VoidCallback? onFetchCompleted;
  final FlutterGifController controller;
  final ImageProvider image;
  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final bool gaplessPlayback;
  final String? semanticLabel;
  final bool excludeFromSemantics;

  @override
  State<StatefulWidget> createState() {
    return GifImageState();
  }

  static GifCache cache = GifCache();
}

class GifImageState extends State<GifImage> {
  List<ImageInfo>? _infos;
  int _curIndex = 0;
  bool _fetchComplete = false;

  ImageInfo? get _imageInfo {
    if (!_fetchComplete) {
      return null;
    }
    return _infos == null ? null : _infos?[_curIndex];
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.removeListener(_listener);
    widget.controller.dispose();
  }

  @override
  void didUpdateWidget(final GifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      fetchGif(widget.image).then((final imageInfors) {
        if (mounted) {
          setState(() {
            _infos = imageInfors;
            _fetchComplete = true;
            _curIndex = widget.controller.value.toInt();
            if (widget.onFetchCompleted != null) {
              widget.onFetchCompleted!();
            }
          });
        }
      });
    }

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_listener);
      widget.controller.addListener(_listener);
    }
  }

  void _listener() {
    if (_curIndex != widget.controller.value && _fetchComplete) {
      if (mounted) {
        setState(() {
          _curIndex = widget.controller.value.toInt();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_infos == null) {
      fetchGif(widget.image).then((final imageInfors) {
        if (mounted) {
          setState(() {
            _infos = imageInfors;
            _fetchComplete = true;
            _curIndex = widget.controller.value.toInt();
            if (widget.onFetchCompleted != null) {
              widget.onFetchCompleted!();
            }
          });
        }
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    final image = RawImage(
      image: _imageInfo?.image,
      width: widget.width,
      height: widget.height,
      scale: _imageInfo?.scale ?? 1.0,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      centerSlice: widget.centerSlice,
      matchTextDirection: widget.matchTextDirection,
    );

    if (widget.excludeFromSemantics) {
      return image;
    }

    return Semantics(
      container: widget.semanticLabel != null,
      image: true,
      label: widget.semanticLabel ?? '',
      child: image,
    );
  }
}

final HttpClient _sharedHttpClient = HttpClient()..autoUncompress = false;

HttpClient get _httpClient => switch (kDebugMode) {
      false => _sharedHttpClient,
      true => debugNetworkImageHttpClientProvider?.call() ?? _sharedHttpClient,
    };

Future<List<ImageInfo>> fetchGif(final ImageProvider provider) async {
  final Uint8List bytes;
  final String key = switch (provider) {
    final NetworkImage ni => ni.url,
    final AssetImage ai => ai.assetName,
    final MemoryImage mi => md5.convert(mi.bytes).toString(),
    _ => '',
  };

  final existing = GifImage.cache.caches[key];
  if (existing != null) {
    return existing;
  }

  if (provider is NetworkImage) {
    final Uri resolved = Uri.base.resolve(provider.url);
    final HttpClientRequest request = await _httpClient.getUrl(resolved);
    provider.headers?.forEach((final String name, final String value) {
      request.headers.add(name, value);
    });
    final HttpClientResponse response = await request.close();
    bytes = await consolidateHttpClientResponseBytes(
      response,
    );
  } else if (provider is AssetImage) {
    final AssetBundleImageKey key = await provider.obtainKey(const ImageConfiguration());
    bytes = (await key.bundle.load(key.name)).buffer.asUint8List();
  } else if (provider is FileImage) {
    bytes = await provider.file.readAsBytes();
  } else if (provider is MemoryImage) {
    bytes = provider.bytes;
  } else {
    throw Exception("Unsupported image provider");
  }

  final buffer = await ImmutableBuffer.fromUint8List(bytes);
  final ui.Codec codec =
      await PaintingBinding.instance.instantiateImageCodecWithSize(buffer);
  final infos = <ImageInfo>[];
  for (int i = 0; i < codec.frameCount; i++) {
    final frameInfo = await codec.getNextFrame();
    final duration = frameInfo.duration.inSeconds;
    for (int sec = 1; sec <= duration; sec++) {
      infos.add(ImageInfo(image: frameInfo.image));
    }
  }
  return infos;
}
