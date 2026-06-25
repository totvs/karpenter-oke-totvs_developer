# Gestão Inteligente de Nós com Karpenter no Kubernetes

> Conteúdo técnico produzido para o **TOTVS Developer** — plataforma de conhecimento e comunidade de desenvolvedores da TOTVS.

Este repositório contém toda a infraestrutura e configuração necessária para demonstrar a **gestão inteligente de nós** em um cluster Kubernetes no Oracle Cloud Infrastructure (OCI), utilizando o [Karpenter Provider for OCI (KPO)](https://docs.oracle.com/iaas/Content/ContEng/Tasks/contengusingkarpenter.htm) sobre o serviço **OKE (Oracle Kubernetes Engine)**.

---

## Sobre o projeto

O Karpenter é um autoscaler de nós de nova geração para Kubernetes. Ao contrário do Cluster Autoscaler tradicional — que escala grupos de nós inteiros com shapes fixos —, o Karpenter provisiona **nós individuais sob medida**, escolhendo o shape ideal para cada workload e removendo nós ociosos automaticamente.

Este projeto demonstra na prática:

- Provisionamento de cluster OKE via **Terraform** (módulo oficial Oracle)
- Instalação do **Karpenter Provider for OCI** via Helm
- Configuração de **IAM** com Workload Identity para o controller do Karpenter
- Definição de `OciNodeClass` e múltiplos `NodePool` (system, app e batch)
- Teste de escalonamento automático com workload de carga

---

## Pré-requisitos

| Ferramenta | Versão mínima |
|---|---|
| Terraform | >= 1.6 |
| OCI CLI | >= 3.x |
| kubectl | >= 1.32 |
| Helm | >= 3.12 |
| Conta OCI | Com permissões de criação de recursos em um compartment |

---

## Estrutura do repositório

```
cluster-oke/
├── main.tf                     # Módulo OKE (VCN, subnets, NSGs, node pool)
├── variables.tf                # Declaração de todas as variáveis
├── outputs.tf                  # Outputs do módulo OKE (subnet IDs, NSG IDs)
├── backend.tf                  # Configuração de backend Terraform
├── ssh_local.tf                # Leitura local da chave SSH pública
├── terraform.tfvars.example    # Exemplo de valores — NÃO commitar o .tfvars real
└── karpenter/
    ├── README.md               # Guia detalhado de instalação do KPO
    ├── iam-policies.sh         # Script para criar Dynamic Group e IAM Policies
    ├── validate.sh             # Validação pós-instalação
    ├── helm/
    │   ├── values.yaml.example # Template de values — NÃO commitar o values.yaml real
    │   └── values.yaml         # (gitignored) valores reais preenchidos localmente
    └── manifests/
        ├── 00-namespace-rbac.yaml   # Namespace karpenter + RBAC
        ├── 01-nodeclass.yaml        # OciNodeClass (shape, imagem, subnet, NSG)
        ├── 02-nodepool-system.yaml  # NodePool para workloads de sistema
        ├── 03-nodepool-app.yaml     # NodePool para workloads de aplicação
        ├── 04-nodepool-batch.yaml   # NodePool para workloads batch/spot
        └── 05-test-workload.yaml    # Deployment de teste para disparar scale-up
```

---

## Como usar

### 1. Provisionar a infraestrutura OKE

Clone o repositório e configure suas variáveis:

```bash
# Copie o arquivo de exemplo e preencha com seus valores
cp terraform.tfvars.example terraform.tfvars
```

> **Atenção:** o arquivo `terraform.tfvars` contém credenciais sensíveis e está listado no `.gitignore`. Nunca o commite.

Inicialize e aplique o Terraform:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Após o apply, colete os IDs necessários para o Karpenter:

```bash
terraform output oke_subnet_ids   # ID da subnet "workers"
terraform output oke_nsg_ids      # ID do NSG "workers"
```

### 2. Configurar o kubeconfig

```bash
oci ce cluster create-kubeconfig \
  --cluster-id <CLUSTER_OCID> \
  --file ~/.kube/config \
  --region sa-saopaulo-1 \
  --token-version 2.0.0 \
  --profile <SEU_PERFIL_OCI>
```

### 3. Criar as IAM Policies

O script `iam-policies.sh` cria o Dynamic Group e as Policies necessárias para o Workload Identity do controller e para o `CLUSTER_JOIN` dos nós provisionados.

Exporte as variáveis obrigatórias antes de executar:

```bash
export TENANCY_ID="ocid1.tenancy.oc1..XXXXXXXX"
export COMPARTMENT_ID="ocid1.compartment.oc1..XXXXXXXX"
export CLUSTER_ID="ocid1.cluster.oc1.<regiao>.XXXXXXXX"
export COMPARTMENT_NAME="<nome-do-compartment>"   # ex: devops
export OCI_CLI_PROFILE="<perfil-oci-cli>"
```

> Para obter o `COMPARTMENT_NAME` pelo OCID:
> ```bash
> oci iam compartment get --compartment-id $COMPARTMENT_ID \
>   --profile $OCI_CLI_PROFILE --query 'data.name' --raw-output
> ```

```bash
cd karpenter
chmod +x iam-policies.sh
./iam-policies.sh
```

### 4. Instalar o Karpenter via Helm

Antes de instalar, preencha o arquivo de values com os dados do seu ambiente:

```bash
cp karpenter/helm/values.yaml.example karpenter/helm/values.yaml
# Edite values.yaml preenchendo: OCI_REGION, clusterCompartmentId,
# vcnCompartmentId e apiserverEndpoint (IP privado do apiserver)
```

> O IP privado do apiserver pode ser obtido com:
> ```bash
> oci ce cluster get --cluster-id <CLUSTER_OCID> --profile <PERFIL> \
>   --query 'data.endpoints."private-endpoint"' --raw-output
> ```

> **Atenção:** `karpenter/helm/values.yaml` contém OCIDs e IPs reais e está no `.gitignore`. Nunca o commite.

```bash
helm repo add karpenter-provider-oci https://oracle.github.io/karpenter-provider-oci/charts
helm repo update

helm install karpenter karpenter-provider-oci/karpenter \
  --version 0.2.0 \
  --namespace karpenter \
  --create-namespace \
  --values karpenter/helm/values.yaml
```

Verifique se o controller subiu:

```bash
kubectl -n karpenter get pods
kubectl -n karpenter logs -l app.kubernetes.io/name=karpenter --follow
```

### 5. Aplicar os manifests

```bash
kubectl apply -f karpenter/manifests/00-namespace-rbac.yaml
kubectl apply -f karpenter/manifests/01-nodeclass.yaml
kubectl apply -f karpenter/manifests/02-nodepool-system.yaml
kubectl apply -f karpenter/manifests/03-nodepool-app.yaml
kubectl apply -f karpenter/manifests/04-nodepool-batch.yaml
```

Verifique o status:

```bash
kubectl get ocinodeclass
kubectl get nodepools
```

### 6. Testar o escalonamento automático

```bash
# Aplicar o workload de teste
kubectl apply -f karpenter/manifests/05-test-workload.yaml

# Escalar para forçar o provisionamento de novos nós
kubectl -n karpenter-test scale deployment inflate --replicas=10

# Acompanhar nós sendo criados em tempo real
kubectl get nodes -w

# Acompanhar os logs do Karpenter
kubectl -n karpenter logs -l app.kubernetes.io/name=karpenter -f

# Remover o workload — nós ociosos serão desalocados automaticamente
kubectl -n karpenter-test scale deployment inflate --replicas=0
```

---

## Karpenter vs Cluster Autoscaler

| Característica | Cluster Autoscaler (OKE Node Pool) | Karpenter (KPO) |
|---|---|---|
| **Unidade de escala** | Node Group / Node Pool inteiro | Nó individual sob medida |
| **Shape do nó** | Fixo — definido no Node Pool | Dinâmico — escolhe o melhor shape para o workload |
| **Velocidade de scale up** | ~3–5 min | ~1–2 min (lança instância diretamente) |
| **Bin packing** | Não | Sim — consolida pods no menor número de nós |
| **Scale down** | Baseado em utilização média do grupo | Por nó: remove individualmente quando ocioso |
| **Configuração** | Node Pool via Console/Terraform | `OciNodeClass` + `NodePool` YAML no cluster |

---

## Referências

- [Documentação oficial Oracle — Karpenter no OKE](https://docs.oracle.com/iaas/Content/ContEng/Tasks/contengusingkarpenter.htm)
- [Repositório do Karpenter Provider for OCI](https://github.com/oracle-cne/karpenter-provider-oci)
- [Módulo Terraform OKE (oracle-terraform-modules)](https://registry.terraform.io/modules/oracle-terraform-modules/oke/oci/latest)
- [Karpenter (projeto original)](https://karpenter.sh)
- [TOTVS Developer](https://developer.totvs.com.br)

---

> Produzido por **TOTVS** para o programa **TOTVS Developer**.
