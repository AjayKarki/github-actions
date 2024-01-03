#!/bin/bash

set -xe 

VAULT_TOKEN=$VAULT_TOKEN
VAULT_SERVER=$VAULT_SERVER
VAULT_SECRET_PATH=$VAULT_SECRET_PATH
VAULT_SECRET_COMMON_PATH=$VAULT_SECRET_COMMON_PATH

echo "Extracting variables from Vault..."
curl -H "X-Vault-Token: ${VAULT_TOKEN}" https://${VAULT_SERVER}/v1/${VAULT_SECRET_PATH} | jq -r .data > .env.json
curl -H "X-Vault-Token: ${VAULT_TOKEN}" https://${VAULT_SERVER}/v1/${VAULT_SECRET_COMMON_PATH} | jq -r .data >> .env.json
cat .env.json | jq -r 'to_entries[] | "\(.key)=\(.value)"' > .env && cp .env ./app

echo "Generating manager docker compose"
echo "Current directory: $(pwd)"
cd $(pwd)/../ansible/
ansible-playbook -i inventory manager.yml