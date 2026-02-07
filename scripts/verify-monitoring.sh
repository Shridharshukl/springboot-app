#!/bin/bash
###############################################################################
# Verify the entire monitoring stack is working
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  Monitoring Stack Health Check"
echo "============================================"
echo ""

echo "1. Prerequisites:"
check "Docker running"         "docker info"
check "Kind cluster running"   "kind get clusters | grep petclinic-monitoring"
check "kubectl configured"     "kubectl cluster-info --context kind-petclinic-monitoring"
check "Helm installed"         "helm version"

echo ""
echo "2. PetClinic Namespace (pods):"
for svc in config-server discovery-server customers-service visits-service vets-service api-gateway admin-server; do
    check "$svc running" "kubectl get pod -l app=$svc -n petclinic -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
done

echo ""
echo "3. Monitoring Namespace (pods):"
check "Prometheus running"           "kubectl get pod -l app.kubernetes.io/name=prometheus -n monitoring -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
check "Grafana running"              "kubectl get pod -l app.kubernetes.io/name=grafana -n monitoring -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
check "Alertmanager running"         "kubectl get pod -l app.kubernetes.io/name=alertmanager -n monitoring -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
check "Prometheus Operator running"  "kubectl get pod -l app.kubernetes.io/name=prometheus-operator -n monitoring -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
check "Node Exporter running"        "kubectl get pod -l app.kubernetes.io/name=prometheus-node-exporter -n monitoring -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

echo ""
echo "4. Endpoints reachable (via NodePort):"
check "Prometheus UI (30090)"    "curl -sf http://localhost:30090/-/healthy"
check "Grafana UI (30030)"       "curl -sf http://localhost:30030/api/health"
check "Alertmanager UI (30093)"  "curl -sf http://localhost:30093/-/healthy"
check "API Gateway (30080)"      "curl -sf http://localhost:30080/actuator/health"

echo ""
echo "5. Prometheus targets scraping:"
TARGETS=$(curl -sf http://localhost:30090/api/v1/targets 2>/dev/null)
if [ -n "$TARGETS" ]; then
    ACTIVE=$(echo "$TARGETS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([t for t in d['data']['activeTargets'] if t['health']=='up']))" 2>/dev/null || echo "0")
    TOTAL=$(echo "$TARGETS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['activeTargets']))" 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✓${NC} Prometheus has ${ACTIVE}/${TOTAL} active targets UP"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${NC} Cannot reach Prometheus targets API"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "6. Metrics available:"
for svc_port in "api-gateway:8080" "customers-service:8081" "visits-service:8082" "vets-service:8083"; do
    svc="${svc_port%%:*}"
    port="${svc_port##*:}"
    POD=$(kubectl get pod -l "app=$svc" -n petclinic -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD" ]; then
        check "$svc /actuator/prometheus" "kubectl exec $POD -n petclinic -- curl -sf localhost:${port}/actuator/prometheus | grep -q jvm_memory"
    else
        echo -e "  ${YELLOW}?${NC} $svc pod not found"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "============================================"
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
