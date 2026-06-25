#!/usr/bin/env bash
# ============================================================
# validate.sh — Validação e diagnóstico do Karpenter Provider for OCI
# Uso: KUBECONFIG=~/.kube/<seu-kubeconfig> ./validate.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
section() { echo -e "\n${YELLOW}══════════════════════════════════════${NC}"; echo -e "${YELLOW} $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════${NC}"; }

# ---- 1. Status dos pods do Karpenter ----
section "1. Pods do Karpenter"
kubectl -n karpenter get pods -o wide

# ---- 2. Logs recentes do controller ----
section "2. Logs recentes do controller (últimas 30 linhas)"
kubectl -n karpenter logs -l app.kubernetes.io/name=karpenter --tail=30 2>/dev/null || \
  kubectl -n karpenter logs deployment/karpenter --tail=30

# ---- 3. CRDs instalados ----
section "3. CRDs do Karpenter instalados"
kubectl get crd | grep -E "karpenter|ocinodeclass" || warn "Nenhum CRD karpenter encontrado"

# ---- 4. OciNodeClass ----
section "4. OciNodeClass"
if kubectl get ocinodeclass &>/dev/null; then
  kubectl get ocinodeclass -o wide
  echo ""
  kubectl describe ocinodeclass
else
  warn "Nenhuma OciNodeClass encontrada"
fi

# ---- 5. NodePool ----
section "5. NodePool"
if kubectl get nodepool &>/dev/null; then
  kubectl get nodepool -o wide
  echo ""
  kubectl describe nodepool
else
  warn "Nenhum NodePool encontrado"
fi

# ---- 6. NodeClaims (nós gerenciados pelo Karpenter) ----
section "6. NodeClaims (instâncias provisionadas)"
kubectl get nodeclaim 2>/dev/null || warn "Nenhum NodeClaim ativo (normal se não há pods pendentes)"

# ---- 7. Status dos nós ----
section "7. Todos os nós do cluster"
kubectl get nodes -o wide --show-labels | head -30

# ---- 8. Eventos recentes relacionados ao Karpenter ----
section "8. Eventos Karpenter (últimos 20)"
kubectl get events -A --sort-by=.lastTimestamp \
  | grep -iE "karpenter|nodeclaim|nodepool|ocinodeclass|ScalingUp|ScalingDown|Launched|Terminated" \
  | tail -20 || warn "Nenhum evento karpenter encontrado"

# ---- 9. Teste de scale ----
section "9. Teste de escalonamento"
info "Para testar o scale-out, execute:"
echo ""
echo "  # Escalar o workload de teste para forçar novo nó:"
echo "  kubectl -n karpenter-test scale deployment inflate --replicas=5"
echo ""
echo "  # Acompanhar provisioning em tempo real:"
echo "  watch -n 2 kubectl get nodes"
echo "  kubectl -n karpenter logs -l app.kubernetes.io/name=karpenter -f"
echo ""
echo "  # Acompanhar NodeClaims sendo criados:"
echo "  kubectl get nodeclaim -w"
echo ""
echo "  # Para testar scale-in (consolidação), zerar réplicas:"
echo "  kubectl -n karpenter-test scale deployment inflate --replicas=0"
echo "  # Nós ociosos serão removidos após consolidateAfter (30m no NodePool)"

info "Validação concluída."
