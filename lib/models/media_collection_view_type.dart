enum MediaCollectionViewType { list, horizontalPoster, verticalPoster }

extension MediaCollectionViewTypeX on MediaCollectionViewType {
  String get storageValue {
    switch (this) {
      case MediaCollectionViewType.list:
        return 'list';
      case MediaCollectionViewType.horizontalPoster:
        return 'horizontal_poster';
      case MediaCollectionViewType.verticalPoster:
        return 'vertical_poster';
    }
  }

  bool get isPosterWall => this != MediaCollectionViewType.list;

  static MediaCollectionViewType fromStorage(String raw) {
    switch (raw.trim()) {
      case 'horizontal_poster':
        return MediaCollectionViewType.horizontalPoster;
      case 'list':
        return MediaCollectionViewType.list;
      case 'vertical_poster':
      default:
        return MediaCollectionViewType.verticalPoster;
    }
  }
}
