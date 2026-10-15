import json
import pathlib
import tempfile
import unittest
from pack import pack

class PackingTests(unittest.TestCase):
    def test_reproducible_sorted_utf8(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            source = root/'input.json'
            source.write_text(json.dumps({'schemaVersion':1,'version':'open-1','languages':{'en':['ground','a'],'ru':['ёж','я','дела']}},ensure_ascii=False))
            report = pack(source,root)
            self.assertEqual((root/'en.words').read_bytes(),b'a\nground\n')
            self.assertEqual((root/'ru.words').read_text(),'дела\nя\nёж\n')
            self.assertEqual(report,pack(source,root))
            self.assertEqual(report['wordCounts'],{'en':2,'ru':3})

    def test_rejects_invalid_source_without_outputs(self):
        for words in [[],['a','a'],['A'],['a\nb'],['привет']]:
            with self.subTest(words=words), tempfile.TemporaryDirectory() as tmp:
                root = pathlib.Path(tmp); source=root/'input.json'
                source.write_text(json.dumps({'schemaVersion':1,'version':'open-1','languages':{'en':words,'ru':['я']}}))
                with self.assertRaises(ValueError): pack(source,root)
                self.assertFalse((root/'en.words').exists())

if __name__ == '__main__': unittest.main()
