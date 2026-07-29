//go:build darwin

package main

// AppleSMC readout via IOKit — the same interface Stats/Sensei use. Fans come
// from FNum/F<n>Ac; temperatures from enumerating every key starting with 'T'
// that decodes to a plausible Celsius value. Works on Apple Silicon ("flt "
// little-endian floats) and Intel ("sp78"/"fpe2" fixed point).

/*
#cgo LDFLAGS: -framework IOKit
#include <IOKit/IOKitLib.h>

typedef struct { char major; char minor; char build; char reserved[1]; unsigned short release; } SMCKeyData_vers_t;
typedef struct { unsigned short version; unsigned short length; unsigned int cpuPLimit; unsigned int gpuPLimit; unsigned int memPLimit; } SMCKeyData_pLimitData_t;
typedef struct { unsigned int dataSize; unsigned int dataType; char dataAttributes; } SMCKeyData_keyInfo_t;
typedef struct {
  unsigned int key;
  SMCKeyData_vers_t vers;
  SMCKeyData_pLimitData_t pLimitData;
  SMCKeyData_keyInfo_t keyInfo;
  char result; char status; char data8;
  unsigned int data32;
  unsigned char bytes[32];
} SMCKeyData_t;

static io_connect_t smcOpen(void) {
  io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
  if (!service) return 0;
  io_connect_t conn = 0;
  kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &conn);
  IOObjectRelease(service);
  if (result != KERN_SUCCESS) return 0;
  return conn;
}

static kern_return_t smcCall(io_connect_t conn, SMCKeyData_t *in, SMCKeyData_t *out) {
  size_t outSize = sizeof(SMCKeyData_t);
  return IOConnectCallStructMethod(conn, 2, in, sizeof(SMCKeyData_t), out, &outSize);
}

static void smcClose(io_connect_t conn) { IOServiceClose(conn); }
*/
import "C"

import (
	"encoding/binary"
	"fmt"
	"math"
	"unsafe"
)

const (
	smcCmdReadKey      = 5
	smcCmdKeyFromIndex = 8
	smcCmdKeyInfo      = 9
)

func collectSensors() Sensors {
	sensors := emptySensors()
	conn := C.smcOpen()
	if conn == 0 {
		return sensors
	}
	defer C.smcClose(conn)

	if fanCount, ok := smcReadValue(conn, "FNum"); ok {
		for index := 0; index < int(fanCount) && index < 10; index++ {
			if rpm, ok := smcReadValue(conn, fmt.Sprintf("F%dAc", index)); ok && rpm > 0 {
				sensors.Fans = append(sensors.Fans, FanReading{
					Label: fmt.Sprintf("Fan %d", index+1), RPM: math.Round(rpm),
				})
			}
		}
	}

	if total, ok := smcReadValue(conn, "#KEY"); ok {
		for index := uint32(0); index < uint32(total); index++ {
			key, ok := smcKeyAtIndex(conn, index)
			if !ok || key>>24 != 'T' {
				continue
			}
			value, ok := smcReadValue(conn, smcKeyString(key))
			if !ok || value < 1 || value > 120 {
				continue
			}
			sensors.Temps = append(sensors.Temps, TempReading{
				Label: smcKeyString(key), Celsius: value,
			})
		}
	}

	sortSensors(&sensors)
	sensors.Available = len(sensors.Temps) > 0 || len(sensors.Fans) > 0
	return sensors
}

func smcKeyCode(name string) uint32 {
	var code uint32
	for _, character := range []byte(name) {
		code = code<<8 | uint32(character)
	}
	return code
}

func smcKeyString(code uint32) string {
	return string([]byte{
		byte(code >> 24), byte(code >> 16), byte(code >> 8), byte(code),
	})
}

func smcKeyAtIndex(conn C.io_connect_t, index uint32) (uint32, bool) {
	var input, output C.SMCKeyData_t
	input.data8 = smcCmdKeyFromIndex
	input.data32 = C.uint(index)
	if C.smcCall(conn, &input, &output) != C.KERN_SUCCESS {
		return 0, false
	}
	return uint32(output.key), true
}

func smcReadValue(conn C.io_connect_t, name string) (float64, bool) {
	key := smcKeyCode(name)

	var infoIn, infoOut C.SMCKeyData_t
	infoIn.key = C.uint(key)
	infoIn.data8 = smcCmdKeyInfo
	if C.smcCall(conn, &infoIn, &infoOut) != C.KERN_SUCCESS || infoOut.result != 0 {
		return 0, false
	}
	dataSize := uint32(infoOut.keyInfo.dataSize)
	dataType := uint32(infoOut.keyInfo.dataType)
	if dataSize == 0 || dataSize > 32 {
		return 0, false
	}

	var readIn, readOut C.SMCKeyData_t
	readIn.key = C.uint(key)
	readIn.data8 = smcCmdReadKey
	readIn.keyInfo.dataSize = C.uint(dataSize)
	if C.smcCall(conn, &readIn, &readOut) != C.KERN_SUCCESS || readOut.result != 0 {
		return 0, false
	}
	bytes := C.GoBytes(unsafe.Pointer(&readOut.bytes[0]), C.int(dataSize))
	return smcDecode(dataType, bytes)
}

func smcDecode(dataType uint32, bytes []byte) (float64, bool) {
	switch smcKeyString(dataType) {
	case "flt ":
		if len(bytes) < 4 {
			return 0, false
		}
		value := math.Float32frombits(binary.LittleEndian.Uint32(bytes[:4]))
		if math.IsNaN(float64(value)) || math.IsInf(float64(value), 0) {
			return 0, false
		}
		return float64(value), true
	case "sp78":
		if len(bytes) < 2 {
			return 0, false
		}
		return float64(int16(binary.BigEndian.Uint16(bytes[:2]))) / 256, true
	case "fpe2":
		if len(bytes) < 2 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint16(bytes[:2])) / 4, true
	case "ui8 ":
		return float64(bytes[0]), true
	case "ui16":
		if len(bytes) < 2 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint16(bytes[:2])), true
	case "ui32":
		if len(bytes) < 4 {
			return 0, false
		}
		return float64(binary.BigEndian.Uint32(bytes[:4])), true
	default:
		return 0, false
	}
}
