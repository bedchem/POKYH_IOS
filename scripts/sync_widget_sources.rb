#!/usr/bin/env ruby
# Stellt sicher, dass ALLE .swift-Dateien aus POKYHWidget/ im Widget-Target
# kompiliert werden. Idempotent: fügt nur fehlende hinzu.
require 'xcodeproj'

proj   = Xcodeproj::Project.open('POKYH.xcodeproj')
widget = proj.targets.find { |t| t.name == 'POKYHWidgetExtension' } or abort 'Widget-Target fehlt'
group  = proj.main_group.find_subpath('POKYHWidget', true)
group.set_source_tree('SOURCE_ROOT')

# bereits kompilierte Dateipfade des Targets
compiled = widget.source_build_phase.files.filter_map { |bf| bf.file_ref&.real_path&.to_s }

added = []
Dir.glob('POKYHWidget/*.swift').sort.each do |path|
  abs = File.expand_path(path)
  next if compiled.include?(abs)
  # vorhandene File-Reference wiederverwenden oder neu anlegen
  ref = group.files.find { |f| f.real_path.to_s == abs } || group.new_file(path)
  widget.add_file_references([ref])
  added << File.basename(path)
end

proj.save
puts added.empty? ? 'Nichts hinzuzufügen.' : "Hinzugefügt: #{added.join(', ')}"
puts "Widget-Quellen jetzt: #{widget.source_build_phase.files.filter_map { |bf| bf.file_ref&.path&.split('/')&.last }.sort.join(', ')}"
