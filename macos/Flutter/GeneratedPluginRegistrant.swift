//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import bluetooth_low_energy_darwin
import flutter_blue_plus_darwin
import package_info_plus
import shared_preferences_foundation
import universal_ble
import wakelock_plus

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  BluetoothLowEnergyDarwinPlugin.register(with: registry.registrar(forPlugin: "BluetoothLowEnergyDarwinPlugin"))
  FlutterBluePlusPlugin.register(with: registry.registrar(forPlugin: "FlutterBluePlusPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  UniversalBlePlugin.register(with: registry.registrar(forPlugin: "UniversalBlePlugin"))
  WakelockPlusMacosPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusMacosPlugin"))
}
