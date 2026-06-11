#!/bin/bash
# Script to retrieve credentials from Vault for Wonka DAGs
# Supports both forno and prod environments

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Databricks: ENVIRONMENT and VAULT_SECRET via spark_env_vars.
# EMR bootstrap: $1 = environment ("forno" or "prod"), $2 = Vault AppRole secret ID.

ENVIRONMENT="${1:-${ENVIRONMENT:-}}"
VAULT_SECRET="${2:-${VAULT_SECRET:-}}"

if [[ -z "${ENVIRONMENT}" ]]; then
    echo "ERROR: ENVIRONMENT is required (env var or bootstrap \$1)" >&2
    exit 1
fi

if [[ -z "${VAULT_SECRET:-}" ]]; then
    echo "ERROR: VAULT_SECRET variable is required (env var or bootstrap \$2)" >&2
    exit 1
fi

# Environment-specific configuration
declare -A VAULT_CONFIG=(
    [forno_addr]="https://vault-sandbox.sre.quintoandar.com.br"
    [forno_role_id]="e8723cdc-d37f-2769-7e57-0fbf9f63617f"
    [prod_addr]="https://vault.sre.quintoandar.com.br"
    [prod_role_id]="3b8f695a-d0e5-f2f0-bc1e-261aa326ad27"
)

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# Extract JSON value using grep/sed (simple JSON parser for basic structures)
json_extract() {
    local json=$1
    local key=$2

    # Use grep to find the key and extract its value
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Check if JSON response contains errors
json_has_errors() {
    local json=$1
    echo "$json" | grep -q '"errors"'
}

# Extract error message from JSON response
json_get_error() {
    local json=$1
    local error_msg
    error_msg=$(echo "$json" | grep -o '"errors"[[:space:]]*:[[:space:]]*\[[^]]*\]' | sed 's/.*"errors"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/' | sed 's/"//g')
    echo "${error_msg:-Unknown error}"
}

# Create JSON payload for login
create_login_payload() {
    local role_id=$1
    local secret_id=$2
    echo "{\"role_id\":\"$role_id\",\"secret_id\":\"$secret_id\"}"
}

# Create JSON payload for lease renewal
create_renew_payload() {
    local lease_id=$1
    local increment=$2
    echo "{\"lease_id\":\"$lease_id\",\"increment\":\"$increment\"}"
}

# Login to Vault using AppRole and return token
vault_login() {
    local vault_addr=$1
    local role_id=$2
    local secret_id=$3

    local payload
    payload=$(create_login_payload "$role_id" "$secret_id")

    local response
    response=$(curl -s --request POST \
        --data "$payload" \
        --header "Content-Type: application/json" \
        "$vault_addr/v1/auth/approle/login")

    # Check if login was successful
    if json_has_errors "$response"; then
        error "Failed to login to Vault: $(json_get_error "$response")"
    fi

    # Extract client token
    local client_token
    client_token=$(json_extract "$response" "client_token")

    if [[ -z "$client_token" ]]; then
        error "Failed to extract client token from Vault response"
    fi

    echo "$client_token"
}

# Get JSON data from Vault KV store
vault_get_kv() {
    local vault_addr=$1
    local vault_token=$2
    local path=$3

    local response
    response=$(curl -s \
        --header "X-Vault-Token: $vault_token" \
        --header "Content-Type: application/json" \
        "$vault_addr/v1/kv/data/$path")

    # Check if request was successful
    if json_has_errors "$response"; then
        error "Failed to get data from Vault path $path: $(json_get_error "$response")"
    fi

    echo "$response"
}

# Get dynamic database credentials from Vault
vault_get_db_creds() {
    local vault_addr=$1
    local vault_token=$2
    local role=$3

    local response
    response=$(curl -s \
        --header "X-Vault-Token: $vault_token" \
        --header "Content-Type: application/json" \
        "$vault_addr/v1/database/creds/$role")

    # Check if request was successful
    if json_has_errors "$response"; then
        error "Failed to get database credentials: $(json_get_error "$response")"
    fi

    echo "$response"
}

# Renew lease for dynamic credentials
vault_renew_lease() {
    local vault_addr=$1
    local vault_token=$2
    local lease_id=$3
    local increment=${4:-"20h"}

    local payload
    payload=$(create_renew_payload "$lease_id" "$increment")

    local response
    response=$(curl -s --request POST \
        --data "$payload" \
        --header "X-Vault-Token: $vault_token" \
        --header "Content-Type: application/json" \
        "$vault_addr/v1/sys/leases/renew")

    if [[ $? -ne 0 ]]; then
        log "Warning: Failed to renew lease $lease_id"
    else
        log "Successfully renewed lease $lease_id for $increment"
    fi
}

# Save credential to /etc/environment
save_to_environment() {
    local key=$1
    local value=$2

    sudo sh -c "echo '$key=$value' >> /etc/environment"
    log "Saved $key to environment"
}

# =============================================================================
# Main Script
# =============================================================================

log "Starting credential retrieval process"
export VAULT_FORMAT="json"

# Determine environment configuration
case $ENVIRONMENT in
    forno)
        vault_addr=${VAULT_CONFIG[forno_addr]}
        role_id=${VAULT_CONFIG[forno_role_id]}
        ;;
    prod)
        vault_addr=${VAULT_CONFIG[prod_addr]}
        role_id=${VAULT_CONFIG[prod_role_id]}
        ;;
    *)
        error "Unsupported environment: $ENVIRONMENT. Must be 'forno' or 'prod'"
        ;;
esac

log "Retrieving credentials for $ENVIRONMENT environment"

# Authenticate with Vault
log "Authenticating with Vault..."
vault_token=$(vault_login "$vault_addr" "$role_id" "$VAULT_SECRET")
log "Successfully authenticated with Vault"

# Get Confluent Kafka credentials
log "Retrieving Confluent Kafka credentials..."
confluent_data=$(vault_get_kv "$vault_addr" "$vault_token" "apps/$ENVIRONMENT/wonka/confluent/serviceaccounts/confluent_key")

confluent_key=$(json_extract "$confluent_data" "key")
confluent_secret=$(json_extract "$confluent_data" "secret")

# Get Schema Registry credentials
log "Retrieving Schema Registry credentials..."
schema_registry_data=$(vault_get_kv "$vault_addr" "$vault_token" "apps/$ENVIRONMENT/wonka/confluent/serviceaccounts/schema_registry_key")

schema_registry_key=$(json_extract "$schema_registry_data" "key")
schema_registry_secret=$(json_extract "$schema_registry_data" "secret")

# Save all credentials to environment
log "Saving credentials to /etc/environment..."
save_to_environment "KAFKA_API_KEY" "$confluent_key"
save_to_environment "KAFKA_API_SECRET" "$confluent_secret"
save_to_environment "CDF_TO_KAFKA_SCHEMA_REGISTRY_KEY" "$schema_registry_key"
save_to_environment "CDF_TO_KAFKA_SCHEMA_REGISTRY_SECRET" "$schema_registry_secret"

log "Credential retrieval completed successfully"
