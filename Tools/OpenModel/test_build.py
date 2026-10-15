import unittest
from build import parse_affixes, expand_entry, build_words

class ExpansionTests(unittest.TestCase):
    def test_legacy_yo_affixes_require_independent_e_support(self):
        aff = parse_affixes('SFX J Y 2\nSFX J 0 а [^ейоь]\nSFX J ё я ё\n')
        words = build_words('3\nжильё/J\nжилье\nжилья\n', aff, 'ru')
        self.assertNotIn('жильёа', words)
        self.assertIn('жильё', words)
        self.assertIn('жилья', words)

    def test_suffix_condition_strip_and_base(self):
        aff = parse_affixes('SET UTF-8\nSFX S Y 2\nSFX S y ies [^aeiou]y\nSFX S 0 s [^y]\n')
        self.assertEqual(expand_entry('city', 'S', aff), {'city', 'cities'})
        self.assertEqual(expand_entry('cat', 'S', aff), {'cat', 'cats'})
    def test_prefix_suffix_cross_product(self):
        aff = parse_affixes('SET UTF-8\nPFX U Y 1\nPFX U 0 un .\nSFX D Y 1\nSFX D 0 ed .\n')
        self.assertEqual(expand_entry('lock','UD',aff), {'lock','unlock','locked','unlocked'})
    def test_non_cross_affix(self):
        aff = parse_affixes('PFX U N 1\nPFX U 0 un .\nSFX D Y 1\nSFX D 0 ed .\n')
        self.assertNotIn('unlocked',expand_entry('lock','UD',aff))
    def test_only_compound_and_case_filter(self):
        aff = parse_affixes('ONLYINCOMPOUND c\n')
        self.assertEqual(build_words('4\nhello\nHello\nabc/c\nx\n',aff,'en'), ['hello'])
    def test_reject_unsupported_or_bad_count(self):
        for text in ['FLAG long', 'SFX A Y 2\nSFX A 0 s .', 'SFX A Y 1\nSFX A 0 s/B .']:
            with self.subTest(text=text), self.assertRaises(ValueError): parse_affixes(text)


class SourceArtifactTests(unittest.TestCase):
    def test_user_regressions_and_sorted_unique(self):
        import json
        from build import MODEL
        model = json.loads((MODEL/'open-v1.json').read_text())
        for lang, examples in {'en':['ground','connector','running'], 'ru':['тоже','переключилось','периодически','привет','дела','занимаешься']}.items():
            words = model['languages'][lang]
            self.assertEqual(words, sorted(set(words)))
            self.assertTrue(set(examples).issubset(words))
    def test_artifact_rejects_legacy_malformed_yo_forms(self):
        import json
        from build import MODEL
        words = set(json.loads((MODEL/'open-v1.json').read_text())['languages']['ru'])
        self.assertTrue({'жильёа','жильёом','ружьёе','сырьёу','смышлёен'}.isdisjoint(words))
        self.assertTrue({'жильё','жилья','ружьё','ружья','сырьё','смышлёный','зелёный'}.issubset(words))

    def test_all_pinned_inputs_and_license_copies(self):
        import json
        from build import ROOT, MODEL, sha
        for source in json.loads((MODEL/'provenance.json').read_text())['files']:
            self.assertEqual(sha((ROOT/source['path']).read_bytes()),source['sha256'])
        for source,copy in [('en/README_en_US.txt','SCOWL-en_US.txt'),('ru_RU/README_ru_RU.txt','Lebedev-ru_RU.txt')]:
            self.assertEqual((ROOT/'Corpora/Sources'/source).read_bytes(),(MODEL/'Licenses'/copy).read_bytes())

if __name__ == '__main__': unittest.main()
