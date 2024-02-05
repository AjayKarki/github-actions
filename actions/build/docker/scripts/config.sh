#!/bin/bash

set -xe

HARBOR_ENDPOINT="https://${IMAGE_REPOSITORY}/api/v2.0"
CREATE_PROJECT_ENDPOINT="$HARBOR_ENDPOINT/projects"
GET_PROJECT_ENDPOINT="$HARBOR_ENDPOINT/projects?page=1&page_size=50&public=false&with_detail=false"
RETENTATION_ENPOINT="$HARBOR_ENDPOINT/retentions"
VAULT_TOKEN=$VAULT_TOKEN
VAULT_SERVER=$VAULT_SERVER
VAULT_PATH=$VAULT_SECRETS_CICD_PATH
PROJECT_NAME=$(echo $VAULT_SECRET_PATH | awk -F '/' '{print $1}')
# Pull registry credentials from Vault 
USERNAME=$(curl -H "X-Vault-Token: ${VAULT_TOKEN}" "https://${VAULT_SERVER}/v1/${VAULT_PATH}" | jq -r .data.KCR_USER)
PASSWORD=$(curl -H "X-Vault-Token: ${VAULT_TOKEN}" "https://${VAULT_SERVER}/v1/${VAULT_PATH}" | jq -r .data.KCR_PASSWORD)
# Function to list existing projects
list_projects() {
    RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" "$GET_PROJECT_ENDPOINT")
    if [ $? -eq 0 ]; then
        echo "$RESPONSE" | jq -r '.[] | "\(.name)"'
    else
        echo "Failed to fetch projects $RESPONSE" &> /dev/null
        return 0
    fi
}

# Create Project
create_project() {
    NEW_PROJECT="$1"
    PROJECT_LIST=$(list_projects)
    for project in $PROJECT_LIST; do
        if [ "$NEW_PROJECT" == "$project" ]; then
            echo "Project already exists" &> /dev/null
            return 0
        fi
    done

    RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" -H "Content-Type: application/json" "$CREATE_PROJECT_ENDPOINT" -d "{\"project_name\":\"$NEW_PROJECT\",\"metadata\":{\"public\":\"false\"}}")
    
    if [ $? -eq 0 ]; then
        echo "Project with name: $NEW_PROJECT created"
    else
        echo "Failed to create project $NEW_PROJECT. Status code: $?"
        echo "RESPONSE: $RESPONSE"
    fi
}

# Function to get project id
get_project_id() {
    project_endpoint="$CREATE_PROJECT_ENDPOINT/$NEW_PROJECT"
    RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" "$project_endpoint")
    if [ $? -eq 0 ]; then
        echo "$RESPONSE" | jq -r '.project_id'
    else
        echo "Failed to fetch project id $RESPONSE"
        return 0
    fi
}

create_retention_policy() {
    project_ref=$(get_project_id)
    # Retention policy payload
    local payload='{
        "algorithm": "or",
        "id": 1,
        "rules": [
            {
                "action": "retain",
                "params": {
                    "latestPushedK": 10
                },
                "scope_selectors": {
                    "repository": [
                        {
                            "decoration": "repoMatches",
                            "kind": "doublestar",
                            "pattern": "**"
                        }
                    ]
                },
                "tag_selectors": [
                    {
                        "decoration": "matches",
                        "extras": "{\"untagged\":true}",
                        "kind": "doublestar",
                        "pattern": "**"
                    }
                ],
                "template": "latestPushedK"
            }
        ],
        "scope": {
            "level": "project",
            "ref": '$project_ref'
        },
        "trigger": {
            "kind": "Schedule",
            "settings": {
              "cron": "0 0 0 * * *"  
            }
        }
    }'

    # Send POST request
    local RESPONSE=$(curl  --write-out %{http_code} --silent --output /dev/null -s -u "$USERNAME:$PASSWORD" -H "Content-Type: application/json" "$RETENTATION_ENPOINT" -d "$payload")

    if [ $RESPONSE -eq 201 ]; then
        echo "Retention policy created successfully"
    else
        echo "Retention policy already exists" &> /dev/null 

    fi
}

create_project "$PROJECT_NAME"
create_retention_policy