# Output a clickable message.  This will not count as a warning or
# error.

xcnote () {
    echo >&2 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: note: $*"
}

# Output a clickable message prefixed with a warning symbol (U+26A0)
# and highlighted yellow.  This will increase the overall warning
# count.  A non-zero value for the variable ERRORS_ONLY will force
# warnings to be treated as errors.

if ((ERRORS_ONLY)); then
    xcwarning () {
        echo >&2 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: error: $*"
    }
else
    xcwarning () {
        echo >&2 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: warning: $*"
    }
fi

# Output a clickable message prefixed with a halt symbol (U+1F6D1) and
# highlighted red.  This will increase the overall error count.  Xcode
# will flag the build as failed if the error count is non-zero at the
# end of the build, even if this script returns a successful exit
# code.  Set WARNINGS_ONLY to non-zero to prevent this.

if ((WARNINGS_ONLY)); then
    xcerror () {
        echo >&2 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: warning: $*"
    }
else
    xcerror () {
        echo >&2 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}: error: $*"
    }
fi

# Locate the script directory.

script_dir () {
    local SCRIPT

    if [[ "$0" = */* ]]; then SCRIPT="$0"; else SCRIPT="./$0"; fi

    while [[ -L "$SCRIPT" ]]; do
        local LINK="$(readlink "$SCRIPT")"
        if [[ "$LINK" == /* ]]; then
            SCRIPT="$LINK"
        else
            SCRIPT="${SCRIPT%/*}/$LINK"
        fi
    done

    ( cd "${SCRIPT%/*}"; pwd -P )
}

# All files created by fcr_mktemp will be listed in FCR_TEMPORARY_FILES.
# Delete these when the enclosing script exits.

typeset -a FCR_TEMPORARY_FILES
trap 'STATUS=$?; rm -rf "${FCR_TEMPORARY_FILES[@]}"; exit $STATUS' 0 1 2 15

# Create a temporary file and add it to the list of files to delete when the
# script finishes.
#
# Arguments: Variable names in which to store the generated file names.

fcr_mktemp () {
    for VAR; do
        eval "$VAR=\$(mktemp -t com.google.FirebaseCrashReporter) || return 1"
        FCR_TEMPORARY_FILES+=("${!VAR}")
    done
}

# Create a temporary directory and add it to the list of files to
# delete when the script finishes.
#
# Arguments: Variable names in which to store the generated file names.

fcr_mktempdir () {
    for VAR; do
        eval "$VAR=\$(mktemp -d -t com.google.FirebaseCrashReporter) || return 1"
        FCR_TEMPORARY_FILES+=("${!VAR}")
    done
}

# BASE64URL uses a sligtly different character set than BASE64, and uses no
# padding characters.

function base64url () {
    /usr/bin/base64 | sed -e 's/=//g; s/+/-/g; s/\//_/g'
}

FCR_SVC_KEYS=(auth_provider_x509_cert_url auth_uri client_email client_id client_x509_cert_url private_key private_key_id project_id token_uri type)
FCR_TOK_KEYS=(access_token expires_at token_type)

# Retrieve the property from the service account property list using
# the application ID.  Assumes the APP_KEY variable has been
# initialized, which contains the application key translated to a
# property name.  To examine the top level of the property list,
# temporarily set APP_KEY to the empty string.

svc_property () {
    /usr/libexec/PlistBuddy "${SVC_PLIST}" \
        -c "Print ${APP_KEY:+:${APP_KEY}}${1:+:$1}" 2>/dev/null
}

# Does the same as svc_property above but for the token cache
# property list.

tok_property () {
    /usr/libexec/PlistBuddy "${TOK_PLIST}" \
        -c "Print ${APP_KEY:+:${APP_KEY}}${1:+:$1}" 2>/dev/null
}

# Verify that the service account property list has values for the
# required keys.  Does not check the values themselves.

fcr_verify_svc_plist () {
    for key in "${FCR_SVC_KEYS[@]}"; do
        if ! svc_property "$key" >/dev/null; then
            xcwarning "$key not found in $SVC_PLIST."
            return 1
        fi
    done
}

# Verify that the token cache property list has values for the
# required keys.  If the token_type is incorrect or the expiration
# date has been passed, return failure.

fcr_verify_tok_plist () {
    for key in "${FCR_TOK_KEYS[@]}"; do
        if ! tok_property "$key" >/dev/null; then
            xcwarning "$key not found in $TOK_PLIST."
            return 1
        fi
    done

    if [[ "$(tok_property token_type)" != "Bearer" ]]; then
        xcwarning "Invalid token type '$(tok_property token_type)'."
        return 1
    fi

    if (($(tok_property expires_at) <= NOW)); then
        ((VERBOSE)) && xcnote "Token well-formed but expired."
        return 1
    fi
}

#
# If the user has an existing version 0 property list, try to convert
# it to the new format, assuming that the current app ID is the
# correct one.
#
fcr_legacy_format_conversion_0 () {
    VERSION="$(APP_KEY='' svc_property version)"

    # Handle situation where VERSION is absent or malformed.
    [[ "${VERSION}" =~ ^[[:digit:]]+$ ]] || VERSION=0

    ((VERSION < 1)) || return

    xcnote "Converting certificate information to version 1."

    for key in "${FCR_SVC_KEYS[@]}"; do
        if ! (APP_KEY='' svc_property "$key" >/dev/null 2>&1); then
            xcerror "Current service account information unsalvagable."

            /usr/libexec/PlistBuddy "$SVC_PLIST" -c 'Clear dict' 2>/dev/null
            /usr/libexec/PlistBuddy "$TOK_PLIST" -c 'Clear dict' 2>/dev/null

            return
        fi
    done

    /usr/libexec/PlistBuddy "$SVC_PLIST" \
        -c "Copy : :$APP_KEY" \
        -c "Add :version integer 1" >/dev/null 2>&1

    for key in "${FCR_SVC_KEYS[@]}"; do
        /usr/libexec/PlistBuddy "$SVC_PLIST" -c "Delete :$key" >/dev/null 2>&1
    done

    /usr/libexec/PlistBuddy "$TOK_PLIST" -c 'Clear dict' >/dev/null 2>&1
}

# Set the BEARER_TOKEN variable for authentication.
#
# Requires interaction if the file has not been installed correctly.
#
# No arguments.

fcr_authenticate () {
    : "${FIREBASE_APP_ID:?FIREBASE_APP_ID is required to select authentication credentials}"

    local SVC_PLIST="$HOME/Library/Preferences/com.google.SymbolUpload.plist"
    local TOK_PLIST="$HOME/Library/Preferences/com.google.SymbolUploadToken.plist"

    # Translate FIREBASE_APP_ID to a property list key.  This involves
    # prefixing it with an alphabetic character and replacing all
    # colons with underscores.  Technically, property lists can use
    # any legal string as a key, but some of the utilities are more
    # finicky than others.

    local APP_KEY="app_${FIREBASE_APP_ID//:/_}"

    # Convert service account plist version 0 to version 1 if needed.
    fcr_legacy_format_conversion_0

    if ((VERBOSE > 2)); then
        CURLOPT='--trace-ascii /dev/fd/2'
    elif ((VERBOSE > 1)); then
        CURLOPT='--verbose'
    else
        CURLOPT=''
    fi

    local NOW="$(/bin/date +%s)"

    # If the certificate property list does not contain the required
    # keys, delete it and the token property list.
    if ! fcr_verify_svc_plist; then
        xcnote "Invalid certificate information for $FIREBASE_APP_ID."
        /usr/libexec/PlistBuddy "$SVC_PLIST" -c "Delete $APP_KEY" >/dev/null 2>&1
        /usr/libexec/PlistBuddy "$TOK_PLIST" -c "Delete $APP_KEY" >/dev/null 2>&1
    else
        ((VERBOSE)) && xcnote "Certificate information valid."
    fi

    # If the token will expire in the next sixty seconds (or already
    # has), reload it.
    if ! fcr_verify_tok_plist; then
        if ! fcr_verify_svc_plist; then
            /usr/libexec/PlistBuddy "$SVC_PLIST" \
                -c "Add :version integer" \
                -c "Set :version 1"
            local JSON_FILE="$(/usr/bin/osascript -e 'the POSIX path of (choose file with prompt "Where is the service account file?" of type "public.json")' 2>/dev/null)"
            if [[ "$JSON_FILE" && -f "$JSON_FILE" ]]; then
                /usr/bin/plutil -replace "$APP_KEY" -json "$(/bin/cat "$JSON_FILE")" "$SVC_PLIST" || return 2

                if fcr_verify_svc_plist; then
                    ((VERBOSE)) && xcnote "Installed service account file into $SVC_PLIST."
                else
                    /usr/libexec/PlistBuddy "$SVC_PLIST" -c "Delete $APP_KEY" >/dev/null 2>&1
                    xcerror "Unable to parse service account file."
                    return 2
                fi
            else
                xcerror "User cancelled symbol uploading."
                return 1
            fi
        fi

        ((VERBOSE)) && xcnote "Requesting OAuth2 token using installed credentials."

        TOKEN_URI="$(svc_property token_uri)"
        CLIENT_EMAIL="$(svc_property client_email)"

        # Assemble the JSON Web Token (RFC 1795)
        local JWT_HEADER='{"alg":"RS256","typ":"JWT"}'
        JWT_HEADER="$(echo -n "$JWT_HEADER" | base64url)"
        local JWT_CLAIM='{"iss":"'"$CLIENT_EMAIL"'","scope":"https://www.googleapis.com/auth/mobilecrashreporting","aud":"'"$TOKEN_URI"'","exp":'"$((NOW + 3600))"',"iat":'"$NOW"'}'
        JWT_CLAIM="$(echo -n "$JWT_CLAIM" | base64url)"
        local JWT_SIG="$(echo -n "$JWT_HEADER.$JWT_CLAIM" | openssl dgst -sha256 -sign <(svc_property private_key) -binary | base64url)"
        local JWT="$JWT_HEADER.$JWT_CLAIM.$JWT_SIG"

        if [[ "$(tok_property version)" != 1 ]]; then
            /usr/libexec/PlistBuddy "$TOK_PLIST" \
                -c "Clear dict" \
                -c "Add :version integer 1" >/dev/null 2>&1
        fi

        TOKEN_JSON="$(curl $CURLOPT -s -d grant_type='urn:ietf:params:oauth:grant-type:jwt-bearer' -d assertion="$JWT" "$TOKEN_URI")"

        /usr/bin/plutil -replace "$APP_KEY" -json "$TOKEN_JSON" \
            "$TOK_PLIST" || return 1

        EXPIRES_AT="$(($(tok_property expires_in) + NOW))"

        /usr/libexec/PlistBuddy "$TOK_PLIST" \
            -c "Add :$APP_KEY:expires_at integer $EXPIRES_AT" \
            -c "Add :$APP_KEY:expiration_date date $(date -jf %s "$EXPIRES_AT")"
    else
        ((VERBOSE)) && xcnote "Token still valid."
        EXPIRES_AT="$(tok_property expires_at)"
    fi

    ((VERBOSE)) && xcnote "Token will expire at $(date -jf %s +'%r %Z' "$EXPIRES_AT")."

    ((VERBOSE > 1)) && xcnote "Using service account with key $(svc_property private_key_id)"

    BEARER_TOKEN="$(tok_property access_token)"

    if [[ ! "$BEARER_TOKEN" ]]; then
        # Calling tok_property without an argument dumps the entire
        # token cache to the console.
        tok_property
        xcerror "Unable to retrieve authentication token from server."
        /usr/libexec/PlistBuddy "$TOK_PLIST" -c "Delete $APP_KEY"
        return 2
    fi

    return 0
}

# Upload the files to the server.
#
# Arguments: Names of files to upload.

fcr_upload_files() {
    fcr_authenticate || return $?

    : "${FCR_PROD_VERS:?}"
    : "${FCR_BUNDLE_ID:?}"
    : "${FIREBASE_APP_ID:?}"
    : "${FIREBASE_API_KEY:?}"
    : "${FCR_BASE_URL:=https://mobilecrashreporting.googleapis.com}"

    fcr_mktemp FILE_UPLOAD_LOCATION_PLIST META_UPLOAD_RESULT_PLIST

    if ((VERBOSE > 2)); then
        CURLOPT='--trace-ascii /dev/fd/2'
    elif ((VERBOSE > 1)); then
        CURLOPT='--verbose'
    else
        CURLOPT=''
    fi

    for FILE; do
        ((VERBOSE)) && xcnote "Get signed URL for uploading."

        URL="$FCR_BASE_URL/v1/apps/$FIREBASE_APP_ID"

        curl $CURLOPT -sL -H "X-Ios-Bundle-Identifier: $FCR_BUNDLE_ID" -H "Authorization: Bearer $BEARER_TOKEN" -X POST -d '' "$URL/symbolFileUploadLocation?key=$FIREBASE_API_KEY" >|"$FILE_UPLOAD_LOCATION_PLIST" || return 1

        plutil -convert binary1 "$FILE_UPLOAD_LOCATION_PLIST" || return 1

        UPLOAD_KEY="$(/usr/libexec/PlistBuddy -c 'print uploadKey' "$FILE_UPLOAD_LOCATION_PLIST" 2>/dev/null)"
        UPLOAD_URL="$(/usr/libexec/PlistBuddy -c 'print uploadUrl' "$FILE_UPLOAD_LOCATION_PLIST" 2>/dev/null)"
        ERRMSG="$(/usr/libexec/PlistBuddy -c 'print error:message' "$FILE_UPLOAD_LOCATION_PLIST" 2>/dev/null)"

        if [[ "$ERRMSG" ]]; then
            if ((VERBOSE)); then
                xcnote "Server response:"
                plutil -p "$FILE_UPLOAD_LOCATION_PLIST" >&2
            fi
            xcerror "symbolFileUploadLocation: $ERRMSG"
            xcnote "symbolFileUploadLocation: Failed to get upload location."
            return 1
        fi

        ((VERBOSE)) && xcnote "Upload symbol file."

        HTTP_STATUS=$(curl $CURLOPT -sfL -H 'Content-Type: text/plain' -H "Authorization: Bearer $BEARER_TOKEN" -w '%{http_code}' -T "$FILE" "$UPLOAD_URL")
        STATUS=$?

        if ((STATUS == 22)); then # exit code 22 is a non-successful HTTP response
            xcerror "upload: Unable to upload symbol file (HTTP Status $HTTP_STATUS)."
            return 1
        elif ((STATUS != 0)); then
            xcerror "upload: Unable to upload symbol file (reason unknown)."
            return 1
        fi

        ((VERBOSE)) && xcnote "Upload metadata information."

        curl $CURLOPT -sL -H 'Content-Type: application/json' -H "X-Ios-Bundle-Identifier: $FCR_BUNDLE_ID" -H "Authorization: Bearer $BEARER_TOKEN" -X POST -d '{"upload_key":"'"$UPLOAD_KEY"'","symbol_file_mapping":{"symbol_type":2,"app_version":"'"$FCR_PROD_VERS"'"}}' "$URL/symbolFileMappings:upsert?key=$FIREBASE_API_KEY" >|"$META_UPLOAD_RESULT_PLIST" || return 1
        plutil -convert binary1 "$META_UPLOAD_RESULT_PLIST" || return 1

        ERRMSG="$(/usr/libexec/PlistBuddy -c 'print error:message' "$META_UPLOAD_RESULT_PLIST" 2>/dev/null)"

        if [[ "$ERRMSG" ]]; then
            xcerror "symbolFileMappings:upsert: $ERRMSG"
            xcnote "symbolFileMappings:upsert: The metadata for the symbol file failed to update."
            return 1
        fi
    done
}
