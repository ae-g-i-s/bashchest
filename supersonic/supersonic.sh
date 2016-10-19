#!/bin/bash

DEPENDENCIES="md5sum curl awk basename find du tr jq sed"

for dependency in $DEPENDENCIES
do
	which $dependency 2>&1 > /dev/null || {
		echo "Missing required depedency: ${dependency}. Exiting."
		exit -1
	}
done

CLIENT_ID='supersonic.sh'							# Static client ID
HOST='http://your.host.com:4040'	# Subsonic host
USER='username'
PASS='password'
API_VERSION='1.14.0'									# API version; 1.40.0 is for Subsonic 6.0+

# API endpoints
ENDPOINT_GET_STARRED='getStarred.view'
ENDPOINT_DOWNLOAD='download.view'

# Additional command-specific parameters
QUERY_PARAMS=""

# The list of implemented commands
COMMANDS="sync"

# Performs a subsonic API call.
# Since the invocation of curl is the last line, you can use this function's output and return value like curl.
function subsonic_request() {
	# Authentication parameters
	SALT=$RANDOM
	HASH=$(echo -n "${PASS}${SALT}" | md5sum - | awk '{print $1}')

	# Perform request
	curl -# "${HOST}/rest/${ENDPOINT}?u=${USER}&s=${SALT}&t=${HASH}&c=${CLIENT_ID}&v=${API_VERSION}&f=json&${QUERY_PARAMS}"
}

# Formats a size from bytes to MB
function format_size() {
	echo $1 | awk '{printf("%.2f MB", ($1/1024/1024))}'
}

case "$1" in
	sync)
		echo "Syncing starred tracks to the current folder ($PWD)"
		# First, get all starred tunes
		ENDPOINT="${ENDPOINT_GET_STARRED}"
		echo "Retrieving starred tracks from Subsonic"
		i=0
		subsonic_request | jq -c '."subsonic-response".starred.song[] | {"id","artist","album","title","size","path"}' | sed -e 's|\\|\\\\|g' | while read entry
		do
			ID=$(echo "$entry" | jq '.id' | tr -dc '[0-9]')
			ARTIST=$(echo "$entry" | jq '.artist'  | sed -e 's/^"//' -e 's/"$//' -e 's/\\//g')
			ALBUM=$(echo "$entry" | jq '.album' | sed -e 's/^"//' -e 's/"$//' -e 's/\\//g')
			TITLE=$(echo "$entry" | jq '.title' | sed -e 's/^"//' -e 's/"$//' -e 's/\\//g')
			SIZE=$(echo "$entry" | jq '.size' | sed -e 's/^"//' -e 's/"$//' -e 's/\\//g')
			FILE=$(echo "$entry" | jq '.path' | sed -e 's/^"//' -e 's/"$//' -e 's/\\//g')
			FILE_BASE=$(basename "${FILE}")
			SIZE_FORMATTED=$(format_size "${SIZE}")
			#echo "$FILE_BASE" | grep -q mp3 || { echo "Skipping ${FILE_BASE}"; continue; }
			echo "${i}. ${ARTIST} - ${TITLE} (${ALBUM}) [${FILE_BASE}, ${SIZE_FORMATTED}] {id: ${ID}}"
			i=$(($i+1))
			HAVE_EXISTING=""

			# Find existing files that have the same name and see if any of them have approximately the same size.
			# The "approximate" size (with a margin of 4kB) is there to compensate for file system differences.
			FILE_BASE_ESCAPED=$(echo -n "$FILE_BASE" | sed -e 's|\[|\\[|g' -e 's|\]|\\]|g')
			while read existing
			do
				existing_size=$(echo "${existing}" | awk '{print $1}')
				existing_size_formatted=$(format_size "${existing_size}")
				difference=$((${SIZE}-${existing_size}))
				existing_path=$(echo "${existing}" | sed -e "s|^${existing_size}\s*||")
				echo -n "> Existing file: ${existing_path}... "
				if [ "$difference" -lt 4096 -a "$difference" -gt -4096 ]
				then
					echo "Size OK (${existing_size_formatted})"
					HAVE_EXISTING="${existing_path}"
					continue 2;
				else
					echo "too small/large (${existing_size_formatted})"
				fi
			done < <(find . -name "${FILE_BASE_ESCAPED}" -exec du --bytes {} \;)
			[ -n "${HAVE_EXISTING}" ] && continue
			# If we landed here, there is no existing file that is large enough.
			ENDPOINT="${ENDPOINT_DOWNLOAD}"
			QUERY_PARAMS="id=${ID}"
			echo "> Downloading..."
			subsonic_request > "${FILE_BASE}"
			sleep 2
		done
		;;
	starred)
		ENDPOINT="${ENDPOINT_GET_STARRED}"
		subsonic_request
		;;
	*) 
		echo "No such command. Implemented commands are: ${COMMANDS}"
		;;
esac
