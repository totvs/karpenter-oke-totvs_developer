#!/usr/bin/env bash
# ============================================================
# iam-policies.sh — IAM para KPO conforme documentação oficial Oracle
#
# Duas partes:
#   1. Policy Workload Identity — permissoes para o CONTROLLER KPO
#      gerenciar instancias, volumes e rede no OCI
#   2. Dynamic Group + Policy — permite que os NOS provisionados
#      se registrem (CLUSTER_JOIN) no cluster OKE
#
# Uso:
#   chmod +x iam-policies.sh
#   OCI_CLI_PROFILE=<perfil> ./iam-policies.sh
#
# Documentacao Oracle:
#   https://docs.oracle.com/iaas/Content/ContEng/Tasks/contengusingkarpenter.htm
# ============================================================
set -euo pipefail

# ------------------------------------------------------------
# Variaveis obrigatorias — exportar antes de executar o script:
#
#   export TENANCY_ID="ocid1.tenancy.oc1..XXXXXXXX"
#   export COMPARTMENT_ID="ocid1.compartment.oc1..XXXXXXXX"
#   export CLUSTER_ID="ocid1.cluster.oc1.<regiao>.XXXXXXXX"
#   export COMPARTMENT_NAME="<nome-do-compartment>"   # usado nas policy statements
#   export OCI_CLI_PROFILE="<perfil-oci-cli>"         # padrao: default
#
# Obter COMPARTMENT_NAME via:
#   oci iam compartment get --compartment-id $COMPARTMENT_ID \
#     --profile $OCI_CLI_PROFILE --query 'data.name' --raw-output
# ------------------------------------------------------------

: "${TENANCY_ID:?Variavel TENANCY_ID nao definida. Exporte antes de executar.}"
: "${COMPARTMENT_ID:?Variavel COMPARTMENT_ID nao definida. Exporte antes de executar.}"
: "${CLUSTER_ID:?Variavel CLUSTER_ID nao definida. Exporte antes de executar.}"
: "${COMPARTMENT_NAME:?Variavel COMPARTMENT_NAME nao definida. Exporte antes de executar.}"

PROFILE="${OCI_CLI_PROFILE:-default}"

KPO_NAMESPACE="karpenter"
KPO_SA="karpenter"

DG_NAME="kpo-nodes-dyn-grp"
POLICY_WORKLOAD_NAME="kpo-workload-identity-policy"
POLICY_NODES_NAME="kpo-nodes-policy"

# ============================================================
# PARTE 1: Policy Workload Identity para o controller KPO
# O KPO usa Workload Identity (service account do k8s) —
# NAO usa Instance Principal nem API key armazenada no cluster.
# ============================================================
echo "==> [1/2] Criando Policy Workload Identity para o controller KPO..."

# Condicao Workload Identity — restringe a policy ao SA do KPO no cluster
WI="request.principal.type = 'workload', request.principal.namespace = '${KPO_NAMESPACE}', request.principal.service_account = '${KPO_SA}', request.principal.cluster_id = '${CLUSTER_ID}'"

STATEMENTS_WI=$(cat <<EOF
[
  "Allow any-user to manage instance-family in compartment ${COMPARTMENT_NAME} where all { ${WI} }",
  "Allow any-user to manage volumes in compartment ${COMPARTMENT_NAME} where all { ${WI} }",
  "Allow any-user to manage volume-attachments in compartment ${COMPARTMENT_NAME} where all { ${WI} }",
  "Allow any-user to manage virtual-network-family in compartment ${COMPARTMENT_NAME} where all { ${WI} }",
  "Allow any-user to inspect compartments in compartment ${COMPARTMENT_NAME} where all { ${WI} }"
]
EOF
)

EXISTING_WI=$(oci iam policy list \
  --compartment-id "${TENANCY_ID}" \
  --profile "${PROFILE}" \
  --query "data[?name=='${POLICY_WORKLOAD_NAME}'].id | [0]" \
  --raw-output 2>/dev/null || echo "")

if [ -n "${EXISTING_WI}" ] && [ "${EXISTING_WI}" != "null" ]; then
  echo "    Policy ${POLICY_WORKLOAD_NAME} ja existe. Atualizando..."
  oci iam policy update --policy-id "${EXISTING_WI}" \
    --statements "${STATEMENTS_WI}" --version-date "" \
    --profile "${PROFILE}" --force > /dev/null
else
  oci iam policy create \
    --compartment-id "${TENANCY_ID}" \
    --name "${POLICY_WORKLOAD_NAME}" \
    --description "Workload Identity policy para o controller KPO no cluster ${CLUSTER_ID}" \
    --statements "${STATEMENTS_WI}" \
    --profile "${PROFILE}" > /dev/null
  echo "    Policy criada: ${POLICY_WORKLOAD_NAME}"
fi

# ============================================================
# PARTE 2: Dynamic Group + Policy para registro dos nos no cluster
# Os nos provisionados pelo KPO precisam de permissao CLUSTER_JOIN
# para ingressar no cluster OKE.
# ============================================================
echo ""
echo "==> [2/2] Criando Dynamic Group e Policy para CLUSTER_JOIN dos nos..."

EXISTING_DG=$(oci iam dynamic-group list \
  --compartment-id "${TENANCY_ID}" \
  --profile "${PROFILE}" \
  --query "data[?name=='${DG_NAME}'].id | [0]" \
  --raw-output 2>/dev/null || echo "")

if [ -n "${EXISTING_DG}" ] && [ "${EXISTING_DG}" != "null" ]; then
  echo "    Dynamic Group ${DG_NAME} ja existe. Pulando criacao."
else
  oci iam dynamic-group create \
    --compartment-id "${TENANCY_ID}" \
    --name "${DG_NAME}" \
    --description "Nos provisionados pelo KPO no compartment ${COMPARTMENT_NAME}" \
    --matching-rule "ALL {instance.compartment.id = '${COMPARTMENT_ID}'}" \
    --profile "${PROFILE}" > /dev/null
  echo "    Dynamic Group criado: ${DG_NAME}"
fi

# Policy que permite aos nos KPO se registrarem no cluster (CLUSTER_JOIN)
STATEMENTS_NODES=$(cat <<EOF
[
  "Allow dynamic-group ${DG_NAME} to {CLUSTER_JOIN} in compartment ${COMPARTMENT_NAME} where target.cluster.id = '${CLUSTER_ID}'"
]
EOF
)

EXISTING_NODES_POLICY=$(oci iam policy list \
  --compartment-id "${TENANCY_ID}" \
  --profile "${PROFILE}" \
  --query "data[?name=='${POLICY_NODES_NAME}'].id | [0]" \
  --raw-output 2>/dev/null || echo "")

if [ -n "${EXISTING_NODES_POLICY}" ] && [ "${EXISTING_NODES_POLICY}" != "null" ]; then
  echo "    Policy ${POLICY_NODES_NAME} ja existe. Atualizando..."
  oci iam policy update --policy-id "${EXISTING_NODES_POLICY}" \
    --statements "${STATEMENTS_NODES}" --version-date "" \
    --profile "${PROFILE}" --force > /dev/null
else
  oci iam policy create \
    --compartment-id "${TENANCY_ID}" \
    --name "${POLICY_NODES_NAME}" \
    --description "Permite que nos KPO se registrem no cluster ${CLUSTER_ID}" \
    --statements "${STATEMENTS_NODES}" \
    --profile "${PROFILE}" > /dev/null
  echo "    Policy criada: ${POLICY_NODES_NAME}"
fi

echo ""
echo "==> Concluido!"
echo ""
echo "    Policy Workload Identity : ${POLICY_WORKLOAD_NAME}"
echo "    Dynamic Group (nos)      : ${DG_NAME}"
echo "    Policy CLUSTER_JOIN      : ${POLICY_NODES_NAME}"
echo ""
echo "    Proximo passo: obter IP privado do apiserver e instalar KPO via Helm"
