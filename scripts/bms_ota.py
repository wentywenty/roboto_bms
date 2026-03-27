#!/usr/bin/env python3
import sys
import os
import time
import serial
import struct
import subprocess

def modbus_crc16(data):
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF

class BmsOta:
    def __init__(self, port, bin_path):
        self.port = port
        self.bin_path = bin_path
        self.ser = None
        self.bin_data = None

    def log(self, msg, color="\033[0m"):
        print(f"{color}[BMS OTA] {msg}\033[0m")

    def send_frame(self, cmd, data):
        length = len(data)
        frame = struct.pack(">BBB H", 0x01, 0x45, cmd, length) + data
        crc = modbus_crc16(frame)
        frame += struct.pack("<H", crc)
        self.ser.write(frame)
        return frame

    def read_response(self, timeout=2.0):
        self.ser.timeout = timeout
        header = self.ser.read(5)
        if len(header) < 5: return None
        addr, func, cmd, length = struct.unpack(">BBB H", header)
        payload = self.ser.read(length)
        crc_bytes = self.ser.read(2)
        if len(payload) < length: return None
        return payload

    def run(self):
        if not os.path.exists(self.bin_path):
            self.log(f"错误: 找不到固件文件 {self.bin_path}", "\033[1;31m")
            return False

        with open(self.bin_path, "rb") as f:
            self.bin_data = f.read()
        
        self.log(f"开始升级固件: {self.bin_path} ({len(self.bin_data)} 字节)")

        try:
            self.ser = serial.Serial(self.port, 115200, timeout=1)
            
            self.log("步骤 1: 发送升级请求...")
            req_data = b'\x30' * 6
            self.send_frame(0x11, req_data)
            resp = self.read_response()
            if not resp or resp[0] != 0x00:
                self.log(f"请求被拒绝: 状态码 0x{resp[0] if resp else 'NULL':02X}", "\033[1;31m")
                return False

            self.log("步骤 2: 发送固件元数据...")
            meta_data = self.bin_data[:22]
            self.send_frame(0x12, meta_data)
            resp = self.read_response()
            if not resp or resp[0] not in [0x08, 0x06]:
                self.log("元数据校验失败", "\033[1;31m")
                return False
            
            packet_size_code = resp[1]
            chunk_size = {1:64, 2:128, 3:240, 4:512, 5:1024}.get(packet_size_code, 512)
            self.log(f"BMS 请求分包大小: {chunk_size} 字节")

            self.log("步骤 3: 正在传输数据块...")
            total_size = len(self.bin_data)
            offset = 0
            pkt_idx = 0
            
            while offset < total_size:
                chunk = self.bin_data[offset : offset + chunk_size]
                actual_len = len(chunk)
                header_info = self.bin_data[14:17] 
                header_info += self.bin_data[13:14]
                header_info += struct.pack(">H", pkt_idx)
                header_info += struct.pack(">H", actual_len)
                header_info += self.bin_data[20:22]
                
                self.send_frame(0x13, header_info + chunk)
                resp = self.read_response(timeout=3.0)
                if not resp or resp[0] != 0x02:
                    self.log(f"包 {pkt_idx} 写入失败, 重试中...", "\033[1;33m")
                    time.sleep(0.5)
                    continue
                
                offset += actual_len
                pkt_idx += 1
                progress = (offset / total_size) * 100
                sys.stdout.write(f"\r进度: [{pkt_idx}] {progress:.1f}%")
                sys.stdout.flush()

            sys.stdout.write("\n")
            self.log("升级完成！等待 BMS 复位...", "\033[1;32m")
            time.sleep(5)
            return True

        finally:
            if self.ser: self.ser.close()

if __name__ == "__main__":
    port_arg = sys.argv[1] if len(sys.argv) > 1 else "/etc/default/bms_daemon"
    if os.path.exists(port_arg):
        with open(port_arg, "r") as f:
            for line in f:
                if "BMS_PORT=" in line:
                    port_arg = line.split("=")[1].strip()
                    break
    
    bin_file = sys.argv[2] if len(sys.argv) > 2 else "/opt/roboparty/lib/firmware/firmware.bin"
    ota = BmsOta(port_arg, bin_file)
    ota.run()
