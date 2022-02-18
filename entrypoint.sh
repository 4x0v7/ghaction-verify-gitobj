#!/bin/sh

set -e

apk add --no-cache --quiet ca-certificates gawk git gnupg

## funtions

_print_actions_debug() {
  echo "::debug::${1}"
}

_print_actions_debug "got INPUT_REPO: ${INPUT_REPO}"
_print_actions_debug "got INPUT_REF: ${INPUT_REF}"
_print_actions_debug "got INPUT_TAG: ${INPUT_TAG}"
_print_actions_debug "got INPUT_PUBKEY: ${INPUT_PUBKEY}"
_print_actions_debug "got INPUT_PUBKEY_URL: ${INPUT_PUBKEY_URL}"
_print_actions_debug "got INPUT_PUBKEY_URL_HASH: ${INPUT_PUBKEY_URL_HASH}"


_actions_start_group() {
  echo "::group::My title"
  echo "Inside group"
  echo "::endgroup::"

}


_gpg_permissions_fix() {
  # To fix the " gpg: WARNING: unsafe permissions on homedir '/home/path/to/user/.gnupg' " error
  # Make sure that the .gnupg directory and its contents is accessibile by your user.
  mkdir -p ~/.gnupg
  chown -R $(whoami) ~/.gnupg/

  # Also correct the permissions and access rights on the directory
  # chmod 600 ~/.gnupg/*
  chmod 700 ~/.gnupg
}

_has_commit_or_tag() {
  if [ -n "${INPUT_REF}" ] && [ -n "${INPUT_TAG}" ]; then
    echo '{"func": "_has_commit_or_tag()","exit_code": 1,"msg": "ERR:  Please specify a commit, or a tag, but not both"}'
    # exit 1
  elif [ -z "${INPUT_REF}" ] && [ -n "${INPUT_TAG}" ]; then
    # echo "got a tag"
    echo '{"type": "tag","ref": "","exit_code": 0,"msg": ""}' | jq -r ".ref |= \"$INPUT_TAG\""
  elif [ -n "${INPUT_REF}" ] && [ -z "${INPUT_TAG}" ]; then
    # echo "got a commit"
    echo '{"type": "commit","ref": "","exit_code": 0,"msg": ""}' | jq -r ".ref |= \"$INPUT_REF\""
  else
    echo '{"func": "_has_commit_or_tag()","exit_code": 1,"msg": "ERR:  Please specify a commit, or a tag"}'
  fi
}

_has_pubkey_or_url() {
  if [ -n "${INPUT_PUBKEY}" ] && [ -n "${INPUT_PUBKEY_URL}" ]; then
    # echo "ERR:  Please specify a trusted signer public key, or a url, but not both"
    echo '{"func": "_has_pubkey_or_url()","exit_code": 1,"msg": "ERR:  Please specify a trusted signer public key, or a url, but not both"}'
    # exit 1
  elif [ -z "${INPUT_PUBKEY}" ] && [ -n "${INPUT_PUBKEY_URL}" ]; then
    echo '{"type": "url","exit_code": 0,"msg": ""}'
    # KEY=$(echo "${INPUT_PUBKEY}" | tr -d '0x')
    # export INPUT_PUBKEY

    # gpg --batch --recv "${INPUT_PUBKEY}" 2>&1
    # gpg --list-keys --fingerprint --with-colons 2>&1 | grep scSC | awk -F: '{print "trusted-key "$5}' >> ~/.gnupg/gpg.conf
    # gpg --update-trustdb 2>&1 | grep 'gpg: key'
    # _get_signer_info
    # _set_ouputs
  elif [ -n "${INPUT_PUBKEY}" ] && [ -z "${INPUT_PUBKEY_URL}" ]; then
    echo '{"type": "key","exit_code": 0,"msg": ""}'
    # wget -qO- "${INPUT_PUBKEY_URL}" | gpg --import
    # _get_signer_info
    # _set_ouputs
  else
    echo '{"func": "_has_pubkey_or_url()","exit_code": 1,"msg": "ERR:  Please specify a trusted signer public key, or a url"}'
    # return 1
  fi
}

_has_repo_or_self() {
  true
}

# _get_signer_info() {
#   SIGNER_USER=$(gpg --list-keys --fingerprint --with-colons 2>&1 | grep 'uid:' |  awk -F: '{print $10}' | gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}')
#   SIGNER_EMAIL=$(gpg --list-keys --fingerprint --with-colons 2>&1 | grep 'uid:' |  awk -F: '{print $10}' | gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
# }
_set_ouputs() {
  echo "::set-output name=ref::${GIT_REF}"
  echo "::set-output name=commit::${GIT_COMMIT}"
  echo "::set-output name=signer_name::${SIGNER_NAME}"
  echo "::set-output name=signer_email::${SIGNER_EMAIL}"
  echo "::set-output name=signature_date::${SIGNATURE_DATE}"
  echo "::set-output name=signer_fingerprint::${SIGNER_FINGERPRINT}"
  echo "::set-output name=signer_longid::${SIGNER_LONGID}"
}

_get_tag_type() {
  TT=$(git for-each-ref "refs/tags/$INPUT_TAG" | awk -F' ' '{print $2}')
  echo "${TT}"
}

_known_good_verify() {
  git verify-commit "${INPUT_TAG}"
}

_verify_commit() {

    if [ -n "$1" ]; then
      echo "got an argument: $1"
      unset -v INPUT_REF
      INPUT_REF="$1"
    fi
    # vcmd="git verify-commit ${INPUT_TAG} >&2"
    # if [ $? = 0 ]; then
    if result=$(git verify-commit "${INPUT_REF}" --raw 2>&1); then
      echo "Verify commit successful"
      VERIFY_SUCCESS="$result"
      _parse_success_message
      # echo "$VERIFY_SUCCESS"
      SIGNED_BOOL='true'
      echo "::set-output name=signed::${SIGNED_BOOL}"
      # _set_ouputs
      # _get_signer_info
    else
      echo "Verify commit failed" >&2
      echo "$result"
      echo '{"func": "_verify_commit()","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $result\""
      SIGNED_BOOL='false'
      echo "::set-output name=signed::${SIGNED_BOOL}"
      # exit 1
    fi
}

# need gawk?
_parse_success_message() {
  # REF=$GIT_REF
  SIGNER_NAME=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{ print substr($0, index($0,$4)) }' | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}')
  SIGNER_EMAIL=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{ print substr($0, index($0,$4)) }' | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
  SIGNER_LONGID=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{print $3}') # | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
  SIGNER_FINGERPRINT=$(echo "$VERIFY_SUCCESS" | grep 'VALIDSIG' |  awk -F' ' '{print $3}') # | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
  SIGNATURE_DATE=$(echo "$VERIFY_SUCCESS" | grep 'VALIDSIG' |  awk -F' ' '{print $5}' | jq -r todateiso8601) # | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
  # echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{ print substr($0, index($0,$4)) }' #| gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}'
  # echo "$VERIFY_SUCCESS" | grep 'VALIDSIG' |  awk -F' ' '{print $5}' #| gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}'
  # true
  # echo "$SIG_DATE"
  # echo "1645116261" | jq -r todateiso8601
}

# _get_signer_info() {
#   SIGNER_USER=$(gpg --list-keys --fingerprint --with-colons 2>&1 | grep 'uid:' |  awk -F: '{print $10}' | gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}')
#   SIGNER_EMAIL=$(gpg --list-keys --fingerprint --with-colons 2>&1 | grep 'uid:' |  awk -F: '{print $10}' | gawk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
# }

_verify_tag() {
    # vcmd="git verify-tag ${INPUT_TAG}"
    if result=$(git verify-tag "${INPUT_TAG}" 2>&1); then
      echo "Verify tag successful"
      SIGNED_BOOL='true'
      echo "::set-output name=signed::${SIGNED_BOOL}"
    else
      echo "Verify tag failed" >&2
      SIGNED_BOOL='false'
      echo "$result"
      echo '{"func": "_verify_tag()","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $result\""
      echo "::set-output name=signed::${SIGNED_BOOL}"
    fi
}

_pull_repo() {
  if [ -n "${INPUT_REPO}" ]; then
    # mkdir -p /tmp/repo_to_validate
    echo "Cloing repo ${INPUT_REPO}"
    git clone "${INPUT_REPO}" /tmp/repo_to_validate
    cd /tmp/repo_to_validate || exit
  fi
}

_init_gpg_config() {
  mkdir -p ~/.gnupg
  echo "keyserver hkp://pgp.rediris.es" >> ~/.gnupg/gpg.conf # works, but why? loop afew ks maybe
  # echo "keyserver hkps://keys.openpgp.org" >> ~/.gnupg/gpg.conf
  # echo "keyserver hkp://pgp.mit.edu" >> ~/.gnupg/gpg.conf
}

_sanitize_key() {
  echo "${INPUT_PUBKEY}" | sed 's/^0a//'
}

_import_from_keyserver() {
  echo "Importing from keyserver"
  _init_gpg_config
  if result=$(gpg --batch --recv "${INPUT_PUBKEY}" 2>&1); then
    echo "Import successful"
  else
    echo "Import failed"

    ERROR=$(echo "$result" | tail -1 | sed --expression='s/\"/\\"/g') # escape any quotes for json
    echo '{"type": "-1","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $ERROR\"" | jq -r
    exit 1
  fi
}


_import_from_url() {
  echo "Importing from url"
  if result=$( { wget -qO- "${INPUT_PUBKEY_URL}" | gpg --import; } 2>&1 ); then
  
    echo "Import successful"
  else
    echo "Import failed"


    ERROR=$(echo "$result" | tail -5 | sed --expression='s/\"/\\"/g') # escape any quotes for json
    echo '{"type": "-1","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $ERROR\"" | jq -r
    exit 1
  fi
}

_set_key_trust() {
  echo "Setting key trust"
  gpg --list-keys --fingerprint --with-colons 2>&1 | grep scSC | awk -F: '{print "trusted-key "$5}' >> ~/.gnupg/gpg.conf
}

_update_trustdb() {
  echo "Updating trustdb"
  # gpg --update-trustdb | grep 'gpg: key'
  gpg --update-trustdb 2>&1 | grep 'gpg: key'
  # return 0
}

_check_args() {
  if result=$(_has_pubkey_or_url); then
    if ec=$(echo "$result" | jq -r '.exit_code'); then
      if [ "$ec" = 1 ]; then
        echo "$result" | jq
        exit 1
      fi
    fi
  fi

  if result=$(_has_commit_or_tag); then
    if ec=$(echo "$result" | jq -r '.exit_code'); then
      if [ "$ec" = 1 ]; then
        echo "$result" | jq
        exit 1
      fi
    fi
  fi
}

_import_pubkey() {
  SIGN_KEY=$(_has_pubkey_or_url | jq -r '.type')

  if [ "$SIGN_KEY" = "key" ]; then
    echo "got a key"
    _import_from_keyserver
    # _check_import
    _set_key_trust
    _update_trustdb
  elif [ "$SIGN_KEY" = "url" ]; then
    echo "got a url"
    _import_from_url
    # _set_key_trust
    # _update_trustdb
  fi
}

_verify_all() {
  GIT_OBJ=$(_has_commit_or_tag | jq -r '.type')
  GIT_REF=$(_has_commit_or_tag | jq -r '.ref')
  GIT_COMMIT=$(git rev-parse "$GIT_REF")

  if [ "$GIT_OBJ" = "tag" ]; then
    if [ "$(_get_tag_type)" = "commit" ]; then
      echo "doing a verify-commit cause its a lightweight tag"
      _verify_commit "$INPUT_TAG"
      _set_ouputs
    elif [ "$(_get_tag_type)" = "tag" ]; then
      echo "doing a verify-tag cause its an annotated tag"
      _verify_tag
      _set_ouputs
    fi
  elif [ "$GIT_OBJ" = "commit" ]; then # last case, it's a
      echo "doing a verify-commit cause its a commit"
      _verify_commit "$INPUT_REF"
      _set_ouputs
  fi
}

##########
## Start #
##########

_gpg_permissions_fix
_check_args
# _check_import
_import_pubkey
_pull_repo
_verify_all
# _verify_tag
# _verify_commit


# _import_pubkey() {
#   SIGN_KEY=$(_has_pubkey_or_url | jq -r '.type')

#   if [ "$SIGN_KEY" = "key" ]; then
#     echo "Got a key"
#     _import_from_keyserver
#     # return 0
#   elif [ "$SIGN_KEY" = "url" ]; then
#     echo "Got an url"
#     _import_from_url
#     _set_key_trust
#     _update_trustdb
#   fi
# }

# Pull repo if $INPUT_REPO defined
# Else assume we're checked out already

# if result=$(_has_pubkey_or_url); then
#   if ec=$(echo "$result" | jq -r '.exit_code'); then
#     if [ $ec = 1 ]; then
#       echo "$result" | jq
#       exit 1
#     fi
#   fi
# fi


# if result=$(_has_commit_or_tag); then
#   if ec=$(echo "$result" | jq -r '.exit_code'); then
#     if [ $ec = 1 ]; then
#       echo "$result" | jq
#       exit 1
#     fi
#   fi
# fi


# _has_commit_or_tag
# _has_pubkey_or_url

# _pull_repo
# _import_pubkey
# _verify_all

# _pull_repo









# if [ -z "${INPUT_REPO}" ]; then
#   INPUT_REPO="self"
#   if [ -n "${INPUT_TAG}" ]; then
#     type=$(_get_tag_type)
#     if [ "${type}" = "commit" ]; then
#       vcmd="git verify-commit ${INPUT_TAG}"
#       if $vcmd; then
#         echo "Verify commit successful"
#         SIGNED_BOOL='true'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#       else
#         echo "Verify commit failed" >&2
#         SIGNED_BOOL='false'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#         exit 1
#       fi
#     # get tag
#     elif [ "${type}" = "tag" ]; then
#       vcmd="git verify-tag ${INPUT_TAG}"
#       if $vcmd; then
#         echo "Verify tag successful"
#         SIGNED_BOOL='true'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#       else
#         echo "Verify tag failed" >&2
#         SIGNED_BOOL='false'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#         exit 1
#       fi
#     fi
#   else
#     true
#   fi
# else
#   true
#   # mkdir -p /tmp/repo_to_validate
#   # cd /tmp/repo_to_validate || exit
#   # git clone "${INPUT_REPO}" .
#   # git verify-commit ${INPUT_TAG}
# fi












#     type=$(_get_tag_type)
#     if [ "${type}" = "commit" ]; then


# _get_tag_type
# echo "${INPUT_REPO}"

# Pinning gpg key by validating its sha256
# GPG_KEY_SHASUM="${INPUT_PUBKEY_URL_HASH}"

# test_url_regex='(https?:\/\/)?([\da-z\.-]+)\.([a-z]{2,6})([\/\w\.-]*)*\/?'
# if [ -n "${INPUT_PUBKEY_URL}" ]; then
#   # expr "$INPUT_PUBKEY_URL" : $test_url_regex
#   wget -qO- "${INPUT_PUBKEY_URL}" > /tmp/gpgkeytocheck
#   cat /tmp/gpgkeytocheck | gpg --with-fingerprint 2>&1 | grep 'pub \|uid'
# fi

# if [ -n "${INPUT_REF}" ] && [ -n "${INPUT_TAG}" ]; then
#   echo "ERR:  Please specify a commit, or a tag, but not both"
#   exit 1
# fi

# if [ -n "${INPUT_PUBKEY}" ] && [ -n "${INPUT_PUBKEY_URL}" ]; then
#   echo "ERR:  Please specify a trusted signer public key, or a url, but not both"
#   exit 1
# fi

# mkdir -p ~/.gnupg
# echo "keyserver hkp://pgp.rediris.es" >> ~/.gnupg/gpg.conf # works, but why? loop afew ks maybe
# echo "keyserver hkps://keys.openpgp.org" >> ~/.gnupg/gpg.conf
# echo "keyserver hkp://pgp.mit.edu" >> ~/.gnupg/gpg.conf

# if [ -n "${INPUT_PUBKEY}" ]; then
#   # KEY=$(echo "${INPUT_PUBKEY}" | tr -d '0x')
#   # export INPUT_PUBKEY

#   gpg --batch --recv "${INPUT_PUBKEY}" 2>&1
#   gpg --list-keys --fingerprint --with-colons 2>&1 | grep scSC | awk -F: '{print "trusted-key "$5}' >> ~/.gnupg/gpg.conf
#   gpg --update-trustdb 2>&1 | grep 'gpg: key'
#   _get_signer_info
#   _set_ouputs
# elif [ -n "${INPUT_PUBKEY_URL}" ]; then

#   wget -qO- "${INPUT_PUBKEY_URL}" | gpg --import
#   _get_signer_info
#   _set_ouputs

# else

#   # gpg --list-keys --fingerprint --with-colons 2>&1 | grep 'uid:u' |  awk -F: '{print $10}' | sed 's/.*+<([^>]+)>.*/\1/p'
#   # gpg --list-keys --fingerprint --with-colons | grep 'uid:u' |  awk -F: '{print $10}' | grep -o '.+<([^>]+)>'

#   echo "ERR:  INPUT_PUBKEY_URL or INPUT_PUBKEY must be set"
#   exit 1
#   # _get_signer_info
#   # _set_ouputs

#   # gpg --update-trustdb | grep 'gpg: key'
#   #  \
#   #   && gpg --list-keys --fingerprint --with-colons | grep scESC | awk -F: '{print "trusted-key "$5}' >> ~/.gnupg/gpg.conf
# fi


# if [ -z "${INPUT_REPO}" ]; then
#   INPUT_REPO="self"
#   if [ -n "${INPUT_TAG}" ]; then
#     type=$(_get_tag_type)
#     if [ "${type}" = "commit" ]; then
#       vcmd="git verify-commit ${INPUT_TAG}"
#       if $vcmd; then
#         echo "Verify commit successful"
#         SIGNED_BOOL='true'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#       else
#         echo "Verify commit failed" >&2
#         SIGNED_BOOL='false'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#         exit 1
#       fi
#     # get tag
#     elif [ "${type}" = "tag" ]; then
#       vcmd="git verify-tag ${INPUT_TAG}"
#       if $vcmd; then
#         echo "Verify tag successful"
#         SIGNED_BOOL='true'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#       else
#         echo "Verify tag failed" >&2
#         SIGNED_BOOL='false'
#         echo "::set-output name=signed::${SIGNED_BOOL}"
#         exit 1
#       fi
#     fi
#   else
#     true
#   fi
# else
#   mkdir -p /tmp/repo_to_validate
#   cd /tmp/repo_to_validate || exit
#   git clone "${INPUT_REPO}" .
#   git verify-commit ${INPUT_TAG}
# fi
