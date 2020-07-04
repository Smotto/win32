// monitor.dart

// Shows retrieval of various information from the high-level monitor
// configuration API.

// Some examples of output:
//
// 1) two physical monitors connected in extended mode
// ```
// C:\src\win32> dart example\monitor.dart
// number of monitors: 2
// primary monitor handle: 132205
// number of physical monitors: 1
// physical monitor handle: 0
// physical monitor description: Generic PnP Monitor
// capabilities:
//  - Supports technology type functions
//  - Supports brightness functions
//  - Supports contrast functions
// brightness: minimum(0), current(75), maximum(100)
// ```
//
// 2) a single LCD monitor that does not support DDC
// ```
// C:\src\win32> dart example\monitor.dart
// number of monitors: 1
// primary monitor handle: 1312117
// number of physical monitors: 1
// physical monitor handle: 0
// physical monitor description: LCD 1366x768
// Monitor does not support DDC/CI.
// ```

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final monitors = <int>[];

int enumMonitorCallback(int hMonitor, int hDC, Pointer lpRect, int lParam) {
  monitors.add(hMonitor);
  return TRUE;
}

int findPrimaryMonitor(List<int> monitors) {
  final monitorInfo = MONITORINFO.allocate();

  for (var monitor in monitors) {
    final result = GetMonitorInfo(monitor, monitorInfo.addressOf);
    if (result == TRUE) {
      if (monitorInfo.dwFlags & MONITORINFOF_PRIMARY == MONITORINFOF_PRIMARY) {
        free(monitorInfo.addressOf);
        return monitor;
      }
    }
  }

  free(monitorInfo.addressOf);
  return 0;
}

bool testBitmask(int bitmask, int value) => bitmask & value == value;

void printMonitorCapabilities(int capabilitiesBitmask) {
  if (capabilitiesBitmask == MC_CAPS_NONE) {
    print(' - No capabilities supported');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_MONITOR_TECHNOLOGY_TYPE)) {
    print(' - Supports technology type functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_BRIGHTNESS)) {
    print(' - Supports brightness functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_CONTRAST)) {
    print(' - Supports contrast functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_COLOR_TEMPERATURE)) {
    print(' - Supports color temperature functions');
  }
}

void main() {
  var result = FALSE;

  result = EnumDisplayMonitors(
      NULL, // all displays
      nullptr, // no clipping region
      Pointer.fromFunction<MonitorEnumProc>(
          enumMonitorCallback, // dwData
          0),
      NULL);
  if (result == FALSE) {
    throw WindowsException(result);
  }

  print('number of monitors: ${monitors.length}');

  final primaryMonitorHandle = findPrimaryMonitor(monitors);
  print('primary monitor handle: $primaryMonitorHandle');

  final physicalMonitorCountPtr = allocate<Uint32>();
  result = GetNumberOfPhysicalMonitorsFromHMONITOR(
      primaryMonitorHandle, physicalMonitorCountPtr);
  if (result == FALSE) {
    throw WindowsException(result);
  }
  print('number of physical monitors: ${physicalMonitorCountPtr.value}');

  // We need to allocate space for a PHYSICAL_MONITOR struct for each physical
  // monitor. Each struct comprises a HANDLE and a 128-character UTF-16 array.
  // Since fixed-size arrays are difficult to allocate with Dart FFI at present,
  // and since we only need the first entry, we can manually allocate space of
  // the right size.
  final physicalMonitorArray = allocate<Uint8>(
      count: physicalMonitorCountPtr.value * (sizeOf<IntPtr>() + 256));

  result = GetPhysicalMonitorsFromHMONITOR(primaryMonitorHandle,
      physicalMonitorCountPtr.value, physicalMonitorArray);
  if (result == FALSE) {
    throw WindowsException(result);
  }

  // Retrieve the monitor handle for the first physical monitor in the returned
  // array.
  final physicalMonitorHandle = physicalMonitorArray.cast<IntPtr>().value;
  print('physical monitor handle: $physicalMonitorHandle');
  final physicalMonitorDescription = physicalMonitorArray
      .elementAt(sizeOf<IntPtr>())
      .cast<Utf16>()
      .unpackString(128);
  print('physical monitor description: $physicalMonitorDescription');

  final monitorCapabilitiesPtr = allocate<Uint32>();
  final monitorColorTemperaturesPtr = allocate<Uint32>();

  result = GetMonitorCapabilities(physicalMonitorHandle, monitorCapabilitiesPtr,
      monitorColorTemperaturesPtr);
  if (result == TRUE) {
    print('capabilities: ');
    printMonitorCapabilities(monitorCapabilitiesPtr.value);
  } else {
    print('Monitor does not support DDC/CI.');
  }

  final minimumBrightnessPtr = allocate<Uint32>();
  final currentBrightnessPtr = allocate<Uint32>();
  final maximumBrightnessPtr = allocate<Uint32>();
  result = GetMonitorBrightness(physicalMonitorHandle, minimumBrightnessPtr,
      currentBrightnessPtr, maximumBrightnessPtr);
  if (result == TRUE) {
    print('brightness: minimum(${minimumBrightnessPtr.value}), '
        'current(${currentBrightnessPtr.value}), '
        'maximum(${maximumBrightnessPtr.value})');
  }

  DestroyPhysicalMonitors(physicalMonitorCountPtr.value, physicalMonitorArray);

  // free all the heap-allocated variables
  free(physicalMonitorCountPtr);
  free(physicalMonitorArray);
  free(monitorCapabilitiesPtr);
  free(monitorColorTemperaturesPtr);
  free(minimumBrightnessPtr);
  free(currentBrightnessPtr);
  free(maximumBrightnessPtr);
}
