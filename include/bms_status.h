#ifndef BMS_STATUS_H
#define BMS_STATUS_H

#include <cstdint>

namespace bms {

#pragma pack(push, 1) 
struct BatteryStatus {
    double voltage;
    double current;
    double temperature;
    double percentage;
    double charge;      
    double capacity;    
    double design_capacity;
    uint32_t protect_status;
    uint16_t work_state;
    double max_cell_voltage;
    double min_cell_voltage;
    char serial_number[33];
    uint16_t sw_version;
    uint16_t hw_version;
    uint16_t soh;
    uint32_t cycles;
};
#pragma pack(pop)

} // namespace bms

#endif
