import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import { AliyunVoicePlugin } from '../aliyun_voice/AliyunVoicePlugin';

const TAG = "GeneratedPluginRegistrant";

export class GeneratedPluginRegistrant {

  static registerWith(flutterEngine: FlutterEngine) {
    try {
      new AliyunVoicePlugin().registerWith(flutterEngine);
    } catch (e) {
      Log.e(TAG, "Tried to register plugins with FlutterEngine failed.");
      Log.e(TAG, "Received exception while registering", e);
    }
  }
}
