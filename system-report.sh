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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"
OUTPUT_FILE="${LOGS_DIR}/system_report_$(date +%Y%m%d_%H%M%S).log"
VERBOSE=false
INCLUDE_DOCKER=true
INCLUDE_AUDIO=true
MAX_LOGS=50

# Print colored output
print_color() {
    local color=$1
    local message=$2
    if [[ -t 1 ]]; then
        # Only use colors if outputting to terminal
        echo -e "${color}${message}${NC}"
    else
        # Plain text for file output
        echo "$message"
    fi
}

print_header() {
    local title=$1
    echo ""
    if [[ -t 1 ]]; then
        print_color "$CYAN" "=== $title ==="
    else
        echo "=== $title ==="
    fi
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
    # Try multiple ways to get hostname
    local hostname_result
    if command_exists hostname; then
        hostname_result=$(hostname 2>/dev/null)
    elif command_exists hostnamectl; then
        hostname_result=$(hostnamectl --static 2>/dev/null)
    elif [[ -f /etc/hostname ]]; then
        hostname_result=$(cat /etc/hostname 2>/dev/null)
    else
        hostname_result="Unknown"
    fi
    echo "Hostname: ${hostname_result:-Unknown}"
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
                lscpu 2>/dev/null || echo "lscpu command failed"
            elif [[ -f /proc/cpuinfo ]]; then
                echo "=== CPU Info from /proc/cpuinfo ==="
                head -20 /proc/cpuinfo 2>/dev/null || echo "Could not read /proc/cpuinfo"
            else
                echo "CPU information not available"
            fi
            ;;
        "macos")
            echo "CPU Model: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"
            echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')"
            echo "CPU Frequency: $(sysctl -n hw.cpufrequency 2>/dev/null | awk '{print $1/1000000 " MHz"}' 2>/dev/null || echo 'Unknown')"
            if command_exists system_profiler; then
                system_profiler SPHardwareDataType 2>/dev/null | grep -E "(Processor|Memory|Cores)" || echo "System profiler failed"
            fi
            ;;
        "freebsd")
            echo "CPU Model: $(sysctl -n hw.model 2>/dev/null || echo 'Unknown')"
            echo "CPU Cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'Unknown')"
            echo "CPU Frequency: $(sysctl -n hw.clockrate 2>/dev/null | awk '{print $1 " MHz"}' 2>/dev/null || echo 'Unknown')"
            ;;
        "windows")
            if command_exists wmic; then
                wmic cpu get Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed /format:list 2>/dev/null || echo "CPU info not available"
            else
                echo "CPU info tools not available"
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
                free -h 2>/dev/null || echo "free command failed"
            elif [[ -f /proc/meminfo ]]; then
                head -10 /proc/meminfo 2>/dev/null || echo "Could not read /proc/meminfo"
            else
                echo "Memory information not available"
            fi
            ;;
        "macos")
            echo "Total Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB"}' 2>/dev/null || echo 'Unknown')"
            if command_exists vm_stat; then
                vm_stat 2>/dev/null || echo "vm_stat failed"
            fi
            ;;
        "windows")
            if command_exists wmic; then
                echo "=== Physical Memory ==="
                wmic memorychip get Capacity,Speed,MemoryType /format:list 2>/dev/null || echo "Memory info not available"
                echo "=== Memory Usage ==="
                wmic OS get TotalVisibleMemorySize,FreePhysicalMemory /format:list 2>/dev/null || echo "Memory usage not available"
            else
                echo "Memory info tools not available"
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
                df -h 2>/dev/null || df 2>/dev/null || echo "df command failed"
            else
                echo "Disk information not available"
            fi
            ;;
        "windows")
            if command_exists wmic; then
                wmic logicaldisk get Size,FreeSpace,Caption /format:list 2>/dev/null || echo "Disk info not available"
            elif command_exists df; then
                df -h 2>/dev/null || echo "df command failed"
            else
                echo "Disk information not available"
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
                ip addr show 2>/dev/null | grep -E "(inet |link/)" | head -20 || echo "ip command failed"
            elif command_exists ifconfig; then
                ifconfig 2>/dev/null | head -30 || echo "ifconfig failed"
            else
                echo "Network information not available"
            fi
            ;;
        "macos"|"freebsd")
            if command_exists ifconfig; then
                ifconfig 2>/dev/null | grep -E "(inet |ether)" | head -20 || echo "ifconfig failed"
            else
                echo "Network information not available"
            fi
            ;;
        "windows")
            if command_exists ipconfig; then
                ipconfig /all 2>/dev/null | head -30 || echo "ipconfig failed"
            else
                echo "Network information not available"
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
                ps aux --sort=-%cpu 2>/dev/null | head -15 || ps aux 2>/dev/null | head -15 || echo "ps command failed"
            else
                echo "Process information not available"
            fi
            ;;
        "macos")
            if command_exists ps; then
                ps aux -r 2>/dev/null | head -15 || echo "ps command failed"
            else
                echo "Process information not available"
            fi
            ;;
        "windows")
            if command_exists tasklist; then
                tasklist /fo table 2>/dev/null | head -15 || echo "tasklist failed"
            else
                echo "Process information not available"
            fi
            ;;
    esac
}

# Get Docker information (if available and enabled)
get_docker_info() {
    if [[ "$INCLUDE_DOCKER" == true ]] && command_exists docker; then
        print_header "DOCKER INFORMATION"
        
        if docker ps >/dev/null 2>&1; then
            echo "=== Running Containers ==="
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Could not list containers"
            
            echo -e "\n=== Container Resource Usage ==="
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "Could not get container stats"
            
            echo -e "\n=== Docker System Info ==="
            docker system df 2>/dev/null || echo "Docker system info not available"
        else
            echo "Docker is installed but not running or permission denied"
        fi
    else
        echo "Docker not available or disabled"
    fi
}

# Get mount point information
get_mount_info() {
    print_header "MOUNT POINTS & STORAGE"
    
    case "$OS_TYPE" in
        "linux"|"freebsd")
            echo "=== Network and Special Mounts ==="
            mount | grep -E "(cifs|nfs|fuse|/mnt|sshfs)" 2>/dev/null || echo "No network/special mounts found"
            
            echo -e "\n=== Block Devices ==="
            if command_exists lsblk; then
                lsblk -f 2>/dev/null || mount 2>/dev/null | head -10 || echo "Block device info not available"
            else
                mount 2>/dev/null | head -10 || echo "Mount info not available"
            fi
            ;;
        "macos")
            echo "=== Network Mounts ==="
            mount | grep -E "(cifs|nfs|smb|afp)" 2>/dev/null || echo "No network mounts found"
            
            echo -e "\n=== All Mount Points (Top 15) ==="
            mount 2>/dev/null | head -15 || echo "Mount info not available"
            ;;
        "windows")
            echo "=== Network Drives ==="
            if command_exists net; then
                net use 2>/dev/null || echo "No network drives found"
            else
                echo "Network drive info not available"
            fi
            ;;
    esac
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
                else
                    echo "Audio info not available"
                fi
                ;;
            "windows")
                echo "=== Audio Devices ==="
                if command_exists wmic; then
                    wmic sounddev get Name,Status /format:list 2>/dev/null || echo "Audio info not available"
                else
                    echo "Audio info not available"
                fi
                ;;
        esac
    else
        echo "Audio monitoring disabled"
    fi
}

# Get system services
get_services_info() {
    print_header "SYSTEM SERVICES"
    
    case "$OS_TYPE" in
        "linux")
            if command_exists systemctl; then
                echo "=== Active Services (Audio/Media/Docker Related) ==="
                systemctl list-units --type=service --state=running 2>/dev/null | grep -iE "(audio|sound|pulse|jack|docker|media|plex|container)" || echo "No matching services found"
                
                echo -e "\n=== All Running Services ==="
                systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -15 || echo "Service info not available"
            else
                echo "systemctl not available"
            fi
            ;;
        "macos")
            if command_exists launchctl; then
                echo "=== Running Services ==="
                launchctl list 2>/dev/null | grep -v "^-" | head -15 || echo "Service info not available"
            else
                echo "launchctl not available"
            fi
            ;;
        "freebsd")
            if command_exists service; then
                echo "=== Running Services ==="
                service -e 2>/dev/null || echo "Service info not available"
            else
                echo "service command not available"
            fi
            ;;
        "windows")
            if command_exists sc; then
                echo "=== Running Services ==="
                sc query state= running 2>/dev/null | head -20 || echo "Service info not available"
            else
                echo "sc command not available"
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
                        temp=$(cat "$thermal" 2>/dev/null)
                        zone=$(basename "$(dirname "$thermal")")
                        echo "$zone: $((temp / 1000))°C"
                    fi
                done
            else
                echo "Temperature monitoring not available"
            fi
            ;;
        "macos")
            echo "Temperature monitoring requires third-party tools on macOS"
            if command_exists istats; then
                istats 2>/dev/null || echo "Install iStats for temperature monitoring: gem install iStats"
            fi
            ;;
        "freebsd")
            if command_exists sysctl; then
                sysctl hw.acpi.thermal 2>/dev/null || echo "Temperature info not available"
            else
                echo "Temperature monitoring not available"
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
    -o, --output FILE   Specify output filename (will be saved in logs/ directory)
    --no-docker         Skip Docker information
    --no-audio          Skip audio system information
    --no-temp           Skip temperature information

EXAMPLES:
    $0                  Run with default settings
    $0 -v -o my_report  Verbose output to logs/my_report.log
    $0 --no-docker --no-audio    Skip Docker and audio info

LOG MANAGEMENT:
    - Logs are automatically saved to logs/ subdirectory
    - Maximum of $MAX_LOGS log files are kept
    - Older logs are automatically cleaned up

SUPPORTED SYSTEMS:
    - Linux (all major distributions)
    - macOS
    - FreeBSD
    - Windows (via WSL, Git Bash, or Cygwin)

EOF
}

# Create logs directory and manage log rotation
setup_logging() {
    # Create logs directory if it doesn't exist
    if [[ ! -d "$LOGS_DIR" ]]; then
        mkdir -p "$LOGS_DIR" || {
            print_color "$RED" "Error: Cannot create logs directory: $LOGS_DIR"
            exit 1
        }
        print_color "$GREEN" "Created logs directory: $LOGS_DIR"
    fi
    
    # Clean up old logs if we have too many
    local log_count
    log_count=$(find "$LOGS_DIR" -name "system_report_*.log" -type f 2>/dev/null | wc -l)
    
    if [[ $log_count -ge $MAX_LOGS ]]; then
        local logs_to_remove=$((log_count - MAX_LOGS + 1))
        print_color "$YELLOW" "Found $log_count log files. Cleaning up $logs_to_remove oldest files..."
        
        # Remove oldest log files (using portable method)
        find "$LOGS_DIR" -name "system_report_*.log" -type f -exec ls -t {} + 2>/dev/null | tail -n "$logs_to_remove" | while IFS= read -r file; do
            rm -f "$file" && print_color "$YELLOW" "Removed: $(basename "$file")"
        done
    fi
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
                # If user specifies custom output, still put it in logs directory but allow custom name
                OUTPUT_FILE="${LOGS_DIR}/$(basename "$2")"
                # Add .log extension if not present
                [[ "$OUTPUT_FILE" == *.log ]] || OUTPUT_FILE="${OUTPUT_FILE}.log"
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
    
    # Setup logging directory and cleanup
    setup_logging
    
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
        get_mount_info
        get_audio_info
        get_services_info
        
        if [[ "${INCLUDE_TEMP:-true}" == true ]]; then
            get_temperature_info
        fi
        
    } > "$OUTPUT_FILE" 2>&1
    
    # Also display to terminal with colors
    if [[ -t 1 ]]; then
        cat "$OUTPUT_FILE"
    fi
    
    print_color "$GREEN" "Report saved to: $OUTPUT_FILE"
    
    # Show log management info
    local current_log_count
    current_log_count=$(find "$LOGS_DIR" -name "system_report_*.log" -type f 2>/dev/null | wc -l)
    print_color "$CYAN" "Total logs in directory: $current_log_count/$MAX_LOGS"
}

# Run main function with all arguments
main "$@"