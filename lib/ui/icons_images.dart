import 'package:flutter/material.dart';

import 'package:nemesis_helper/model/json_data.dart';

class UiImage extends StatelessWidget {
  const UiImage({
    super.key,
    required this.jsonImage,
    required this.widthLogical,
  });

  final JsonImage jsonImage;

  /// Requested width of this image in logical pixels
  final int? widthLogical;

  TextStyle _errorStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.error);

  Image _scaledImage(BuildContext context, ImageProvider provider) {
    // Determine image size based on actual screen size
    final screenSize = MediaQuery.sizeOf(context);

    return Image(
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      image: ResizeImage(
        provider,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
        width: (widthLogical ?? screenSize.width).round(),
        height: screenSize.height.round(),
      ),
      errorBuilder: (context, err, _) {
        return Text("Error loading ${this.jsonImage.path}: $err",
            style: _errorStyle(context));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = jsonImage.provider;
    return (provider != null)
        ? _scaledImage(context, provider)
        : FutureBuilder(
            future: jsonImage.providerFuture,
            builder: (context, snapshot) {
              final provider = snapshot.data;
              if (provider == null) {
                if (snapshot.hasError) {
                  return Text(
                      "Error loading ${this.jsonImage.path} provider: ${snapshot.error}",
                      style: _errorStyle(context));
                }
                return const SizedBox.shrink();
              }

              return _scaledImage(context, provider);
            },
          );
  }
}

class UiIcon extends StatelessWidget {
  const UiIcon({
    super.key,
    required this.jsonIcon,
    this.height,
  });

  final double? height;
  final JsonIcon jsonIcon;

  TextStyle _errorStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.error);

  @override
  Widget build(BuildContext context) {
    return Image(
      image: jsonIcon.provider,
      filterQuality: FilterQuality.medium,
      height: this.height,
      errorBuilder: (context, err, _) {
        return Text("Error loading ${this.jsonIcon.path}: $err",
            style: _errorStyle(context));
      },
    );
  }
}
