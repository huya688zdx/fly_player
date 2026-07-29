class PosterBrowseEnrichmentCommitDecision {
  const PosterBrowseEnrichmentCommitDecision({
    required this.commitDisplay,
    required this.applyFocusEffects,
  });

  final bool commitDisplay;
  final bool applyFocusEffects;
}

class PosterBrowseEnrichmentCommitPolicy {
  const PosterBrowseEnrichmentCommitPolicy._();

  static PosterBrowseEnrichmentCommitDecision resolve({
    required int requestLoadGeneration,
    required int currentLoadGeneration,
    required int requestFocusGeneration,
    required int currentFocusGeneration,
  }) {
    final commitDisplay = requestLoadGeneration == currentLoadGeneration;
    return PosterBrowseEnrichmentCommitDecision(
      commitDisplay: commitDisplay,
      applyFocusEffects:
          commitDisplay && requestFocusGeneration == currentFocusGeneration,
    );
  }
}
