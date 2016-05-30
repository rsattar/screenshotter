# Copyright (c) 2016 Cluster Labs, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Replace this path with the path to the key you just downloaded
JSON_FILE=./JSON_FILE_NAME

# Check if JSON file exists, skip if not
if [ ! -e ${JSON_FILE} ]; then
	echo "warning: Firebase Crash JSON file not found, not uploading symbols"
	exit 0
fi

# Mark path to GoogleService-Info.plist
GOOGLE_SERVICE_INFO_FILE=./GoogleService-Info.plist
# Check if the GoogleService-Info.plist file exists; skip if not
if [ ! -e ${GOOGLE_SERVICE_INFO_FILE} ]; then
	echo "warning: GoogleService-Info.plist file not found, not upload symbols"
	exit 0
fi


# Extract GOOGLE_APP_ID from your GoogleService-Info.plist file
GOOGLE_APP_ID=$(defaults read "$PWD/GoogleService-Info" GOOGLE_APP_ID)

# Check if GOOGLE_APP_ID is empty
if [ -z "$GOOGLE_APP_ID" ]; then
	echo "warning: GOOGLE_APP_ID is missing in GoogleService-Info.plist, not uploading symbols"
	exit 0
fi

defaults write com.google.SymbolUpload version -integer 1   # creates file if it does not exist
JSON=$(cat "${JSON_FILE}")

/usr/bin/plutil -replace "app_${GOOGLE_APP_ID//:/_}" -json "${JSON}" "$HOME/Library/Preferences/com.google.SymbolUpload.plist"
"${PODS_ROOT}"/FirebaseCrash/upload-sym
