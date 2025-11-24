#!/bin/bash


echo "Installing AWS CLI..."
/databricks/python/bin/pip install -q awscli
echo "AWS CLI installed."

echo "Getting Cassandra credentials at $(date '+%Y-%m-%dT%T.%zZ')"
export VAULT_FORMAT="json"

if [ $ENVIRONMENT == "forno" ]; then
  echo "Getting credentials for forno"

  # Setting up important Vault variables
  vault_addr="https://vault-sandbox.sre.quintoandar.com.br"
  payload='{"role_id":"e8723cdc-d37f-2769-7e57-0fbf9f63617f","secret_id":"'$VAULT_SECRET'"}'
  resp=$(curl -s --request POST --data $payload $vault_addr/v1/auth/approle/login)
  vault_token=$(echo $resp | sed -n 's/.*"client_token":"\([^"]*\)".*/\1/p')

  # Getting Cassandra dynamic credentials
  cassandra_credentials=$(curl --header "X-Vault-Token: $vault_token" $vault_addr/v1/database/creds/forno-all-wonka)
  cassandra_lease_id=$(echo $cassandra_credentials | grep -o '"lease_id": *"[^"]*"' | cut -d'"' -f4)
  curl --header "X-Vault-Token: $vault_token" --request POST --data '{"lease_id":"'$cassandra_lease_id'","increment":"20h"}' "$vault_addr/v1/sys/leases/renew"

  cassandra_username=$(echo $cassandra_credentials | grep -o '"username": *"[^"]*"' | cut -d'"' -f4)
  cassandra_password=$(echo $cassandra_credentials | grep -o '"password": *"[^"]*"' | cut -d'"' -f4)

  # Getting static Confluent credentials
  confluent_credentials=$(curl --header "X-Vault-Token: $vault_token" "$vault_addr/v1/kv/data/apps/forno/wonka/confluent/serviceaccounts/confluent_key")
  confluent_key=$(echo "$confluent_credentials" | grep -o '"key": *"[^"]*"' | cut -d'"' -f4)
  confluent_secret=$(echo "$confluent_credentials" | grep -o '"secret": *"[^"]*"' | cut -d'"' -f4)

  sudo echo KAFKA_API_KEY=$confluent_key >> /etc/environment
  sudo echo KAFKA_API_SECRET=$confluent_secret >> /etc/environment

else
  echo "Getting credentials for prod"

  vault_addr="https://vault.sre.quintoandar.com.br"
  payload='{"role_id":"3b8f695a-d0e5-f2f0-bc1e-261aa326ad27","secret_id":"'$VAULT_SECRET'"}'
  resp=$(curl -s --request POST --data $payload $vault_addr/v1/auth/approle/login)
  vault_token=$(echo $resp | sed -n 's/.*"client_token":"\([^"]*\)".*/\1/p')

  cassandra_credentials=$(curl --header "X-Vault-Token: $vault_token" $vault_addr/v1/kv/data/apps/prod/wonka/cassandra-all)
  cassandra_username=$(echo "$cassandra_credentials" | grep -o '"username": *"[^"]*"' | cut -d'"' -f4)
  cassandra_password=$(echo "$cassandra_credentials" | grep -o '"password": *"[^"]*"' | cut -d'"' -f4)  

  confluent_credentials=$(curl --header "X-Vault-Token: $vault_token" $vault_addr/v1/kv/data/apps/prod/wonka/confluent/serviceaccounts/confluent_key)
  confluent_key=$(echo "$confluent_credentials" | grep -o '"key": *"[^"]*"' | cut -d'"' -f4)
  confluent_secret=$(echo "$confluent_credentials" | grep -o '"secret": *"[^"]*"' | cut -d'"' -f4)

  sudo echo KAFKA_API_KEY=$confluent_key >> /etc/environment
  sudo echo KAFKA_API_SECRET=$confluent_secret >> /etc/environment
fi

sudo echo CASSANDRA_USERNAME=$cassandra_username >> /etc/environment
sudo echo CASSANDRA_PASSWORD=$cassandra_password >> /etc/environment
