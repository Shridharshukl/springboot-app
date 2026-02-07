#!/bin/bash
###############################################################################
# Start ngrok tunnels one at a time (for free ngrok accounts)
# Usage: ./start-ngrok.sh [grafana|prometheus|alertmanager|gateway]
###############################################################################

set -euo pipefail

NGROK_AUTHTOKEN="${NGROK_AUTHTOKEN:-36DPaTMFJ4rKa7X8DCqtD3b6r7V_5KBVG65xS4DpfU7PhqfQb}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configure ngrok if not already done
if ! ngrok config check &>/dev/null 2>&1; then
    ngrok config add-authtoken "$NGROK_AUTHTOKEN"
fi

case "${1:-}" in
    grafana)
        echo -e "${GREEN}Starting ngrok tunnel for Grafana (port 30030)...${NC}"
        echo -e "${YELLOW}Login: admin / petclinic2026${NC}"
        ngrok http 30030
        ;;
    prometheus)
        echo -e "${GREEN}Starting ngrok tunnel for Prometheus (port 30090)...${NC}"
        ngrok http 30090
        ;;
    alertmanager)
        echo -e "${GREEN}Starting ngrok tunnel for Alertmanager (port 30093)...${NC}"
        ngrok http 30093
        ;;
    gateway)
        echo -e "${GREEN}Starting ngrok tunnel for API Gateway (port 30080)...${NC}"
        ngrok http 30080
        ;;
    all)
        echo -e "${GREEN}Starting ALL ngrok tunnels (requires paid ngrok plan)...${NC}"
        ngrok start --config ~/.config/ngrok/ngrok-petclinic.yml --all
        ;;
    *)
        echo "Usage: $0 {grafana|prometheus|alertmanager|gateway|all}"
        echo ""
        echo "Free ngrok accounts: Run one tunnel at a time"
        echo "Paid ngrok accounts: Use 'all' to start all tunnels"
        exit 1
        ;;
esac
