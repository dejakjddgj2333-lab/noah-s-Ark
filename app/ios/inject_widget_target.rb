#!/usr/bin/env ruby
# 注入 MingceWidget app-extension target 进 Runner.xcodeproj (幂等).
# 数据文件已在 ios/MingceWidget/, 此脚本只接工程引用 + build settings + embed phase.
require "xcodeproj"

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
PROJ = File.join(SCRIPT_DIR, "Runner.xcodeproj")
WIDGET_DIR = "MingceWidget"
WIDGET_NAME = "MingceWidget"
WIDGET_BUNDLE_ID = "com.hkmc.noahsark.MingceWidget"
TEAM = "C4Y8S5CHFT"
APP_GROUP = "group.com.hkmc.noahsark.shared"
SWIFT_FILES = %w[
  MingceWidgetBundle.swift
  SharedStore.swift
  MingcePriceWidget.swift
  MingceWhaleWidget.swift
  WatchLiveActivity.swift
]
RESOURCE_FILES = [] # 无额外资源; Info.plist/entitlements 走 build settings

project = Xcodeproj::Project.open(PROJ)
runner = project.targets.find { |t| t.name == "Runner" }
abort "Runner target not found" unless runner

# 幂等: 已存在则跳过创建, 仅确保 build settings
existing = project.targets.find { |t| t.name == WIDGET_NAME }

unless existing
  # --- 1. product file ref (.appex) ---
  appex_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  appex_ref.path = "#{WIDGET_NAME}.appex"
  appex_ref.name = "#{WIDGET_NAME}.appex"
  appex_ref.source_tree = "BUILT_PRODUCTS_DIR"
  appex_ref.explicit_file_type = "wrapper.app-extension"
  appex_ref.include_in_index = "0"
  project.products_group << appex_ref

  # --- 2. native target ---
  widget = project.new_target(:app_extension, WIDGET_NAME, :ios, "15.0")
  widget.product_reference.path = "#{WIDGET_NAME}.appex"
  # new_target 已把 product 加进 products group; 移除我们手建的重复 ref
  project.products_group.children.delete(appex_ref) if project.products_group.children.include?(appex_ref)

  # --- 3. source group + files ---
  group = project.main_group.find_subpath(WIDGET_DIR, true)
  group.set_source_tree("<group>")
  group.set_path(WIDGET_DIR)

  sources_phase = widget.source_build_phase
  SWIFT_FILES.each do |f|
    ref = group.new_file(f)
    sources_phase.add_file_reference(ref, true)
  end
  # Info.plist + entitlements 加进 group (不进任何 build phase, 仅工程可见)
  group.new_file("Info.plist")
  group.new_file("#{WIDGET_NAME}.entitlements")

  # --- 4. Runner: embed app extensions phase + dependency ---
  embed = runner.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins } ||
          runner.new_copy_files_build_phase("Embed Foundation Extensions") # placeholder name
  embed.name = "Embed App Extensions"
  embed.symbol_dst_subfolder_spec = :plug_ins
  embed.dst_path = ""
  unless embed.files_references.include?(widget.product_reference)
    bf = embed.add_file_reference(widget.product_reference, true)
    bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
  end

  dep = runner.add_dependency(widget)

  # 破 Xcode 15/16 新构建系统 "Cycle inside Runner": Embed 须在 Run Script/Thin Binary 之前
  embed_idx = runner.build_phases.index(embed)
  run_idx = runner.build_phases.index { |ph| ph.display_name == "Run Script" }
  if run_idx && embed_idx && embed_idx > run_idx
    runner.build_phases.delete(embed)
    runner.build_phases.insert(runner.build_phases.index { |ph| ph.display_name == "Run Script" }, embed)
  end

  project.save
  puts "created target #{WIDGET_NAME}"
end

# --- 5. build settings (每次跑都对齐) ---
widget = project.targets.find { |t| t.name == WIDGET_NAME }

# widget target 需 base xcconfig 才能解析 $(FLUTTER_BUILD_NAME/NUMBER),
# 否则 Info.plist 缺 CFBundleVersion → 模拟器报 "Invalid placeholder attributes".
# 用专用 Widget.xcconfig (只含 Generated.xcconfig), 不用 Release.xcconfig —
# 后者 #include Pods-Runner 的 FRAMEWORK_SEARCH_PATHS, 会让 widget 误链 WebRTC/Flutter.
widget_xcconfig = project.files.find { |f| f.path == "Flutter/Widget.xcconfig" }
unless widget_xcconfig
  fl = project.main_group.find_subpath("Flutter", true)
  widget_xcconfig = fl.new_reference("Widget.xcconfig")
end

widget.build_configurations.each do |c|
  c.base_configuration_reference = widget_xcconfig
  bs = c.build_settings
  bs["PRODUCT_BUNDLE_IDENTIFIER"] = WIDGET_BUNDLE_ID
  bs["PRODUCT_NAME"] = "$(TARGET_NAME)"
  bs["INFOPLIST_FILE"] = "#{WIDGET_DIR}/Info.plist"
  bs["CODE_SIGN_ENTITLEMENTS"] = "#{WIDGET_DIR}/#{WIDGET_NAME}.entitlements"
  bs["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  bs["SWIFT_VERSION"] = "5.0"
  bs["TARGETED_DEVICE_FAMILY"] = "1"
  bs["SKIP_INSTALL"] = "YES"
  bs["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks",
  ]
  bs["GENERATE_INFOPLIST_FILE"] = "NO"
  bs["CURRENT_PROJECT_VERSION"] = "$(FLUTTER_BUILD_NUMBER)"
  bs["MARKETING_VERSION"] = "$(FLUTTER_BUILD_NAME)"
  bs["CLANG_ENABLE_MODULES"] = "YES"
  bs["SWIFT_EMIT_LOC_STRINGS"] = "YES"
  bs["DEVELOPMENT_TEAM"] = TEAM
  case c.name
  when "Debug"
    bs["CODE_SIGN_STYLE"] = "Automatic"
    bs["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
  when "Release", "Profile"
    bs["CODE_SIGN_STYLE"] = "Manual"
    bs["CODE_SIGN_IDENTITY"] = "Apple Distribution"
    # PROVISIONING_PROFILE_SPECIFIER 由步骤3 (profile 建好后) 写入
  end
end

# Runner 保持不动 (主 profile 重建由步骤3处理).
project.save
puts "build settings aligned"
puts "OK"
