#!/bin/bash
#===============================================================================
# SIC_Cloud_Security.sh — SIC Cloud Security Assessment Module
#
# Usage:
#   CLOUD_PROVIDER=aws ./SIC_Cloud_Security.sh "audit AWS production"
#   CLOUD_PROVIDER=gcp ./SIC_Cloud_Security.sh "scan GCP IAM"
#   CLOUD_PROVIDER=azure ./SIC_Cloud_Security.sh "check Azure NSGs"
#
# Environment:
#   CLOUD_PROVIDER  — aws|gcp|azure (auto-detected if SDK credentials configured)
#   AWS_PROFILE     — AWS CLI profile
#   AWS_REGION      — AWS region (default: us-east-1)
#   GOOGLE_APPLICATION_CREDENTIALS — GCP SA key path
#   AZURE_TENANT, AZURE_CLIENT, AZURE_SECRET — Azure SP
#
# Part of the SIC platform.
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"
sic_check_version 1 3

sic_register_module \
    --name "SIC_Cloud_Security" \
    --tools "aws, gcloud, az, python3, curl, jq" \
    --danger 'rm -rf /|mkfs|dd of=/dev/sd|>/dev/sda' \
    --plan \
        "1. Enumerate cloud assets and configurations" \
        "2. Identify misconfigured permissions and public exposure" \
        "3. Check for common cloud security misconfigurations"

# ─────────────────────────────────────────
# sic_run_module_suite() — Cloud audit engine
# ─────────────────────────────────────────
sic_run_module_suite() {
    local target="$1" tmp_dir="$2" visa_cfg="$3"
    sic_parse_visa_cfg "$visa_cfg"
    local provider="${CLOUD_PROVIDER:-}"
    mkdir -p "$tmp_dir/vuln"

    echo ""
    echo -e "${PURPLE}☁  CLOUD SECURITY AUDIT: $target${NC}"

    # ── Auto-detect provider ──
    if [[ -z "$provider" ]]; then
        if command -v aws &>/dev/null && timeout 5 aws sts get-caller-identity 2>/dev/null; then
            provider="aws"
        elif command -v gcloud &>/dev/null && timeout 5 gcloud auth list 2>/dev/null | grep -q ACTIVE; then
            provider="gcp"
        elif command -v az &>/dev/null && timeout 5 az account show 2>/dev/null; then
            provider="azure"
        else
            echo -e "${YELLOW}  [!] No cloud provider detected. Set CLOUD_PROVIDER or configure creds.${NC}"
            echo -e "${YELLOW}      aws:   export AWS_PROFILE=default && aws sts get-caller-identity${NC}"
            echo -e "${YELLOW}      gcp:   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json${NC}"
            echo -e "${YELLOW}      azure: az login or set AZURE_TENANT/CLIENT/SECRET${NC}"
            return
        fi
    fi

    echo -e "${GREEN}  Provider: ${provider^^} | Target: $target${NC}"

    case "${provider,,}" in
        aws)   cloud_audit_aws "$target" "$tmp_dir" ;;
        gcp)   cloud_audit_gcp "$target" "$tmp_dir" ;;
        azure) cloud_audit_azure "$target" "$tmp_dir" ;;
        *)     echo -e "${RED}  [!] Unknown provider: $provider (use aws|gcp|azure)${NC}" ;;
    esac

    echo -e "${GREEN}  ✅ Cloud audit complete — results in $tmp_dir/vuln/${provider,,}/${NC}"
}

# ── AWS ──
cloud_audit_aws() {
    local target="$1" tmp_dir="$2"
    local out="$tmp_dir/vuln/aws"
    mkdir -p "$out"

    echo -e "${CYAN}  [1/6] S3 bucket enumeration...${NC}"
    aws s3api list-buckets --query "Buckets[].Name" --output json 2>/dev/null > "$out/s3_buckets.json" || echo '[]' > "$out/s3_buckets.json"
    while IFS= read -r bucket; do
        [[ -z "$bucket" || "$bucket" == "[]" ]] && continue
        aws s3api get-bucket-acl --bucket "$bucket" 2>/dev/null | jq '{bucket: "'$bucket'", public: [.Grants[]? | select(.Grantee.URI | contains("AllUsers") or contains("AuthenticatedUsers"))]}' >> "$out/s3_public.json" 2>/dev/null || true
    done < <(jq -r '.[]' "$out/s3_buckets.json" 2>/dev/null)
    echo -e "${GREEN}     Buckets: $(jq length "$out/s3_buckets.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [2/6] IAM credential report...${NC}"
    aws iam generate-credential-report 2>/dev/null || true
    aws iam get-credential-report --query 'Content' --output text 2>/dev/null | base64 -d > "$out/iam_report.csv" 2>/dev/null || true
    echo -e "${GREEN}     IAM users: $(tail -n +2 "$out/iam_report.csv" 2>/dev/null | wc -l)${NC}"

    echo -e "${CYAN}  [3/6] Security Groups (0.0.0.0/0)...${NC}"
    aws ec2 describe-security-groups --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]]" --output json > "$out/public_sgs.json" 2>/dev/null || echo '[]' > "$out/public_sgs.json"
    echo -e "${GREEN}     Public SGs: $(jq length "$out/public_sgs.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [4/6] ELB exposure...${NC}"
    aws elbv2 describe-load-balancers --query "LoadBalancers[?Scheme=='internet-facing'].DNSName" --output json > "$out/elb_public.json" 2>/dev/null || echo '[]' > "$out/elb_public.json"
    echo -e "${GREEN}     Public ALBs: $(jq length "$out/elb_public.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [5/6] GuardDuty status...${NC}"
    local gd; gd=$(aws guardduty list-detectors --query "DetectorIds" --output json 2>/dev/null || echo '[]')
    echo "$gd" > "$out/guardduty.json"
    [[ "$(jq length "$out/guardduty.json" 2>/dev/null)" -gt 0 ]] && echo -e "${GREEN}     GuardDuty: ENABLED${NC}" || echo -e "${YELLOW}     GuardDuty: NOT ENABLED${NC}"

    echo -e "${CYAN}  [6/6] CloudTrail...${NC}"
    aws cloudtrail describe-trails --query "trailList[].Name" --output json > "$out/cloudtrail.json" 2>/dev/null || echo '[]' > "$out/cloudtrail.json"
    echo -e "${GREEN}     Trails: $(jq length "$out/cloudtrail.json" 2>/dev/null || echo 0)${NC}"
}

# ── GCP ──
cloud_audit_gcp() {
    local target="$1" tmp_dir="$2"
    local out="$tmp_dir/vuln/gcp"
    mkdir -p "$out"

    echo -e "${CYAN}  [1/5] GCS buckets...${NC}"
    gcloud storage buckets list --format="json(name,iamConfiguration)" 2>/dev/null > "$out/gcs_buckets.json" || echo '[]' > "$out/gcs_buckets.json"
    echo -e "${GREEN}     Buckets: $(jq length "$out/gcs_buckets.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [2/5] IAM policy...${NC}"
    gcloud projects get-iam-policy "$(gcloud config get-value project 2>/dev/null)" --format=json > "$out/iam_policy.json" 2>/dev/null || echo '{}' > "$out/iam_policy.json"
    echo -e "${GREEN}     Bindings: $(jq '.bindings | length' "$out/iam_policy.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [3/5] Firewall rules (0.0.0.0/0 ingress)...${NC}"
    gcloud compute firewall-rules list --format="json(name,sourceRanges,allowed)" 2>/dev/null > "$out/firewall_rules.json" || echo '[]' > "$out/firewall_rules.json"
    jq '[.[] | select(.sourceRanges[]? == "0.0.0.0/0")]' "$out/firewall_rules.json" > "$out/public_firewalls.json" 2>/dev/null
    echo -e "${GREEN}     Public: $(jq length "$out/public_firewalls.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [4/5] GKE clusters...${NC}"
    gcloud container clusters list --format="json(name,location,masterAuthorizedNetworksConfig)" 2>/dev/null > "$out/gke_clusters.json" || echo '[]' > "$out/gke_clusters.json"
    echo -e "${GREEN}     GKE: $(jq length "$out/gke_clusters.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [5/5] Cloud SQL public IP...${NC}"
    gcloud sql instances list --format="json(name,ipAddresses,settings.ipConfiguration)" 2>/dev/null > "$out/cloudsql.json" || echo '[]' > "$out/cloudsql.json"
    echo -e "${GREEN}     SQL: $(jq length "$out/cloudsql.json" 2>/dev/null || echo 0)${NC}"
}

# ── Azure ──
cloud_audit_azure() {
    local target="$1" tmp_dir="$2"
    local out="$tmp_dir/vuln/azure"
    mkdir -p "$out"

    echo -e "${CYAN}  [1/5] Account info...${NC}"
    az account show --output json 2>/dev/null > "$out/account.json" || echo '{}' > "$out/account.json"

    echo -e "${CYAN}  [2/5] NSG rules (Internet source)...${NC}"
    az network nsg list --query "[?securityRules[?sourceAddressPrefix=='*' || sourceAddressPrefix=='Internet']]" --output json > "$out/public_nsgs.json" 2>/dev/null || echo '[]' > "$out/public_nsgs.json"
    echo -e "${GREEN}     Public NSGs: $(jq length "$out/public_nsgs.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [3/5] Storage public access...${NC}"
    az storage account list --query "[?allowBlobPublicAccess==\`true\`]" --output json > "$out/public_storage.json" 2>/dev/null || echo '[]' > "$out/public_storage.json"

    echo -e "${CYAN}  [4/5] Privileged roles...${NC}"
    az role assignment list --include-inherited --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor']" --output json > "$out/privileged_roles.json" 2>/dev/null || echo '[]' > "$out/privileged_roles.json"
    echo -e "${GREEN}     Privileged: $(jq length "$out/privileged_roles.json" 2>/dev/null || echo 0)${NC}"

    echo -e "${CYAN}  [5/5] Key Vault exposure...${NC}"
    az keyvault list --query "[?properties.networkAcls.defaultAction!='Deny']" --output json > "$out/exposed_vaults.json" 2>/dev/null || echo '[]' > "$out/exposed_vaults.json"
    echo -e "${GREEN}     Exposed vaults: $(jq length "$out/exposed_vaults.json" 2>/dev/null || echo 0)${NC}"
}

sic_run "$@"

