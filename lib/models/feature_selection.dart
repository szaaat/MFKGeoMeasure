class FeatureSelection {
  final String layerId;
  final String featureId;

  FeatureSelection({
    required this.layerId,
    required this.featureId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureSelection &&
          runtimeType == other.runtimeType &&
          layerId == other.layerId &&
          featureId == other.featureId;

  @override
  int get hashCode => layerId.hashCode ^ featureId.hashCode;
}
