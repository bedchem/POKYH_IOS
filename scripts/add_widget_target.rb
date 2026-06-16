#!/usr/bin/env ruby
# Legt die Widget-Extension „POKYHWidgetExtension" an und verdrahtet App Group,
# geteilte Quellen, Entitlements und Extension-Embedding. Idempotent: bricht ab,
# wenn das Target bereits existiert.
require 'xcodeproj'

PROJECT   = 'POKYH.xcodeproj'
APP_NAME  = 'POKYH'
WIDGET    = 'POKYHWidgetExtension'
TEAM      = 'X4223DUK8A'
GROUP_ID  = 'group.dev.plattnericus.POKYH'
WIDGET_BUNDLE = 'dev.plattnericus.POKYH.POKYHWidget'

proj = Xcodeproj::Project.open(PROJECT)
app  = proj.targets.find { |t| t.name == APP_NAME } or abort "App-Target #{APP_NAME} nicht gefunden"

if proj.targets.any? { |t| t.name == WIDGET }
  abort "Target #{WIDGET} existiert bereits – nichts zu tun."
end

# ── 1. Extension-Target ───────────────────────────────────────────────────────
widget = proj.new_target(:app_extension, WIDGET, :ios, '26.0', proj.products_group, :swift)

# ── 2. Geteilte Quelle (Shared/SharedKit.swift) → App UND Widget ──────────────
shared_group = proj.main_group.find_subpath('Shared', true)
shared_group.set_source_tree('SOURCE_ROOT')
shared_ref = shared_group.files.find { |f| f.path&.end_with?('SharedKit.swift') } ||
             shared_group.new_file('Shared/SharedKit.swift')
app.add_file_references([shared_ref])
widget.add_file_references([shared_ref])

# ── 3. Widget-eigene Quellen ──────────────────────────────────────────────────
widget_group = proj.main_group.find_subpath('POKYHWidget', true)
widget_group.set_source_tree('SOURCE_ROOT')
%w[POKYHWidgetBundle.swift NextLessonWidget.swift LessonLiveActivity.swift].each do |fname|
  ref = widget_group.new_file("POKYHWidget/#{fname}")
  widget.add_file_references([ref])
end

# ── 4. Build-Settings des Widgets ─────────────────────────────────────────────
widget.build_configurations.each do |cfg|
  s = cfg.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']   = WIDGET_BUNDLE
  s['PRODUCT_NAME']                = '$(TARGET_NAME)'
  s['DEVELOPMENT_TEAM']            = TEAM
  s['CODE_SIGN_STYLE']             = 'Automatic'
  s['CODE_SIGN_ENTITLEMENTS']      = 'POKYHWidget/POKYHWidget.entitlements'
  s['INFOPLIST_FILE']              = 'POKYHWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE']     = 'NO'
  s['SWIFT_VERSION']               = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET']  = '26.0'
  s['TARGETED_DEVICE_FAMILY']      = '1,2'
  s['SKIP_INSTALL']                = 'YES'
  s['MARKETING_VERSION']           = '1.0'
  s['CURRENT_PROJECT_VERSION']     = '1'
  s['SWIFT_EMIT_LOC_STRINGS']      = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS']     = ['$(inherited)', '@executable_path/Frameworks',
                                      '@executable_path/../../Frameworks']
end

# ── 5. App Group-Entitlement für die App setzen ───────────────────────────────
app.build_configurations.each do |cfg|
  cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'POKYH.entitlements'
end

# ── 6. Extension in die App einbetten (PlugIns) ───────────────────────────────
app.add_dependency(widget)
embed = app.copy_files_build_phases.find { |ph| ph.name == 'Embed Foundation Extensions' }
embed ||= app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
unless embed.files_references.include?(widget.product_reference)
  bf = embed.add_file_reference(widget.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

proj.save
puts "OK: Target #{WIDGET} angelegt. Targets jetzt: #{proj.targets.map(&:name).join(', ')}"
