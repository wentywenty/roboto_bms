#include <iostream>
#include <thread>
#include <chrono>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>
#include <signal.h>
#include <sys/stat.h>
#include <cstring>
#include "bms_status.h"
#include "bms_protocol.hpp"

#define SOCKET_PATH "/tmp/bms.sock"

/* Global flag for graceful shutdown */
bool g_running = true;
void signal_handler(int sig) { g_running = false; }

int main(int argc, char** argv) {
    /* Register signal handlers for clean exit */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* Get serial port from argument or use default */
    std::string port = (argc > 1) ? argv[1] : "/dev/ttyUSB0";
    tws_bms::BmsProtocol bms_proto(port, 115200);

    /* Keep trying to open the serial port (BMS Heartbeat start) */
    while (g_running && !bms_proto.open()) {
        std::cerr << "[BMS Daemon] Waiting for serial port " << port << "..." << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }

    /* Initialize Unix Domain Socket Server */
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        std::cerr << "[BMS Daemon] Failed to create socket" << std::endl;
        return 1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    
    /* Cleanup existing socket file */
    unlink(SOCKET_PATH);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "[BMS Daemon] Bind failed" << std::endl;
        return 1;
    }

    if (listen(server_fd, 5) < 0) {
        std::cerr << "[BMS Daemon] Listen failed" << std::endl;
        return 1;
    }

    /* Set socket permissions so ROS node can connect */
    chmod(SOCKET_PATH, 0666);

    std::cout << "[BMS Daemon] Started. Heartbeat Active on " << port << std::endl;

    bms::BatteryStatus status_to_send;
    memset(&status_to_send, 0, sizeof(status_to_send));
    
    std::vector<int> clients;

    while (g_running) {
        /* 1. Fetch data from BMS (This acts as the heartbeat) */
        tws_bms::BatteryStatus raw_data;
        if (bms_proto.read_basic_info(raw_data) && bms_proto.read_capacity_info(raw_data)) {
            
            /* 2. Map raw data to shared POD structure */
            status_to_send.voltage = raw_data.voltage;
            status_to_send.current = raw_data.current;
            status_to_send.temperature = raw_data.temperature;
            status_to_send.percentage = raw_data.percentage;
            status_to_send.charge = raw_data.charge;
            status_to_send.capacity = raw_data.capacity;
            status_to_send.protect_status = raw_data.protect_status;
            status_to_send.work_state = raw_data.work_state;
            
            /* 3. Broadcast to all connected clients */
            for (auto it = clients.begin(); it != clients.end(); ) {
                if (write(*it, &status_to_send, sizeof(status_to_send)) < 0) {
                    close(*it);
                    it = clients.erase(it);
                } else {
                    ++it;
                }
            }

            /* 4. Accept new client connections (Non-blocking) */
            struct timeval tv = {0, 10000}; /* 10ms timeout */
            fd_set rfds;
            FD_ZERO(&rfds);
            FD_SET(server_fd, &rfds);
            if (select(server_fd + 1, &rfds, NULL, NULL, &tv) > 0) {
                int cfd = accept(server_fd, NULL, NULL);
                if (cfd >= 0) {
                    clients.push_back(cfd);
                    std::cout << "[BMS Daemon] New client connected." << std::endl;
                }
            }
        } else {
            std::cerr << "[BMS Daemon] BMS Read Failure. Port may be disconnected." << std::endl;
            bms_proto.close_port();
            std::this_thread::sleep_for(std::chrono::seconds(1));
            bms_proto.open();
        }
        
        /* Loop frequency ~1Hz */
        std::this_thread::sleep_for(std::chrono::milliseconds(1000));
    }

    /* Cleanup */
    for (int c : clients) close(c);
    close(server_fd);
    unlink(SOCKET_PATH);
    std::cout << "[BMS Daemon] Shutdown complete." << std::endl;
    return 0;
}
