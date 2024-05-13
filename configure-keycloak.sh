
#!/bin/bash

#----# Wait for Keycloak #----#

echo "Waiting for Keycloak to become available..."
until $(curl --output /dev/null --silent --head --fail http://localhost:8080/); do
    printf '.'
    sleep 1
done
echo "Keycloak is ready"

#-----# Retrieve admin token for configuration #----#

KEYCLOAK_URL="http://localhost:8080"
ADMIN_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=password" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')
echo "Admin token creation ran"

#-----# Create a realm #----#

curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -d '{"id": "newrealm", "realm": "newrealm", "enabled": true}'
echo "Realm creation ran"

#-----# Create users #----#

# Instructions: Add users and modify their parameters for customization. By default, the array index is appended to the last name (icluded in email = username) in the following format: 'first.last<index>@COMMON_DOMAIN'.

# Common parameters for all default users (can all be customized)
COMMON_DOMAIN="example.com"
COMMON_FIRST_NAME="first"
COMMON_LAST_NAME="last"
COMMON_PASSWORD="password"

# Customize users as needed
declare -A user_attributes
user_attributes[1]="${COMMON_FIRST_NAME}|${COMMON_LAST_NAME}|${COMMON_DOMAIN}|${COMMON_PASSWORD}"
user_attributes[2]="${COMMON_FIRST_NAME}|${COMMON_LAST_NAME}|${COMMON_DOMAIN}|${COMMON_PASSWORD}"
#user_attributes[3]="Alice|Wonderland|anotherdomain.com|alicepass" # This is a fully customized user example

# Array of user indices
user_keys=("1" "2")  # Add the next index for each extra declared user

# Loop through the user indices to create each user
for user_key in "${user_keys[@]}"; do
    IFS='|' read -r firstName lastName domain password <<< "${user_attributes[$user_key]}"

    # Construct the email address
    email="${firstName,,}.${lastName,,}${user_key}@${domain}"  # Convert to lowercase and add index

    USER_PAYLOAD=$(cat <<EOF
{
  "username": "$email",
  "enabled": true,
  "email": "$email",
  "emailVerified": true,
  "firstName": "$firstName",
  "lastName": "$lastName",
  "credentials": [{
    "type": "password",
    "value": "$password",
    "temporary": false
  }]
}
EOF
    )

    # Create the user
    USER_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/newrealm/users" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -d "$USER_PAYLOAD")
    echo "User creation response for $email: $USER_RESPONSE"  # Add this line to log the response

    # Retrieve the user ID to verify creation
    echo "Retrieving ${firstName}.${lastName}${user_key} ID..."
    USER_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/newrealm/users?briefRepresentation=true&username=$email" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
    #check_value "$USER_ID" "${firstName}.${lastName}${user_key} ID"
done
echo "Users creation ran"

#-----# Create a group #----#

GROUP_PAYLOAD='{"name": "group1"}'
GROUP_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/newrealm/groups" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -d "$GROUP_PAYLOAD")

# Log the group creation attempt
#check_value "$GROUP_RESPONSE" "Group Creation"
echo "Group creation ran"

#----# Assign user to a group #----#

# URL encode the username and fetch user ID
ENCODED_USERNAME=$(echo -n 'first.last1@example.com' | jq -sRr @uri)
USER_JSON=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/newrealm/users?briefRepresentation=true&username=$ENCODED_USERNAME" \
    -H "Authorization: Bearer $ADMIN_TOKEN")
USER_ID=$(echo "$USER_JSON" | jq -r '.[0].id')
echo "User ID for $ENCODED_USERNAME: $USER_ID"

# Fetch group ID for group1
GROUP_JSON=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/newrealm/groups?briefRepresentation=true&search=group1" \
    -H "Authorization: Bearer $ADMIN_TOKEN")
GROUP_ID=$(echo "$GROUP_JSON" | jq -r '.[0].id')
echo "Group ID for group1: $GROUP_ID"

ADD_USER_TO_GROUP_RESPONSE=$(curl -s -X PUT "$KEYCLOAK_URL/admin/realms/newrealm/users/$USER_ID/groups/$GROUP_ID" \
    -H "Authorization: Bearer $ADMIN_TOKEN")
# Log the attempt to add a user to a group
#check_value "$ADD_USER_TO_GROUP_RESPONSE" "Adding User to Group"
echo "Add $USER_ID to group1 ran"

#-----# Configure OIDC clients #----#

# Configure general API OIDC client to authorize calls through Kong
CLIENT_KONG_PAYLOAD='{
  "clientId": "kong",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "secret-kong",
  "redirectUris": ["/mock/*"],
  "rootUrl": "https://localhost:8443",
  "attributes": {
    "clientAuthenticatorType": "client-secret"
  },
  "serviceAccountsEnabled": true
}'
CLIENT_KONG_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/newrealm/clients" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -d "$CLIENT_KONG_PAYLOAD")
#check_value "$CLIENT_KONG_RESPONSE" "Kong Client setup response"

# Configure Admin OIDC Client to authorize administrative access
CLIENT_MYAPP_PAYLOAD='{
  "clientId": "myapp",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "secret-myapp",
  "redirectUris": ["http://myapp"]
}'
echo "Ran admin OIDC client configuration"

CLIENT_MYAPP_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/newrealm/clients" \
    -H "Content-Type: application.json" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -d "$CLIENT_MYAPP_PAYLOAD")
#check_value "$CLIENT_MYAPP_RESPONSE" "MyApp Client setup response"
echo "Realm, Users, Clients, and Group configurations ran"
