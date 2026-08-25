#!/usr/bin/env ruby
# Adds the PacketTunnel Network Extension target to Runner.xcodeproj WITHOUT
# touching the existing Flutter Runner target. Runs on the Codemagic macOS
# builder (no local Xcode). Idempotent: re-running skips work already done.
#
# What it wires:
#   * VpnChannel.swift  -> compiled into the Runner (app) target
#   * Runner entitlements (packet-tunnel-provider)
#   * A new app-extension target "PacketTunnel" (com.oscar.greenvpn.PacketTunnel)
#       - PacketTunnelProvider.swift
#       - its Info.plist + entitlements
#       - Tun2SocksKit Swift package (product "Tun2SocksKit")
#   * Embeds PacketTunnel.appex into Runner + a target dependency
require 'xcodeproj'

PROJECT   = 'Runner.xcodeproj'
APP_TGT   = 'Runner'
EXT_NAME  = 'PacketTunnel'
EXT_BID   = 'com.oscar.greenvpn.PacketTunnel'
TEAM      = 'FSJK3B954S'
PKG_URL   = 'https://github.com/EbrahimTahernejad/Tun2SocksKit'
PKG_PROD  = 'Tun2SocksKit'
PKG_MIN   = '5.16.0'
BUILD_NUM = ENV['PROJECT_BUILD_NUMBER'] || ENV['BUILD_NUMBER'] || '1'
MKT_VER   = '1.0.0'

project = Xcodeproj::Project.open(PROJECT)
runner  = project.targets.find { |t| t.name == APP_TGT }
raise "Runner target not found" unless runner

# ---- 1. App side: entitlements + VpnChannel.swift into Runner --------------
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

runner_group = project.main_group['Runner'] || project.main_group
unless runner.source_build_phase.files_references.any? { |r| r.path && r.path.end_with?('VpnChannel.swift') }
  ref = runner_group.new_reference('VpnChannel.swift')
  runner.add_file_references([ref])
  puts "added VpnChannel.swift to Runner"
end

# ---- 2. Create the PacketTunnel extension target (idempotent) --------------
ext = project.targets.find { |t| t.name == EXT_NAME }
if ext
  puts "PacketTunnel target already exists — refreshing settings"
else
  ext = project.new_target(:app_extension, EXT_NAME, :ios, '15.0', nil, :swift)
  puts "created PacketTunnel target"
end

ext.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BID
  bs['PRODUCT_NAME']              = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE']           = 'PacketTunnel/Info.plist'
  bs['CODE_SIGN_ENTITLEMENTS']   = 'PacketTunnel/PacketTunnel.entitlements'
  bs['SWIFT_VERSION']            = '5.0'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  bs['TARGETED_DEVICE_FAMILY']   = '1'
  bs['GENERATE_INFOPLIST_FILE']  = 'NO'
  bs['MARKETING_VERSION']        = MKT_VER
  bs['CURRENT_PROJECT_VERSION']  = BUILD_NUM
  bs['DEVELOPMENT_TEAM']         = TEAM
  bs['CODE_SIGN_STYLE']          = 'Manual'
  bs['SKIP_INSTALL']             = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS']  = ['$(inherited)', '@executable_path/Frameworks',
                                    '@executable_path/../../Frameworks']
end

# Source file for the extension
ext_group = project.main_group[EXT_NAME] || project.main_group.new_group(EXT_NAME, EXT_NAME)
unless ext.source_build_phase.files_references.any? { |r| r.path && r.path.end_with?('PacketTunnelProvider.swift') }
  pref = ext_group.new_reference('PacketTunnelProvider.swift')
  ext.add_file_references([pref])
  puts "added PacketTunnelProvider.swift to extension"
end

# ---- 3. Tun2SocksKit Swift package ----------------------------------------
project.root_object.package_references ||= []
pkg = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL.to_s.include?('Tun2SocksKit')
end
unless pkg
  pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg.repositoryURL = PKG_URL
  pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => PKG_MIN }
  project.root_object.package_references << pkg
  puts "added Tun2SocksKit package reference"
end

ext.package_product_dependencies ||= []
unless ext.package_product_dependencies.any? { |d| d.product_name == PKG_PROD }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = pkg
  dep.product_name = PKG_PROD
  ext.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  ext.frameworks_build_phase.files << bf
  puts "linked Tun2SocksKit into extension"
end

# ---- 4. Embed appex into Runner + dependency ------------------------------
runner.add_dependency(ext) unless runner.dependencies.any? { |d| d.target == ext }

embed = runner.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins }
unless embed
  embed = runner.new_copy_files_build_phase('Embed App Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(ext.product_reference)
  bf = embed.add_file_reference(ext.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }
  puts "embedded PacketTunnel.appex into Runner"
end

# ---- 5. Fix "Cycle inside Runner": Embed App Extensions must run BEFORE the
#         Flutter "Thin Binary" script phase, else xcodebuild reports a cycle.
phases = runner.build_phases
thin_idx = nil
phases.each_with_index { |p, i| thin_idx = i if p.respond_to?(:name) && p.name == 'Thin Binary' }
embed_idx = nil
phases.each_with_index { |p, i| embed_idx = i if p == embed }
if thin_idx && embed_idx && embed_idx > thin_idx
  phases.delete(embed)
  ti = nil
  phases.each_with_index { |p, i| ti = i if p.respond_to?(:name) && p.name == 'Thin Binary' }
  phases.insert(ti, embed)
  puts "moved Embed App Extensions before Thin Binary (cycle fix)"
end

project.save
puts "pbxproj patched OK (build #{BUILD_NUM})"
