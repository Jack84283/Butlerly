import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9);

  test('AI suggestions remain proposed until explicitly accepted', () {
    final suggestion = Suggestion(
      id: SuggestionId('suggestion-1'),
      transactionId: TransactionId('transaction-1'),
      target: SuggestionTarget.category,
      proposedValue: 'Dining',
      method: SuggestionMethod.externalAi,
      provenance: aiProvenance(now),
      createdAt: now,
      confidence: 0.84,
      rationale: 'Merchant pattern',
      provider: 'example-provider',
      model: 'example-model',
    );

    expect(suggestion.status, SuggestionStatus.proposed);

    final accepted = suggestion.accept(now.add(const Duration(minutes: 1)));
    expect(accepted.status, SuggestionStatus.accepted);
    expect(suggestion.status, SuggestionStatus.proposed);
  });

  test('a rejected suggestion cannot later be accepted', () {
    final suggestion = Suggestion(
      id: SuggestionId('suggestion-1'),
      transactionId: TransactionId('transaction-1'),
      target: SuggestionTarget.merchant,
      proposedValue: 'Example Merchant',
      method: SuggestionMethod.localAi,
      provenance: aiProvenance(now),
      createdAt: now,
    ).reject(now);

    expect(
      () => suggestion.accept(now),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('machine-derived provenance preserves original representation', () {
    expect(
      () => Provenance(
        id: ProvenanceId('provenance-1'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('evidence and extraction remain separate immutable records', () {
    final evidence = EvidenceItem(
      id: EvidenceId('evidence-1'),
      type: EvidenceType.receiptImage,
      originalName: 'receipt.jpg',
      mediaType: 'image/jpeg',
      provenance: Provenance(
        id: ProvenanceId('provenance-evidence'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        originalRepresentation: 'receipt.jpg',
        sourceLanguage: 'ja',
      ),
      createdAt: now,
      sourceLanguage: 'ja',
    );
    final values = {'merchant': 'Coffee Shop'};
    final extraction = Extraction(
      id: ExtractionId('extraction-1'),
      evidenceId: evidence.id,
      values: values,
      provenance: Provenance(
        id: ProvenanceId('provenance-extraction'),
        sourceType: ProvenanceSourceType.evidenceExtraction,
        capturedAt: now,
        originalRepresentation: 'Coffee Shop',
        sourceLanguage: 'ja',
      ),
      createdAt: now,
    );
    values['merchant'] = 'Changed';

    expect(evidence.sourceLanguage, 'ja');
    expect(extraction.values['merchant'], 'Coffee Shop');
    expect(() => extraction.values['amount'] = '5', throwsUnsupportedError);
  });
}

Provenance aiProvenance(DateTime now) => Provenance(
  id: ProvenanceId('ai-provenance'),
  sourceType: ProvenanceSourceType.externalAi,
  capturedAt: now,
  originalRepresentation: '{"category":"Dining"}',
);
