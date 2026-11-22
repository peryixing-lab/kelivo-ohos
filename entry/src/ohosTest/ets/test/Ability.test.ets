import { describe, it, expect } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import { readFlutterZip } from '../../../main/ets/core/FlutterBackup';
import { forgetKey, newId, readKey, storeKey } from '../../../main/ets/core/Storage';

import { fromProviderLink, toProviderLink } from '../../../main/ets/core/ProviderLink';
import { preset } from '../../../main/ets/core/Models';

const storedZip = 'UEsDBBQAAAAAALR8dF0YZ2vzLgAAAC4AAAAKAAAAY2hhdHMuanNvbnsidmVyc2lvbiI6MSwiY29udmVyc2F0aW9ucyI6W10sIm1lc3NhZ2VzIjpbXX1QSwECFAMUAAAAAAC0fHRdGGdr8y4AAAAuAAAACgAAAAAAAAAAAAAAgAEAAAAAY2hhdHMuanNvblBLBQYAAAAAAQABADgAAABWAAAAAAA=';
const deflatedZip = 'UEsDBBQAAAAIALR8dF0YZ2vzKQAAAC4AAAAKAAAAY2hhdHMuanNvbqtWKkstKs7Mz1OyMtRRSs7PA3ETS4ACxUpW0bE6SrmpxcWJ6algXi0AUEsBAhQDFAAAAAgAtHx0XRhna/MpAAAALgAAAAoAAAAAAAAAAAAAAIABAAAAAGNoYXRzLmpzb25QSwUGAAAAAAEAAQA4AAAAUQAAAAAA';
const json = '{"version":1,"conversations":[],"messages":[]}';

export default function abilityTest() {
  describe('KelivoHarmonyServices', () => {
    it('StoredAndDeflatedFlutterBackup', 0, async () => {
      const codec = new util.Base64Helper();
      expect(await readFlutterZip(codec.decodeSync(storedZip))).assertEqual(json);
      expect(await readFlutterZip(codec.decodeSync(deflatedZip))).assertEqual(json);
    });
    it('KelivoProviderShareCode', 0, () => {
      const form = preset('saved', '本地模型', 'openai', 'https://example.org/v1', 'm');
      const imported = fromProviderLink(toProviderLink(form, 'test-only'), 'fresh');
      expect(imported.provider.id).assertEqual('fresh');
      expect(imported.provider.name).assertEqual('本地模型');
      expect(imported.provider.baseUrl).assertEqual(form.baseUrl);
      expect(imported.key).assertEqual('test-only');
    });
    it('AssetKeyRoundTrip', 0, async () => {
      const ref = newId();
      await storeKey(ref, 'native-test-key');
      try { expect(await readKey(ref)).assertEqual('native-test-key'); }
      finally { await forgetKey(ref); }
      expect(await readKey(ref)).assertEqual('');
    });
  });
}

