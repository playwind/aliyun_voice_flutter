import { FlutterAbility, FlutterEngine, Log } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

const TAG = "EntryAbility"

export default class EntryAbility extends FlutterAbility {
  // 重写pagePath方法，返回正确的页面路径
  pagePath(): string {
    return "pages/MainPage"
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    Log.i(TAG, 'configureFlutterEngine called')
    try {
      super.configureFlutterEngine(flutterEngine)
      Log.i(TAG, 'Registering plugins...')
      GeneratedPluginRegistrant.registerWith(flutterEngine)
      Log.i(TAG, 'Plugins registered successfully')
    } catch (e) {
      Log.e(TAG, `Failed to configure Flutter engine: ${e}`)
    }
  }
}
