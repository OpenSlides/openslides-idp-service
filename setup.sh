#!/bin/sh
# Bootstrap script: creates the OIDC application in Zitadel and uploads
# the logo as instance branding. Runs once after Zitadel is healthy

ZITADEL_URL="${ZITADEL_INTERNAL_URL:-http://zitadel-api:8080}"
# Zitadel resolves the tenant instance by matching the Host header against the
# registered external domain. The instance is bootstrapped with
# ZITADEL_EXTERNALDOMAIN / ZITADEL_EXTERNALPORT, so every curl call must send
# that host (default: localhost:8080) instead of the internal docker hostname.
ZITADEL_EXTERNAL_HOST="${ZITADEL_EXTERNAL_HOST:-localhost:8800}"
PAT_FILE="/zitadel/bootstrap/admin.pat"
CLIENT_ID_FILE="/zitadel/bootstrap/client-id"
CLIENT_SECRET_FILE="/zitadel/bootstrap/client-secret"
ORG_ID_FILE="/zitadel/bootstrap/org-id"
PROJECT_ID_FILE="/zitadel/bootstrap/project-id"
APP_ID_FILE="/zitadel/bootstrap/app-id"
LOGO_FILE="/logos/logo-192.png"
FAVICON_FILE="/logos/favicon.ico"

REDIRECT_URI="${ZITADEL_REDIRECT_URI:-https://localhost:8000/oidc/callback}"
POST_LOGOUT_URI="${APP_REDIRECT_URL:-https://localhost:8000/oidc/callback}"

# Wait for the admin PAT written by Zitadel's init and setup script
echo "Waiting for admin PAT at $PAT_FILE ..."
i=0
while [ ! -s "$PAT_FILE" ]; do
    i=$((i + 1))
    if [ $i -ge 60 ]; then
        echo "ERROR: timed out waiting for $PAT_FILE" >&2
        exit 1
    fi
    sleep 2
done

PAT="$(cat "$PAT_FILE")"
echo "-------------------------------------------------------------"
echo "Admin PAT loaded: $PAT"

sleep 5

# Remove potentially stale ID artifacts
rm -f "$CLIENT_ID_FILE" "$CLIENT_SECRET_FILE" "$ORG_ID_FILE" "$PROJECT_ID_FILE" "$APP_ID_FILE"

upload_logo()
{

    # ---------------------------------------------------------------------------
    # Upload instance logo (light and dark variants) and favicon
    # ---------------------------------------------------------------------------
    # Logo assets are served through the dedicated /assets/v1 handler, not the
    # admin/v1 gRPC-gateway.  The paths are:
    #   POST /assets/v1/instance/policy/label/logo       (light theme logo)
    #   POST /assets/v1/instance/policy/label/logo/dark  (dark theme logo)
    #   POST /assets/v1/instance/policy/label/icon       (light theme favicon)
    #   POST /assets/v1/instance/policy/label/icon/dark  (dark theme favicon)
    # After uploading, the preview policy must be activated via the admin API:
    #   POST /admin/v1/policies/label/_activate          (note the underscore)
    # ---------------------------------------------------------------------------
    if [ -f "$LOGO_FILE" ]; then
        echo "Uploading logo (light) ..."
        if LOGO_RESP=$(curl -f \
                -X POST \
                -H "Authorization: Bearer $PAT" \
                -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
                -F "file=@${LOGO_FILE};type=image/png" \
                "${ZITADEL_URL}/assets/v1/instance/policy/label/logo" 2>&1); then
            echo "Logo (light) uploaded"
        else
            echo "WARN: logo (light) upload failed (non-fatal): $LOGO_RESP"
        fi

        # Dark-theme logo: use logo-dark.png when present, otherwise reuse logo.png.
        echo "Uploading logo (dark) ..."
        if LOGO_DARK_RESP=$(curl -f \
                -X POST \
                -H "Authorization: Bearer $PAT" \
                -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
                -F "file=@${LOGO_FILE};type=image/png" \
                "${ZITADEL_URL}/assets/v1/instance/policy/label/logo/dark" 2>&1); then
            echo "Logo (dark) uploaded"
        else
            echo "WARN: logo (dark) upload failed (non-fatal): $LOGO_DARK_RESP"
        fi

        # Favicon (light and dark): use the same icon for both themes.
        if [ -f "$FAVICON_FILE" ]; then
            echo "Uploading favicon (light) ..."
            if FAVICON_RESP=$(curl -f \
                    -X POST \
                    -H "Authorization: Bearer $PAT" \
                    -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
                    -F "file=@${FAVICON_FILE};type=image/x-icon" \
                    "${ZITADEL_URL}/assets/v1/instance/policy/label/icon" 2>&1); then
                echo "Favicon (light) uploaded"
            else
                echo "WARN: favicon (light) upload failed (non-fatal): $FAVICON_RESP"
            fi
            echo "Uploading favicon (dark) ..."
            if FAVICON_DARK_RESP=$(curl -f \
                    -X POST \
                    -H "Authorization: Bearer $PAT" \
                    -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
                    -F "file=@${FAVICON_FILE};type=image/x-icon" \
                    "${ZITADEL_URL}/assets/v1/instance/policy/label/icon/dark" 2>&1); then
                echo "Favicon (dark) uploaded"
            else
                echo "WARN: favicon (dark) upload failed (non-fatal): $FAVICON_DARK_RESP"
            fi
        else
            echo "WARN: favicon file not found at $FAVICON_FILE, skipping favicon upload."
        fi

        # Activate the label policy so the logo and favicon take effect.
        # The activate action uses a leading underscore in the URL segment.
        if curl -f \
                -X POST \
                -H "Authorization: Bearer $PAT" \
                -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
                -H "Content-Type: application/json" \
                -d '{}' \
                "${ZITADEL_URL}/admin/v1/policies/label/_activate"; then
            echo "Label policy activated."
        else
            echo "WARN: label policy activation failed (non-fatal)."
        fi
    else
        echo "WARN: logo file not found at $LOGO_FILE, skipping logo upload."
    fi

}

upload_logo

# Request the organization id generated during setup.
ORG_ID=""
ORG_RESP=$(curl -f -X POST \
    -H "Authorization: Bearer $PAT" \
    -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
    "${ZITADEL_URL}/v2/organizations/_search" \
    -d "{}")

ORG_ID=$(printf '%s' "$ORG_RESP" | jq -r '.result[0].id // empty')
echo "-------------------------------------------------------------"
echo "Organsitation created (ID: $ORG_ID)"


# Create the project
PROJECT_ID=""
if [ -z "$PROJECT_ID" ]; then
    echo "Creating project ..."
    PROJECT_RESP=$(curl -f \
        -X POST "${ZITADEL_URL}/zitadel.project.v2.ProjectService/CreateProject" \
        -H "Authorization: Bearer $PAT" \
        -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
        -H "Content-Type: application/json" \
        -H "Connect-Protocol-Version: 1" \
        -d "{
            \"organizationId\": \"${ORG_ID}\",
            \"name\": \"openslides\"
        }")

    PROJECT_ID=$(printf '%s' "$PROJECT_RESP" | jq -r '.projectId // empty')
    if [ -z "$PROJECT_ID" ]; then
        echo "ERROR: could not parse project ID from response: $PROJECT_RESP"
        exit 1
    fi
    printf '%s' "$PROJECT_ID" > "$PROJECT_ID_FILE"
    echo "-------------------------------------------------------------"
    echo "Project created (ID: $PROJECT_ID)."
fi

# Create the OIDC application
# This will return a an Application ID as well as a Client ID
# No Client Secret will be returned, this requires a separate API call
echo "Creating OIDC application ..."
APP_RESP=$(curl -f \
    -X POST "${ZITADEL_URL}/zitadel.application.v2.ApplicationService/CreateApplication" \
    -H "Authorization: Bearer $PAT" \
    -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
    -H "Content-Type: application/json" \
    -H "Connect-Protocol-Version: 1" \
    -d "{
        \"applicationId\": \"OpenSlides\",
        \"projectId\": \"${PROJECT_ID}\",
        \"name\": \"OpenSlides\",
        \"oidcConfiguration\": {
            \"redirectUris\": [\"${REDIRECT_URI}\"],
            \"responseTypes\": [\"OIDC_RESPONSE_TYPE_CODE\"],
            \"grantTypes\": [\"OIDC_GRANT_TYPE_AUTHORIZATION_CODE\",\"OIDC_GRANT_TYPE_REFRESH_TOKEN\"],
            \"applicationType\": \"OIDC_APP_TYPE_WEB\",
            \"authMethodType\": \"OIDC_AUTH_METHOD_TYPE_NONE\",
            \"postLogoutRedirectUris\": [\"${POST_LOGOUT_URI}\"],
            \"version\": \"OIDC_VERSION_1_0\",
            \"devMode\": true,
            \"accessTokenType\": \"OIDC_TOKEN_TYPE_JWT\",
            \"accessTokenRoleAssertion\": false,
            \"idTokenRoleAssertion\": false,
            \"idTokenUserinfoAssertion\": true,
            \"clockSkew\": \"0s\",
            \"skipNativeAppSuccessPage\": true,
            \"backChannelLogoutUrl\": \"http://:localhost:8000/system/action/logout\"
        }
    }")

CLIENT_ID=$(printf '%s' "$APP_RESP" | jq -r '.oidcConfiguration.clientId // empty')
# Client secret requires a seperate API route call
# CLIENT_SECRET=$(printf '%s' "$APP_RESP" | jq -r '.oidcConfiguration.clientSecret // empty')
APP_ID=$(printf '%s' "$APP_RESP" | jq -r '.applicationId // empty')
if [ -z "$CLIENT_ID" ] || [ -z "$APP_ID" ]; then
    echo "ERROR: could not parse clientId/applicationId from response: $APP_RESP" >&2
    exit 1
fi

echo "-------------------------------------------------------------"
echo "OIDC application created (App ID: $APP_ID, Client ID: $CLIENT_ID)."


# Create OS ID Action and append it to JWT Token Flow
# Use v1 instead of v2 actions; the latter require a self-hosted webhook endpoint
ACTION_FUNCTION="function setOsId(ctx, api) { const metadata = ctx.v1.user.getMetadata(); if (!metadata || !metadata.metadata) {api.v1.claims.setClaim("os_id", 0); return;} metadata.metadata.forEach(({ key, value }) => { if (key === 'os_id' && value) { api.v1.claims.setClaim('os_id', value); } }); }"

ACTION_RESP=$(curl -X POST "${ZITADEL_URL}/management/v1/actions" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"setOsId\",
            \"script\": \"${ACTION_FUNCTION}\",
            \"timeout\": \"3s\",
            \"allowedToFail\": false
        }")

echo "-------------------------------------------------------------"
echo "Created Action"

ACTION_ID=$(printf '%s' "$ACTION_RESP" | jq -r '.id // empty')

# 2 = Complement Token
# 5 = Pre Access Token Creation
FLOW_RESP=$(curl -X POST "${ZITADEL_URL}/management/v1/flows/2/trigger/5" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Host: ${ZITADEL_EXTERNAL_HOST}" \
        -H "Content-Type: application/json" \
        -d "{
            \"actionIds\": [\"${ACTION_ID}\"]
    }")

echo "-------------------------------------------------------------"
echo "Created Flow and added Action"

# Persist the ID artifacts so that the backend and other services can use it
printf '%s' "$APP_ID" > "$APP_ID_FILE"
printf '%s' "$CLIENT_ID" > "$CLIENT_ID_FILE"
# printf '%s' "$CLIENT_SECRET" > "$CLIENT_SECRET_FILE"
printf '%s' "$ORG_ID" > "$ORG_ID_FILE"
echo "Zitadel setup complete."

