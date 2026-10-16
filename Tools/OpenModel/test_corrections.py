import unittest
from corrections import yo_rules, validate_typos

class CorrectionTests(unittest.TestCase):
    def test_yo_unique_unknown_fold(self):
        self.assertEqual(yo_rules({'ёлка','ежик','ёжик','все','всё'}), [{'source':'елка','target':'ёлка'}])
    def test_multiple_yo_destinations_abstain(self):
        self.assertEqual(yo_rules({'сёсё','сесё'}), [])
    def test_real_word_and_unknown_target_rejected(self):
        for pair in [('form','from'),('teh','thee')]:
            with self.assertRaises(ValueError): validate_typos([pair], {'form','from','the'})
    def test_conflicting_sources_rejected(self):
        with self.assertRaises(ValueError): validate_typos([('teh','the'),('teh','ten')], {'the','ten'})
    def test_deterministic_sorting(self):
        self.assertEqual(validate_typos([('teh','the'),('adn','and')], {'the','and'}), [{'source':'adn','target':'and'},{'source':'teh','target':'the'}])

class ArtifactTests(unittest.TestCase):
    def test_real_artifact_is_safe_and_reproducible(self):
        import json
        from corrections import MODEL, AUTHORED_TYPOS, authored_yo_rules
        model = json.loads((MODEL/'open-v1.json').read_text())
        artifact = json.loads((MODEL/'corrections.json').read_text())
        words = set(model['languages']['en']) | set(model['languages']['ru'])
        pairs = [tuple(line.split()) for line in AUTHORED_TYPOS.splitlines() if line.strip()]
        self.assertEqual(artifact['typos'], validate_typos(pairs,words))
        self.assertEqual(artifact['yo'], authored_yo_rules(set(model['languages']['ru'])))
        self.assertGreaterEqual(len(artifact['typos']),100)
        self.assertIn('ру',artifact['protectedWords'])
        self.assertFalse({r['source'] for r in artifact['typos']} & {r['source'] for r in artifact['yo']})
        for rule in artifact['typos'] + artifact['yo']:
            if rule in artifact['typos']: self.assertNotIn(rule['source'],words)
            self.assertIn(rule['target'],words)
    def test_repeated_letter_hello_typo(self):
        import json
        from corrections import MODEL
        artifact = json.loads((MODEL/'corrections.json').read_text())
        self.assertIn({'source':'helllo','target':'hello'}, artifact['typos'])

    def test_explicit_known_source_yo_preferences(self):
        import json
        from corrections import MODEL
        artifact = json.loads((MODEL/'corrections.json').read_text())
        mapping = {r['source']:r['target'] for r in artifact['yo']}
        self.assertEqual(mapping['елка'],'ёлка')
        self.assertEqual(mapping['ежик'],'ёжик')
        self.assertEqual(mapping['береза'],'берёза')
        self.assertEqual(mapping['зеленый'],'зелёный')
        self.assertEqual(len(mapping),67)

    def test_contractions_are_authored_and_validated_against_dictionary(self):
        from corrections import validate_contractions
        self.assertEqual(validate_contractions(["I'm", "don't"], {"i'm", "don't", "can't"}), ["don't", "i'm"])
        for bad in [["dont"], ["go's"], ["'s"], ["don''t"]]:
            with self.assertRaises(ValueError): validate_contractions(bad, {"don't"})

    def test_schema_two_splits_layout_and_yo_protection(self):
        import json
        from corrections import MODEL
        rules = json.loads((MODEL/'corrections.json').read_text())
        self.assertEqual(rules['schemaVersion'], 2)
        self.assertEqual(rules['version'], 'open-3')
        self.assertEqual(rules['protectedWords'], ['ру'])
        self.assertTrue({'все','всё','осел','осёл','небо','нёбо','передохнем','передохнём'} <= set(rules['yoProtectedWords']))
        self.assertTrue({"don't", "can't", "i'm", "it's", "won't", "you're"} <= set(rules['contractions']))
        self.assertTrue(all(c == c.lower() and c.count("'") == 1 for c in rules['contractions']))
        manifest = json.loads((MODEL/'manifest.json').read_text())
        self.assertEqual(manifest['version'], 'open-3')

    def test_known_ambiguous_yo_preserved(self):
        import json
        from corrections import MODEL
        rules = json.loads((MODEL/'corrections.json').read_text())
        sources = {r['source'] for r in rules['yo']}
        self.assertTrue(sources.isdisjoint({'все','всё','небо','осел','передохнем'}))

if __name__ == '__main__': unittest.main()
