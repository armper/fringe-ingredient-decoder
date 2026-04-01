require "fileutils"
require "xcodeproj"

ROOT = File.expand_path(__dir__)
PROJECT_PATH = File.join(ROOT, "FringeIngredientDecoder.xcodeproj")

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"

app_target = project.new_target(:application, "FringeIngredientDecoder", :ios, "17.0")
test_target = project.new_target(:unit_test_bundle, "FringeIngredientDecoderTests", :ios, "17.0")
test_target.add_dependency(app_target)

project.build_configurations.each do |config|
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["DEVELOPMENT_TEAM"] = "8BDNZ32KQG"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
end

app_target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.pandasoft.fringeingredientdecoder"
  config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  config.build_settings["PRODUCT_MODULE_NAME"] = "FringeIngredientDecoder"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_KEY_CFBundleDisplayName"] = "Fringe Ingredient Decoder"
  config.build_settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_NSCameraUsageDescription"] = "Scan product barcodes to decode ingredients quickly."
  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  config.build_settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["MARKETING_VERSION"] = "1.0"
  config.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
  config.build_settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  config.build_settings["SUPPORTS_MACCATALYST"] = "NO"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks"
  config.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
  config.build_settings["ENABLE_PREVIEWS"] = "YES"
end

test_target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.pandasoft.fringeingredientdecoderTests"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  config.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"
  config.build_settings["TEST_TARGET_NAME"] = app_target.name
  config.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
  config.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/FringeIngredientDecoder.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FringeIngredientDecoder"
end

main_group = project.main_group
app_group = main_group.new_group("FringeIngredientDecoder", "FringeIngredientDecoder")
models_group = app_group.new_group("Models", "Models")
services_group = app_group.new_group("Services", "Services")
store_group = app_group.new_group("Store", "Store")
support_group = app_group.new_group("Support", "Support")
views_group = app_group.new_group("Views", "Views")
scanner_group = views_group.new_group("Scanner", "Scanner")
result_group = views_group.new_group("Result", "Result")
tests_group = main_group.new_group("FringeIngredientDecoderTests", "FringeIngredientDecoderTests")

app_files = [
  app_group.new_file("FringeIngredientDecoderApp.swift"),
  app_group.new_file("ContentView.swift"),
  models_group.new_file("IngredientModels.swift"),
  models_group.new_file("RecentAnalysisRecord.swift"),
  services_group.new_file("OpenFoodFactsService.swift"),
  services_group.new_file("IngredientAnalysisEngine.swift"),
  store_group.new_file("DecoderStore.swift"),
  support_group.new_file("AppTheme.swift"),
  scanner_group.new_file("BarcodeScannerView.swift"),
  result_group.new_file("ResultView.swift"),
  result_group.new_file("IngredientDetailView.swift")
]

asset_catalog = app_group.new_file("Assets.xcassets")

app_target.add_file_references(app_files)
app_target.resources_build_phase.add_file_reference(asset_catalog, true)

test_file = tests_group.new_file("IngredientAnalysisEngineTests.swift")
test_target.add_file_references([test_file])

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, "FringeIngredientDecoder", true)

project.save
