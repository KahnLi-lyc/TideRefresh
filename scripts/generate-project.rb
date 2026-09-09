require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'Examples/TideRefreshDemo.xcodeproj'))
project.root_object.attributes['LastUpgradeCheck'] = '1600'
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '..'
project.root_object.package_references << package

def attach_package(project, target, package)
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = package
  product.product_name = 'TideRefresh'
  target.package_product_dependencies << product
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

app = project.new_target(:application, 'TideRefreshDemo', :ios, '16.0')
tests = project.new_target(:unit_test_bundle, 'TideRefreshTests', :ios, '16.0')
tests.add_dependency(app)
[[app, 'TideRefreshDemo/**/*.swift'], [tests, '../Tests/TideRefreshTests/**/*.swift']].each do |target, pattern|
  attach_package(project, target, package)
  Dir.glob(File.join(root, 'Examples', pattern)).sort.each do |path|
    ref = project.main_group.new_file(Pathname.new(path).relative_path_from(Pathname.new(File.join(root, 'Examples'))).to_s)
    target.source_build_phase.add_file_reference(ref)
  end
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '6.0',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.kahnli.#{target.name}",
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'CODE_SIGNING_ALLOWED' => 'NO',
      'SUPPORTS_MACCATALYST' => 'NO',
      'IPHONEOS_DEPLOYMENT_TARGET' => '16.0'
    })
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown'
end
tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/TideRefreshDemo.app/TideRefreshDemo'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'TideRefreshDemo', true)
project.save
