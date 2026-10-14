/// Explicit project estimate v1, based only on committed aggregate counts.
/// Undo has weight zero; this is not a measured productivity claim.
class EstimateTimeSaved {
  const EstimateTimeSaved();
  int seconds(Map<String, int> counts) =>
      (counts['layout'] ?? 0) +
      (counts['manual'] ?? 0) +
      2 *
          ((counts['typo'] ?? 0) +
              (counts['doubleCaps'] ?? 0) +
              (counts['yo'] ?? 0));
}
