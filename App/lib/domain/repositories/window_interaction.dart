/// Engine-scoped native window interaction; never contains file paths or input.
class HeaderDropRegion {
  const HeaderDropRegion(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
}

abstract interface class WindowInteractionPort {
  Stream<String> get headerDropHandles;
  Future<void> updateHeaderDropRegion(HeaderDropRegion? region);
}
