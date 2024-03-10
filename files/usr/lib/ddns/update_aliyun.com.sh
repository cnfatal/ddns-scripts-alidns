#!/bin/sh
#
# activated inside /etc/config/ddns by setting
#
# option update_script '/usr/lib/ddns/update_aliyun.com.sh'
#
# the script is parsed (not executed) inside send_update() function
# of /usr/lib/ddns/dynamic_dns_functions.sh
# so you can use all available functions and global variables inside this script
# already defined in dynamic_dns_updater.sh and dynamic_dns_functions.sh
#
# It make sence to define the update url ONLY inside this script
# because it's anyway unique to the update script
# otherwise it should work with the default scripts
#
# https://next.api.aliyun.com/api/Alidns/2015-01-09/UpdateDomainRecord
#
# Arguments:
#
# - $username: The access key ID for the service account. You can find at
# 	https://ram.console.aliyun.com/manage/ak
#
# - $password: The secret key for the service account. You can find this
#
# - $domain: The domain to update.
#
# - $param_opt: Optional TTL for the records, in seconds. Defaults to 3600 (1h).
# Dependencies:
# - ddns-scripts  (for the base functionality)
# - openssl-util  (for the authentication flow)
# - curl          (for the GCP REST API)

# . /usr/share/libubox/jshn.sh

sha256() {
	echo -n "$1" | openssl sha256 -r | awk '{print $1}'
}

hmac_sha256() {
	echo -n "$1" | openssl sha256 -hmac "$2" -r | awk '{print $1}'
}

canonical_uri() {
	echo $1 | tr '+' '%20' | tr '*' '%2A' | tr '%7E' '~'
}

canonical_query_string() {
	echo $1 | tr '&' '\n' | sort -d | tr '\n' '&' | sed 's/&$//' | sed 's/:/%3A/g'
}

canonical_headers() {
	echo "$1" | xargs -n1 | sort -d
}

signed_headers() {
	echo -n "$1" | xargs -n1 | cut -d: -f1 | tr '\n' ';' | sed 's/;$//'
}

headers_args() {
	echo $@ | xargs -n1 | awk '{printf "-H %s ",$1}'
}

# https://help.aliyun.com/zh/sdk/product-overview/v3-request-structure-and-signature
do_rpc_transfer() {
	local METHOD="$1"
	local ACTION="$2"
	local QUERY_STRING="$3"
	local BODY="$4"
	write_log 7 "do_rpc_transfer:-> ${METHOD} ${ACTION} ${QUERY_STRING} ${BODY}"
	SERVER="http://dns.aliyuncs.com"
	[ -n "${CURL_SSL}" ] && SERVER="https://dns.aliyuncs.com"
	CANONICAL_URI="/"
	CANONICAL_QUERY_STRING=$(canonical_query_string $QUERY_STRING)
	DATE=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
	NONCE=$(openssl rand -hex 16)
	HASHED_REQUEST_PAYLOAD=$(sha256 "${BODY}")
	HEADERS="x-acs-action:${ACTION} \
		x-acs-signature-method:HMAC-SHA1 \
		x-acs-version:2015-01-09 \
		x-acs-date:${DATE} \
		x-acs-content-sha256:${HASHED_REQUEST_PAYLOAD} \
		x-acs-signature-nonce:${NONCE}"
	CANONICAL_HEADERS=$(canonical_headers "${HEADERS}")
	SIGNED_HEADERS=$(signed_headers "${CANONICAL_HEADERS}")
	CANONICAL_REQUEST=$(printf "%s\n%s\n%s\n%s\n\n%s\n%s" \
		"${METHOD}" \
		"${CANONICAL_URI}" \
		"${CANONICAL_QUERY_STRING}" \
		"${CANONICAL_HEADERS}" \
		"${SIGNED_HEADERS}" \
		"${HASHED_REQUEST_PAYLOAD}")
	HASHED_CANONICAL_REQUEST=$(sha256 "${CANONICAL_REQUEST}")
	STRING_TO_SIGN=$(printf "%s\n%s" "ACS3-HMAC-SHA256" "${HASHED_CANONICAL_REQUEST}")
	SIGNATURE=$(hmac_sha256 "${STRING_TO_SIGN}" "${password}")
	AUTHORIZATION="ACS3-HMAC-SHA256 Credential=${username},SignedHeaders=${SIGNED_HEADERS},Signature=${SIGNATURE}"

	CURL_ARGS="-sS --stderr $ERRFILE"
	_RESULT=$($CURL -X ${METHOD} \
		$(headers_args ${CANONICAL_HEADERS}) \
		-H "Authorization:${AUTHORIZATION}" \
		-d "${BODY}" \
		${CURL_ARGS} ${SERVER}${CANONICAL_URI}?${CANONICAL_QUERY_STRING})
	write_log 7 "do_rpc_transfer:<- ${_RESULT}"
	echo $_RESULT
}

update_record() {
	DOAMIN_NAME=$1
	RECORD_NAME=$2
	RECORD_TYPE=$3
	VALUE=$4
	_RESULT=$(do_rpc_transfer GET DescribeDomainRecords "DomainName=${DOAMIN_NAME}&RRKeyWord=${RECORD_NAME}&Type=${RECORD_TYPE}")
	if [ -z "$_RESULT" ]; then
		write_log 14 "Failed to get record for ${RECORD_NAME}.${DOAMIN_NAME}"
		return
	fi
	RECORD_ID=$(jsonfilter -s "$_RESULT" -e '@.DomainRecords.Record[0].RecordId')
	write_log 7 "Got record id for ${RECORD_NAME}.${DOAMIN_NAME}: ${RECORD_ID}"
	if [ -z "$RECORD_ID" ]; then
		# Create a new record
		write_log 7 "Creating new record for ${RECORD_NAME}.${DOAMIN_NAME}"
		_RESULT=$(do_rpc_transfer POST AddDomainRecord "DomainName=${DOAMIN_NAME}&RR=${RECORD_NAME}&Type=${RECORD_TYPE}&Value=${VALUE}")
		if [ -z "$_RESULT" ]; then
			write_log 14 "Failed to create new record for ${RECORD_NAME}.${DOAMIN_NAME}"
			return
		fi
		write_log 7 "Created new record for ${RECORD_NAME}.${DOAMIN_NAME}: ${VALUE}"
	else
		# Update the existing record
		write_log 7 "Updating record for ${RECORD_NAME}.${DOAMIN_NAME}"
		_RESULT=$(do_rpc_transfer POST UpdateDomainRecord "RecordId=${RECORD_ID}&RR=${RECORD_NAME}&Type=${RECORD_TYPE}&Value=${VALUE}")
		if [ -z "$_RESULT" ]; then
			write_log 14 "Failed to update record for ${RECORD_NAME}.${DOAMIN_NAME}"
			return
		fi
		write_log 7 "Updated record for ${RECORD_NAME}.${DOAMIN_NAME}: ${VALUE}"
	fi
}

main() {
	local record_type

	# Dependency checking
	[ -z "${CURL}" ] && write_log 14 "Aliyun DNS requires cURL"
	[ -z "$(openssl version)" ] && write_log 14 "Aliyun DNS update requires openssl-utils"

	# Argument parsing
	[ -z ${param_opt} ] && ttl=3600 || ttl="${param_opt}"
	[ $use_ipv6 -eq 0 ] && record_type="A" || record_type="AAAA"

	# Sanity checks
	[ -z "$domain" ] && write_log 14 "Service section not configured correctly! Missing 'domain'"
	[ -z "$username" ] && write_log 14 "Service section not configured correctly! Missing 'username'"
	[ -z "$password" ] && write_log 14 "Service section not configured correctly! Missing 'password'"

	# Push the record!
	maindomain=$(echo "$domain" | awk -F'.' '{print $(NF-1)"."$NF}')
	subdomain=$(echo "$domain" | sed "s/$maindomain//" | sed 's/.$//')
	[ -z "$subdomain" ] && subdomain="@"
	write_log 7 "Updating $subdomain.$maindomain"

	update_record $maindomain $subdomain $record_type $__IP
}

main
