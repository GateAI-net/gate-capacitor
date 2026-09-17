Pod::Spec.new do |s|
  s.name = 'GateAICapacitor'
  s.version = '1.0.0'
  s.summary = 'Gate/AI capacitor SDK'
  s.homepage = 'https://gate-ai.net'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'Gate/AI' => 'support@gate-ai.net' }
  s.source = { :git => 'https://github.com/GateAI-net/gate-capacitor.git', :tag => s.version.to_s }
  s.ios.deployment_target = '16.0'
  s.swift_version = '5.0'
  s.source_files = 'ios/**/*.{swift,h,m}'
  s.frameworks = 'Security', 'CryptoKit', 'DeviceCheck'
  s.dependency 'Capacitor', '>= 7.0', '< 9.0'
end
