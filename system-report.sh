#!/bin/bash

# Cross-Platform System Monitor
# Supports Linux, macOS, Windows (via WSL/Git Bash), and FreeBSD

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
OS_TYPE=""
DISTRO=""
OUTPUT_FILE="system_report_$(date +%Y%m%d_%H%M%S).txt"
VERBOSE=false
INCLUDE_DOCKER=true
INCLUDE_AUDIO=true

# Print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    local title=$1
    echo ""
    print_color "$CYAN" "=== $title ==="
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
        if [[ -f /etc/os-release ]]; then
            DISTRO=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        DISTRO="macos"
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        OS_TYPE="windows"
        DISTRO="windows"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        OS_TYPE="freebsd"
        DISTRO="freebsd"
    else
        OS_TYPE="unknown"
        DISTRO="unknown"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system load average
get_load_average() {
    case "$OS_TYPE" in
        "linux"|"freebsd")
            if [[ -f /proc/loadavg ]]; then
                read -r load1 load5 load15 _ < /proc/loadavg
                echo "Load Average: $load1 (1m), $load5 (5m), $load15 (15m)"
            elif command_exists uptime; then
                uptime | grep -o 'load average.*' || echo "Load info not available"
            fi
            ;;
        "macos")
            uptime | grep -o 'load averages.*' || echo "Load info not available"
            ;;
        "windows")
            # Windows doesn't have direct load average, use CPU percentage instead
            if command_exists wmic; then
                local cpu_usage
                cpu_usage=$(wmic cpu get loadpercentage /value 2>/dev/null | grep -o '[0-9]*' | head -1)
                echo "CPU Usage: ${cpu_usage:-N/A}%"
            else
                echo "Load info not available on Windows"
            fi
            ;;
    esac
}

# Get CPU core count
get_cpu_cores() {
    case "$OS_TYPE" in
        "linux")
            nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown"
            ;;
        "macos")
            sysctl -n hw.ncpu 2>/dev/null || echo "Unknown"
            ;;
        "freebsd")
            sysctl -n hw.ncpu 2>/dev/null || echo "Unknown"
            ;;
        "windows")
            echo "${NUMBER_OF_PROCESSORS:-Unknown}"
            ;;
    esac
}

# Get system information
get_system_info() {
    print_header "SYSTEM OVERVIEW"
    
    echo "Operating System: $OS_TYPE ($DISTRO)"
    echo "Hostname: $(hostname 2>/dev/null || echo 'Unknown')"
    echo "Date/Time: $(date)"
    echo "CPU Cores: $(get_cpu_cores)"
    get_load_average
    
    # Uptime
    case "$OS_TYPE" in
        "linux"|"freebsd")
            if command_exists uptime; then
                echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
            fi
            ;;
        "macos")
            if command_exists uptime; then
                echo "Uptime: $(uptime)"
            fi
            ;;
        "windows")
            if command_exists systeminfo; then
                systeminfo | grep "System Boot Time" 2>/dev/null || echo "Uptime: Not available"
            fi
            ;;
    esac
}

# Get detailed CPU information
get_cpu_info() {
    print_header "CPU INFORMATION"
    
    case "$OS_TYPE" in
        "linux")
            if command_exists lscpu; then
                lscpu
            elif [[ -f /proc/cpuinfo ]]; then
                head -20 /proc/cpuinfo
            fi
            ;;
        "macos")
            echo "CPU Model: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
            echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null)"
            echo "CPU Frequency: $(sysctl -n hw.cpufrequency 2>/dev/null | awk '{print $1/1000000 " MHz"}' || echo 'Unknown')"
            if command_exists system_profiler; then
                system_profiler SPHardwareDataType | grep -E "(Processor|Memory|Cores)"
            fi
            ;;
        "freebsd")
            echo "CPU Model: $(sysctl -n hw.model 2>/dev/null || echo 'Unknown')"
            echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null)"
            echo "CPU Frequency: $(sysctl -n hw.clockrate 2>/dev/null | awk '{print $1 " MHz"}' || echo 'Unknown')"
            ;;
        "windows")
            if command_exists wmic; then
                wmic cpu get Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed /format:list 2>/dev/null || echo "CPU info not available"
            fi
            ;;
    esac
}

# Get memory information
get_memory_info() {
    print_header "MEMORY INFORMATION"
    
    case "$OS_TYPE" in
        "linux"|"freebsd")
            if command_exists free; then
                free -h
            elif [[ -f /proc/meminfo ]]; then
                head -10 /proc/meminfo
            fi
            ;;
        "macos")
            echo "Total Memory: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GB"}')"
            if command_exists vm_stat; then
                vm_stat
            fi
            ;;
        "windows")
            if command_exists wmic; then
                echo "=== Physical Memory ==="
                wmic memorychip get Capacity,Speed,MemoryType /format:list 2>/dev/null
                echo "=== Memory Usage ==="
                wmic OS get TotalVisibleMemorySize,FreePhysicalMemory /format:list 2>/dev/null
            fi
            ;;
    esac
}

# Get disk information
get_disk_info() {
    print_header "DISK USAGE"
    
    case "$OS_TYPE" in
        "linux"|"freebsd"|"macos")
            if command_exists df; then
                df -h 2>/dev/null || df
            fi
            ;;
        "windows")
            if command_exists wmic; then
                wmic logicaldisk get Size,FreeSpace,Caption /format:list 2>/dev/null
            elif command_exists df; then
                df -h 2>/dev/null
            fi
            ;;
    esac
}

# Get network information
get_network_info() {
    print_header "NETWORK INTERFACES"
    
    case "$OS_TYPE" in
        "linux")
            if command_exists ip; then
                ip addr show 2>/dev/null | grep -E "(inet |link/)" | head -20
            elif command_exists ifconfig; then
                ifconfig | head -30
            fi
            ;;
        "macos"|"freebsd")
            if command_exists ifconfig; then
                ifconfig | grep -E "(inet |ether)" | head -20
            fi
            ;;
        "windows")
            if command_exists ipconfig; then
                ipconfig /all | head -30
            fi
            ;;
    esac
}

# Get process information
get_process_info() {
    print_header "TOP PROCESSES (CPU)"
    
    case "$OS_TYPE" in
        "linux"|"freebsd")
            if command_exists ps; then
                ps aux --sort=-%cpu | head -15 2>/dev/null || ps aux | head -15
            fi
            ;;
        "macos")
            if command_exists ps; then
                ps aux -r | head -15
            fi
            ;;
        "windows")
            if command_exists tasklist; then
                tasklist /fo table | head -15
            fi
            ;;
    esac
}

# Get Docker information (if available and enabled)
get_docker_info() {
    if [[ "$INCLUDE_DOCKER" == true ]] && command_exists docker; then
        print_header "DOCKER CONTAINERS"
        
        if docker ps >/dev/null 2>&1; then
            echo "=== Running Containers ==="
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
            
            echo -e "\n=== Container Stats ==="
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null
        else
            echo "Docker is installed but not running or permission denied"
        fi
    fi
}

# Get audio system information
get_audio_info() {
    if [[ "$INCLUDE_AUDIO" == true ]]; then
        print_header "AUDIO SYSTEM"
        
        case "$OS_TYPE" in
            "linux")
                # ALSA info
                if command_exists aplay; then
                    echo "=== ALSA Devices ==="
                    aplay -l 2>/dev/null || echo "No ALSA devices found"
                fi
                
                # PulseAudio info
                if command_exists pactl; then
                    echo -e "\n=== PulseAudio Sinks ==="
                    pactl list short sinks 2>/dev/null || echo "PulseAudio not running"
                    echo -e "\n=== PulseAudio Sources ==="
                    pactl list short sources 2>/dev/null || echo "PulseAudio not running"
                fi
                
                # JACK info
                if command_exists jack_lsp; then
                    echo -e "\n=== JACK Ports ==="
                    jack_lsp 2>/dev/null || echo "JACK not running"
                fi
                ;;
            "macos")
                echo "=== Audio Devices ==="
                if command_exists system_profiler; then
                    system_profiler SPAudioDataType 2>/dev/null | grep -E "(Name|Sample Rate)" || echo "Audio info not available"
                fi
                ;;
            "windows")
                echo "=== Audio Devices ==="
                if command_exists wmic; then
                    wmic sounddev get Name,Status /format:list 2>/dev/null || echo "Audio info not available"
                fi
                ;;
        esac
    fi
}

# Get system services
get_services_info() {
    print_header "SYSTEM SERVICES"
    
    case "$OS_TYPE" in
        "linux")
            if command_exists systemctl; then
                echo "=== Active Services (Audio/Media Related) ==="
                systemctl list-units --type=service --state=running | grep -iE "(audio|sound|pulse|jack|docker|media|plex)" 2>/dev/null || echo "No matching services found"
            fi
            ;;
        "macos")
            if command_exists launchctl; then
                echo "=== Running Services ==="
                launchctl list | head -10 2>/dev/null || echo "Service info not available"
            fi
            ;;
        "freebsd")
            if command_exists service; then
                echo "=== Running Services ==="
                service -e 2>/dev/null || echo "Service info not available"
            fi
            ;;
        "windows")
            if command_exists sc; then
                echo "=== Running Services ==="
                sc query state= running | head -20 2>/dev/null || echo "Service info not available"
            fi
            ;;
    esac
}

# Get temperature information
get_temperature_info() {
    print_header "SYSTEM TEMPERATURES"
    
    case "$OS_TYPE" in
        "linux")
            if command_exists sensors; then
                sensors 2>/dev/null || echo "lm-sensors not available"
            elif [[ -d /sys/class/thermal ]]; then
                for thermal in /sys/class/thermal/thermal_zone*/temp; do
                    if [[ -r "$thermal" ]]; then
                        temp=$(cat "$thermal")
                        zone=$(basename "$(dirname "$thermal")")
                        echo "$zone: $((temp / 1000))°C"
                    fi
                done
            else
                echo "Temperature monitoring not available"
            fi
            ;;
        "macos")
            # macOS doesn't have built-in temperature monitoring without third-party tools
            echo "Temperature monitoring requires third-party tools on macOS"
            if command_exists istats; then
                istats 2>/dev/null || echo "Install iStats for temperature monitoring: gem install iStats"
            fi
            ;;
        "freebsd")
            if command_exists sysctl; then
                sysctl hw.acpi.thermal 2>/dev/null || echo "Temperature info not available"
            fi
            ;;
        "windows")
            echo "Temperature monitoring requires third-party tools on Windows"
            ;;
    esac
}

# Display usage information
show_usage() {
    cat << EOF
Cross-Platform System Monitor

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -o, --output FILE   Specify output file (default: system_report_YYYYMMDD_HHMMSS.txt)
    --no-docker         Skip Docker information
    --no-audio          Skip audio system information
    --no-temp           Skip temperature information

EXAMPLES:
    $0                  Run with default settings
    $0 -v -o my_report.txt    Verbose output to custom file
    $0 --no-docker --no-audio    Skip Docker and audio info

SUPPORTED SYSTEMS:
    - Linux (all major distributions)
    - macOS
    - FreeBSD
    - Windows (via WSL, Git Bash, or Cygwin)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --no-docker)
                INCLUDE_DOCKER=false
                shift
                ;;
            --no-audio)
                INCLUDE_AUDIO=false
                shift
                ;;
            --no-temp)
                INCLUDE_TEMP=false
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    parse_args "$@"
    detect_os
    
    print_color "$GREEN" "Cross-Platform System Monitor"
    print_color "$YELLOW" "Detected OS: $OS_TYPE ($DISTRO)"
    print_color "$BLUE" "Report will be saved to: $OUTPUT_FILE"
    
    # Create report
    {
        echo "Cross-Platform System Monitor Report"
        echo "Generated on: $(date)"
        echo "Operating System: $OS_TYPE ($DISTRO)"
        echo "=============================================="
        
        get_system_info
        get_cpu_info
        get_memory_info
        get_disk_info
        get_network_info
        get_process_info
        get_docker_info
        get_audio_info
        get_services_info
        
        if [[ "${INCLUDE_TEMP:-true}" == true ]]; then
            get_temperature_info
        fi
        
    } | tee "$OUTPUT_FILE"
    
    print_color "$GREEN" "Report saved to: $OUTPUT_FILE"
}

# Run main function with all arguments
main "$@"