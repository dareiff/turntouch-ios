platform :ios, "17.0"
use_frameworks!

# Ignore all warnings from all pods
inhibit_all_warnings!

target "Turn Touch iOS" do
    pod "CocoaAsyncSocket"
    pod 'AFNetworking', '~> 4.0'
    pod "SWXMLHash"
    pod "ReachabilitySwift"
    pod "NestSDK"
    
    # SwiftyHue
    pod "SwiftyHue"
    
    pod "iOSDFULibrary"
    pod "InAppSettingsKit"
end


post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '4.2'
            config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Owholemodule'
            config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf'
        end
    end
end
