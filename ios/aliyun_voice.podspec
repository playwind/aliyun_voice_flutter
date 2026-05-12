Pod::Spec.new do |s|
  s.name             = 'aliyun_voice'
  s.version          = '0.0.1'
  s.summary          = 'Aliyun Voice SDK Flutter plugin - ASR + TTS'
  s.description      = <<-DESC
  Flutter plugin wrapping Aliyun NUI SDK for speech recognition (ASR) and text-to-speech (TTS).
                       DESC
  s.homepage         = 'https://github.com/p1aywind/aliyun_voice'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'p1aywind' => 'p1aywind@example.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'

  s.vendored_frameworks = 'nuisdk.framework'
  s.resource_bundles = {
    'AliyunVoice' => ['nuisdk.framework/Resources.bundle/**/*']
  }

  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'

  s.frameworks       = 'Foundation', 'AVFoundation', 'AudioToolbox'
  s.dependency        'Flutter'
end
