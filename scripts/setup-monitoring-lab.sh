#!/bin/bash
###############################################################################
# Spring PetClinic Microservices - Production Monitoring Lab Setup
# This script sets up the entire monitoring stack:
#   1. Install Docker
#   2. Build all microservice Docker images
#   3. Install Kind (Kubernetes in Docker)
#   4. Create Kind cluster
#   5. Load images into Kind
#   6. Deploy microservices
#   7. Install Prometheus + Grafana + Alertmanager via Helm
#   8. Configure ServiceMonitors and dashboards
#   9. Setup ngrok for external access
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_DIR="${PROJECT_ROOT}/k8s"

# Configuration
NGROK_AUTHTOKEN="${NGROK_AUTHTOKEN:-36DPaTMFJ4rKa7X8DCqtD3b6r7V_5KBVG65xS4DpfU7PhqfQb}"
KIND_CLUSTER_NAME="petclinic-monitoring"
HELM_RELEASE_NAME="prometheus"
MONITORING_NAMESPACE="monitoring"
PETCLINIC_NAMESPACE="petclinic"

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}  STEP: $1${NC}"; echo -e "${BLUE}========================================${NC}\n"; }

###############################################################################
# STEP 1: Install Docker
###############################################################################
install_docker() {
    log_step "Installing Docker"

    if command -v docker &>/dev/null; then
        log_info "Docker already installed: $(docker --version)"
        return 0
    fi

    log_info "Installing Docker on Alpine Linux..."
    sudo apk update
    sudo apk add docker docker-cli docker-compose openrc

    # Start Docker daemon
    sudo rc-update add docker default 2>/dev/null || true
    sudo service docker start 2>/dev/null || sudo dockerd &

    # Wait for Docker to be ready
    local retries=30
    while ! docker info &>/dev/null && [ $retries -gt 0 ]; do
        log_info "Waiting for Docker daemon... ($retries)"
        sleep 2
        retries=$((retries - 1))
    done

    if ! docker info &>/dev/null; then
        log_error "Docker daemon failed to start. Trying alternative method..."
        # Try running dockerd directly
        sudo dockerd --host=unix:///var/run/docker.sock &
        sleep 5
    fi

    # Add current user to docker group
    sudo addgroup "$(whoami)" docker 2>/dev/null || true

    log_info "Docker installed: $(docker --version)"
}

###############################################################################
# STEP 2: Install Java 17 (if not present)
###############################################################################
install_java() {
    log_step "Checking Java"

    if command -v java &>/dev/null; then
        JAVA_VER=$(java -version 2>&1 | head -1)
        log_info "Java already installed: $JAVA_VER"
        return 0
    fi

    log_info "Installing Java 17..."
    sudo apk add openjdk17
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
    export PATH=$JAVA_HOME/bin:$PATH
    log_info "Java installed: $(java -version 2>&1 | head -1)"
}

###############################################################################
# STEP 3: Build Docker Images
###############################################################################
build_images() {
    log_step "Building Docker Images for all microservices"

    cd "$PROJECT_ROOT"

    # Build all JARs first
    log_info "Building all microservice JARs with Maven..."
    chmod +x mvnw
    ./mvnw clean package -DskipTests -pl \
        spring-petclinic-config-server,\
spring-petclinic-discovery-server,\
spring-petclinic-customers-service,\
spring-petclinic-visits-service,\
spring-petclinic-vets-service,\
spring-petclinic-api-gateway,\
spring-petclinic-admin-server \
        -am

    # Build Docker images for each service
    local services=(
        "spring-petclinic-config-server:8888"
        "spring-petclinic-discovery-server:8761"
        "spring-petclinic-customers-service:8081"
        "spring-petclinic-visits-service:8082"
        "spring-petclinic-vets-service:8083"
        "spring-petclinic-api-gateway:8080"
        "spring-petclinic-admin-server:9090"
    )

    for svc_port in "${services[@]}"; do
        svc="${svc_port%%:*}"
        port="${svc_port##*:}"
        jar_name=$(ls "${PROJECT_ROOT}/${svc}/target/"*.jar 2>/dev/null | head -1)

        if [ -z "$jar_name" ]; then
            log_warn "JAR not found for $svc, skipping..."
            continue
        fi

        jar_basename=$(basename "$jar_name" .jar)
        log_info "Building Docker image for $svc (port $port)..."

        docker build \
            -f "${PROJECT_ROOT}/docker/Dockerfile" \
            --build-arg "ARTIFACT_NAME=${jar_basename}" \
            --build-arg "EXPOSED_PORT=${port}" \
            -t "springcommunity/${svc}:latest" \
            "${PROJECT_ROOT}/${svc}/target/"
    done

    log_info "All Docker images built successfully!"
    docker images | grep springcommunity
}

###############################################################################
# STEP 4: Install kubectl
###############################################################################
install_kubectl() {
    log_step "Installing kubectl"

    if command -v kubectl &>/dev/null; then
        log_info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return 0
    fi

    log_info "Downloading kubectl..."
    local ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac

    curl -Lo /tmp/kubectl "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    chmod +x /tmp/kubectl
    sudo mv /tmp/kubectl /usr/local/bin/kubectl
    log_info "kubectl installed: $(kubectl version --client 2>&1 | head -1)"
}

###############################################################################
# STEP 5: Install Kind
###############################################################################
install_kind() {
    log_step "Installing Kind (Kubernetes in Docker)"

    if command -v kind &>/dev/null; then
        log_info "Kind already installed: $(kind version)"
        return 0
    fi

    log_info "Downloading Kind..."
    local ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac

    curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-${ARCH}"
    chmod +x /tmp/kind
    sudo mv /tmp/kind /usr/local/bin/kind
    log_info "Kind installed: $(kind version)"
}

###############################################################################
# STEP 6: Install Helm
###############################################################################
install_helm() {
    log_step "Installing Helm"

    if command -v helm &>/dev/null; then
        log_info "Helm already installed: $(helm version --short)"
        return 0
    fi

    log_info "Downloading Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed: $(helm version --short)"
}

###############################################################################
# STEP 7: Create Kind Cluster
###############################################################################
create_kind_cluster() {
    log_step "Creating Kind Cluster"

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "$KIND_CLUSTER_NAME"; then
        log_warn "Kind cluster '$KIND_CLUSTER_NAME' already exists."
        read -p "Delete and recreate? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "$KIND_CLUSTER_NAME"
        else
            log_info "Using existing cluster."
            kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" || true
            return 0
        fi
    fi

    log_info "Creating Kind cluster with config..."
    kind create cluster --config "${K8S_DIR}/kind-config.yaml" --wait 60s

    log_info "Cluster created. Setting kubectl context..."
    kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
    kubectl get nodes
}

###############################################################################
# STEP 8: Load Docker Images into Kind
###############################################################################
load_images_to_kind() {
    log_step "Loading Docker images into Kind cluster"

    local images=(
        "springcommunity/spring-petclinic-config-server:latest"
        "springcommunity/spring-petclinic-discovery-server:latest"
        "springcommunity/spring-petclinic-customers-service:latest"
        "springcommunity/spring-petclinic-visits-service:latest"
        "springcommunity/spring-petclinic-vets-service:latest"
        "springcommunity/spring-petclinic-api-gateway:latest"
        "springcommunity/spring-petclinic-admin-server:latest"
    )

    for img in "${images[@]}"; do
        if docker image inspect "$img" &>/dev/null; then
            log_info "Loading $img into Kind..."
            kind load docker-image "$img" --name "$KIND_CLUSTER_NAME"
        else
            log_warn "Image $img not found locally, skipping..."
        fi
    done

    log_info "All images loaded into Kind cluster."
}

###############################################################################
# STEP 9: Deploy PetClinic Microservices
###############################################################################
deploy_petclinic() {
    log_step "Deploying PetClinic Microservices to Kubernetes"

    # Create namespaces
    kubectl apply -f "${K8S_DIR}/namespaces.yaml"

    # Deploy in order (config-server first, then discovery, then services)
    log_info "Deploying Config Server..."
    kubectl apply -f "${K8S_DIR}/01-config-server.yaml"
    log_info "Waiting for Config Server to be ready..."
    kubectl wait --for=condition=available --timeout=180s deployment/config-server -n "$PETCLINIC_NAMESPACE" || true
    sleep 10

    log_info "Deploying Discovery Server..."
    kubectl apply -f "${K8S_DIR}/02-discovery-server.yaml"
    log_info "Waiting for Discovery Server to be ready..."
    kubectl wait --for=condition=available --timeout=180s deployment/discovery-server -n "$PETCLINIC_NAMESPACE" || true
    sleep 10

    log_info "Deploying Business Services (customers, visits, vets)..."
    kubectl apply -f "${K8S_DIR}/03-business-services.yaml"

    log_info "Deploying API Gateway & Admin Server..."
    kubectl apply -f "${K8S_DIR}/04-api-gateway-admin.yaml"

    log_info "Waiting for all deployments..."
    kubectl wait --for=condition=available --timeout=300s deployment --all -n "$PETCLINIC_NAMESPACE" || true

    log_info "PetClinic services deployed:"
    kubectl get pods -n "$PETCLINIC_NAMESPACE" -o wide
    kubectl get svc -n "$PETCLINIC_NAMESPACE"
}

###############################################################################
# STEP 10: Install Prometheus + Grafana + Alertmanager via Helm
###############################################################################
deploy_monitoring_stack() {
    log_step "Deploying Prometheus + Grafana + Alertmanager (kube-prometheus-stack)"

    # Add Helm repos
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Install kube-prometheus-stack
    log_info "Installing kube-prometheus-stack Helm chart..."
    helm upgrade --install "$HELM_RELEASE_NAME" prometheus-community/kube-prometheus-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --create-namespace \
        --values "${K8S_DIR}/helm-values-prometheus-stack.yaml" \
        --wait \
        --timeout 10m

    # Apply ServiceMonitor and PrometheusRule
    log_info "Applying ServiceMonitor and alerting rules..."
    kubectl apply -f "${K8S_DIR}/05-service-monitor.yaml"

    # Apply Grafana dashboards
    log_info "Applying Grafana dashboards..."
    kubectl apply -f "${K8S_DIR}/06-grafana-dashboards.yaml"

    log_info "Monitoring stack deployed:"
    kubectl get pods -n "$MONITORING_NAMESPACE"
    kubectl get svc -n "$MONITORING_NAMESPACE"
}

###############################################################################
# STEP 11: Install & Configure ngrok for External Access
###############################################################################
install_ngrok() {
    log_step "Installing ngrok"

    if command -v ngrok &>/dev/null; then
        log_info "ngrok already installed."
    else
        log_info "Downloading ngrok..."
        local ARCH=$(uname -m)
        case $ARCH in
            x86_64) ARCH="amd64" ;;
            aarch64) ARCH="arm64" ;;
        esac

        curl -Lo /tmp/ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ARCH}.tgz"
        tar -xzf /tmp/ngrok.tgz -C /tmp/
        chmod +x /tmp/ngrok
        sudo mv /tmp/ngrok /usr/local/bin/ngrok
        rm -f /tmp/ngrok.tgz
    fi

    # Configure ngrok authtoken
    log_info "Configuring ngrok authtoken..."
    ngrok config add-authtoken "$NGROK_AUTHTOKEN"

    log_info "ngrok installed: $(ngrok version)"
}

setup_ngrok_tunnels() {
    log_step "Setting up ngrok tunnels for Prometheus, Alertmanager, and Grafana"

    # Create ngrok config file for multiple tunnels
    mkdir -p ~/.config/ngrok
    cat > ~/.config/ngrok/ngrok-petclinic.yml << 'NGROK_EOF'
version: "3"
tunnels:
  prometheus:
    addr: 30090
    proto: http
    metadata: "Spring PetClinic - Prometheus"
  alertmanager:
    addr: 30093
    proto: http
    metadata: "Spring PetClinic - Alertmanager"
  grafana:
    addr: 30030
    proto: http
    metadata: "Spring PetClinic - Grafana"
  api-gateway:
    addr: 30080
    proto: http
    metadata: "Spring PetClinic - API Gateway"
NGROK_EOF

    log_info "Starting ngrok tunnels..."
    log_warn "NOTE: Free ngrok accounts only support 1 tunnel at a time."
    log_warn "For multiple tunnels, you need ngrok paid plan."
    log_info ""
    log_info "Starting ngrok for all services..."

    # Start ngrok with all tunnels (paid plan) or individually (free plan)
    nohup ngrok start --config ~/.config/ngrok/ngrok-petclinic.yml --all > /tmp/ngrok.log 2>&1 &
    NGROK_PID=$!
    sleep 5

    # Check if ngrok started successfully
    if kill -0 $NGROK_PID 2>/dev/null; then
        log_info "ngrok is running (PID: $NGROK_PID)"

        # Get tunnel URLs from ngrok API
        sleep 3
        log_info "Fetching ngrok tunnel URLs..."
        curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for t in data.get('tunnels', []):
        print(f\"  {t['name']:20s} -> {t['public_url']}\")
except:
    print('  Could not fetch tunnel URLs. Check http://localhost:4040')
" 2>/dev/null || log_warn "Could not fetch tunnel URLs. Free plan may only support 1 tunnel."

        log_info ""
        log_info "ngrok Web Inspector: http://localhost:4040"
    else
        log_warn "ngrok failed to start with all tunnels. Trying individual tunnels..."
        log_info ""
        log_info "Run these commands individually to start tunnels:"
        log_info "  ngrok http 30090  # Prometheus"
        log_info "  ngrok http 30093  # Alertmanager"
        log_info "  ngrok http 30030  # Grafana"
        log_info "  ngrok http 30080  # API Gateway"
    fi
}

###############################################################################
# STEP 12: Print Summary
###############################################################################
print_summary() {
    log_step "SETUP COMPLETE - Summary"

    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Spring PetClinic Monitoring Lab - Ready!  ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${BLUE}Local Access (via Kind NodePorts):${NC}"
    echo "  Prometheus:    http://localhost:30090"
    echo "  Alertmanager:  http://localhost:30093"
    echo "  Grafana:       http://localhost:30030  (admin / petclinic2026)"
    echo "  API Gateway:   http://localhost:30080"
    echo ""
    echo -e "${BLUE}Kubernetes:${NC}"
    echo "  kubectl get pods -n petclinic"
    echo "  kubectl get pods -n monitoring"
    echo ""
    echo -e "${BLUE}Test Prometheus scraping:${NC}"
    echo "  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
    echo "  Open: http://localhost:9090/targets"
    echo ""
    echo -e "${BLUE}Grafana Dashboards:${NC}"
    echo "  - Spring PetClinic - Microservices Overview (auto-provisioned)"
    echo "  - Also import community dashboards: 4701 (JVM), 12900 (Spring Boot)"
    echo ""
    echo -e "${BLUE}ngrok External Access:${NC}"
    echo "  Check ngrok dashboard: http://localhost:4040"
    echo "  Or run individual tunnels:"
    echo "    ngrok http 30030  # Grafana"
    echo "    ngrok http 30090  # Prometheus"
    echo "    ngrok http 30093  # Alertmanager"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  # Check service metrics:"
    echo "  kubectl exec -it \$(kubectl get pod -l app=api-gateway -n petclinic -o jsonpath='{.items[0].metadata.name}') -n petclinic -- curl localhost:8080/actuator/prometheus | head -20"
    echo ""
    echo "  # Check Prometheus targets:"
    echo "  curl -s http://localhost:30090/api/v1/targets | python3 -m json.tool | head -50"
    echo ""
    echo "  # Cleanup:"
    echo "  kind delete cluster --name ${KIND_CLUSTER_NAME}"
    echo ""
}

###############################################################################
# MAIN EXECUTION
###############################################################################
main() {
    log_info "Starting Spring PetClinic Monitoring Lab Setup"
    log_info "Project root: $PROJECT_ROOT"
    echo ""

    install_docker
    install_java
    build_images
    install_kubectl
    install_kind
    install_helm
    create_kind_cluster
    load_images_to_kind
    deploy_petclinic
    deploy_monitoring_stack
    install_ngrok
    setup_ngrok_tunnels
    print_summary
}

# Allow running individual steps
case "${1:-all}" in
    docker)     install_docker ;;
    java)       install_java ;;
    build)      build_images ;;
    kubectl)    install_kubectl ;;
    kind)       install_kind ;;
    helm)       install_helm ;;
    cluster)    create_kind_cluster ;;
    load)       load_images_to_kind ;;
    deploy)     deploy_petclinic ;;
    monitoring) deploy_monitoring_stack ;;
    ngrok)      install_ngrok && setup_ngrok_tunnels ;;
    summary)    print_summary ;;
    all)        main ;;
    *)
        echo "Usage: $0 {all|docker|java|build|kubectl|kind|helm|cluster|load|deploy|monitoring|ngrok|summary}"
        exit 1
        ;;
esac
