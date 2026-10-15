import hashlib,json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class OpenPackagingTests(unittest.TestCase):
 def test_stages_verified_data_with_licenses_and_rejects_tampering(self):
  with tempfile.TemporaryDirectory() as tmp:
   source=Path(tmp)/'source';dest=Path(tmp)/'dest';source.mkdir();(source/'Licenses').mkdir()
   files={}
   for name,text in [('en.words','hello\n'),('ru.words','привет\n'),('corrections.json','{}')]:
    data=text.encode();(source/name).write_bytes(data);files[name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
   (source/'manifest.json').write_text(json.dumps({'schemaVersion':1,'version':'open-2','files':files}))
   for name in ['SCOWL-en_US.txt','Lebedev-ru_RU.txt','Necaramba-GPL-3.0.txt']:(source/'Licenses'/name).write_text('test license')
   script=ROOT/'Tools/Packaging/stage-open-model.py'
   result=subprocess.run(['python3',str(script),str(source),str(dest)],capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((dest/'en.words').read_bytes(),b'hello\n')
   self.assertTrue((dest/'Licenses/SCOWL-en_US.txt').exists())
   (source/'en.words').write_text('tampered\n')
   result=subprocess.run(['python3',str(script),str(source),str(dest)],capture_output=True)
   self.assertNotEqual(result.returncode,0)
if __name__=='__main__':unittest.main()
