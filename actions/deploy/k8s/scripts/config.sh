#!/bin/bash

export KUBECONFIG=kubeconfig.yaml

function configmap() {
  LOCAL_SETTINGS_NAME=$1
  if kubectl get configmaps app-local-settings --namespace=${{env.PROJECT_NAME}} &> /dev/null; then
    kubectl delete configmap app-local-settings --namespace=${{env.PROJECT_NAME }}
    kubectl create configmap app-local-settings --from-file=${LOCAL_SETTINGS_NAME} --namespace=${{env.PROJECT_NAME}}
  else
    kubectl create configmap app-local-settings --from-file=${LOCAL_SETTINGS_NAME} --namespace=${{env.PROJECT_NAME}}
  fi
}

if [ "${{ inputs.LOCAL_SETTINGS }}" == "true" ]; then
  curl -H "PRIVATE-TOKEN: ${{ env.GITLAB_TOKEN }}" "${{ env.GITLAB_SERVER }}/api/v4/projects/${{ env.GITLAB_PROJECT_NUMBER }}/repository/files/${{env.ENVIRONMENT}}%2F${{ env.LOCAL_SETTINGS_NAME }}/raw?ref=main" -o ${{ env.LOCAL_SETTINGS_NAME }}
  configmap ${{ env.LOCAL_SETTINGS_NAME }}
elif [ "${{ inputs.LOCAL_SETTINGS }}" == "false" ]; then
  echo "Dummy Settings" settings.txt
  configmap settings.txt
fi

curl -H "X-Vault-Token: ${{ inputs.VAULT_TOKEN }}" https://${{ inputs.VAULT_SERVER }}/v1/${{ inputs.VAULT_SECRET_PATH }} | jq -r .data > .env.json
curl -H "X-Vault-Token: ${{ inputs.VAULT_TOKEN }}" https://${{ inputs.VAULT_SERVER }}/v1/${{ inputs.VAULT_SECRET_COMMON_PATH }} | jq -r .data > .common.env.json
cat .env.json | jq -r 'to_entries[] | "\(.key)=\(.value)"' | base64 > secrets
cat .common.env.json | jq -r 'to_entries[] | "\(.key)=\(.value)"' | base64 >> secrets

if kubectl get secret app-secret --namespace=${{ env.PROJECT_NAME }} &> /dev/null; then
  kubectl delete secret app-secret --namespace=${{env.PROJECT_NAME}}
  kubectl create secret generic app-secret --from-file=secrets --namespace=${{env.PROJECT_NAME}}
else
  kubectl create secret generic app-secret --from-file=secrets --namespace=${{env.PROJECT_NAME}}
fi