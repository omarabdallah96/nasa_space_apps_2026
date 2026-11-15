import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Credit line the Esri / OpenStreetMap terms require wherever [darkBaseMap] shows.
const baseMapCredit = '© Esri · OpenStreetMap';

const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas';

/// Dark street map (Esri Dark Gray Canvas), no API key needed: the base layer
/// plus a transparent place-name layer (labels in local script and English).
/// Spread into a map's children: `...darkBaseMap()`.
List<Widget> darkBaseMap() => [
      TileLayer(
        urlTemplate: '$_esri/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        maxNativeZoom: 16,
        userAgentPackageName: 'online.codingnow.firesight',
      ),
      TileLayer(
        urlTemplate: '$_esri/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
        maxNativeZoom: 16,
        userAgentPackageName: 'online.codingnow.firesight',
      ),
    ];
