#!/bin/sh

set -e

## functions

_print_actions_debug() {
  echo "::debug::${1}"
}

_print_actions_debug "got INPUT_REPO: ${INPUT_REPO}"
_print_actions_debug "got INPUT_REF: ${INPUT_REF}"
_print_actions_debug "got INPUT_TAG: ${INPUT_TAG}"
_print_actions_debug "got INPUT_PUBKEY: ${INPUT_PUBKEY}"
_print_actions_debug "got INPUT_PUBKEY_URL: ${INPUT_PUBKEY_URL}"
_print_actions_debug "got INPUT_PUBKEY_URL_HASH: ${INPUT_PUBKEY_URL_HASH}"

_print_versions() {
  jo type=debug \
    name=versions \
    os="$(cat /etc/os-release)" \
    tool[gpg]="$(gpg --version | head -2)" \
    tool[git]="$(git --version)" \
    tool[jq]="$(jq --version)" \
    tool[yq]="$(yq --version)" \
    tool[jo]="$(jo -V)"
}
_print_versions | jq | yq e -P '.' -

_actions_start_group() {
  echo "::group::$1"
  echo "$2"
  echo "::endgroup::"
}

# argparsing logic
_has_commit_or_tag() {
  if [ -n "${INPUT_REF}" ] && [ -n "${INPUT_TAG}" ]; then
    echo '{"func": "_has_commit_or_tag()","exit_code": 1,"msg": "ERR:  Please specify a ref, or a tag, but not both"}' | jq
  elif [ -z "${INPUT_REF}" ] && [ -n "${INPUT_TAG}" ]; then
    echo '{"type": "tag","ref": "","exit_code": 0,"msg": ""}' | jq -r ".ref |= \"$INPUT_TAG\"" | jq
  elif [ -n "${INPUT_REF}" ] && [ -z "${INPUT_TAG}" ]; then
    echo '{"type": "commit","ref": "","exit_code": 0,"msg": ""}' | jq -r ".ref |= \"$INPUT_REF\"" | jq
  else
    echo '{"func": "_has_commit_or_tag()","exit_code": 1,"msg": "ERR:  Please specify a ref, or a tag"}' | jq
  fi
}

_has_pubkey_or_url() {
  if [ -n "${INPUT_PUBKEY}" ] && [ -n "${INPUT_PUBKEY_URL}" ]; then
    echo '{"func": "_has_pubkey_or_url()","exit_code": 1,"msg": "ERR:  Please specify a public key, or a url, but not both"}'
    # exit 1
  elif [ -z "${INPUT_PUBKEY}" ] && [ -n "${INPUT_PUBKEY_URL}" ]; then
    # echo '{"type": "url","exit_code": 0,"msg": ""}' 
    jo type=url \
      exit_code=0 \
      msg=""
  elif [ -n "${INPUT_PUBKEY}" ] && [ -z "${INPUT_PUBKEY_URL}" ]; then
    # echo '{"type": "key","exit_code": 0,"msg": ""}'
    jo type=key \
      exit_code=0 \
      msg=""
  else
    jo func='_has_pubkey_or_url()' \
      exit_code=1 \
      ERR="ERR:  Please specify a public key, or a url"
  fi
}

_parse_success_message() {
  SIGNER_NAME=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{ print substr($0, index($0,$4)) }' | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[1]}')
  SIGNER_EMAIL=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{ print substr($0, index($0,$4)) }' | awk 'match($0, /(.+)<([^>]+)>/, a) {print a[2]}')
  SIGNATURE_DATE=$(echo "$VERIFY_SUCCESS" | grep 'VALIDSIG' |  awk -F' ' '{print $5}' | jq -r todateiso8601)
  SIGNER_FINGERPRINT=$(echo "$VERIFY_SUCCESS" | grep 'VALIDSIG' |  awk -F' ' '{print $3}')
  SIGNER_LONGID=$(echo "$VERIFY_SUCCESS" | grep 'GOODSIG' |  awk -F' ' '{print $3}')
}

_set_ouputs() {
  echo "::set-output name=ref::${GIT_REF}"
  echo "::set-output name=commit::${GIT_COMMIT}"
  echo "::set-output name=signer_name::${SIGNER_NAME}"
  echo "::set-output name=signer_email::${SIGNER_EMAIL}"
  echo "::set-output name=signature_date::${SIGNATURE_DATE}"
  echo "::set-output name=signer_fingerprint::${SIGNER_FINGERPRINT}"
  echo "::set-output name=signer_longid::${SIGNER_LONGID}"
}

_verify_commit() {
    if [ -n "$1" ]; then
      unset -v INPUT_REF
      INPUT_REF="$1"
    fi
    if result=$(git verify-commit "${INPUT_REF}" --raw 2>&1); then
      echo "Verify commit successful"
      VERIFY_SUCCESS="$result"
      jo -p func='_verify_commit()' \
        type=result \
        exit_code=0 \
        msg="$result" |  yq e '... style="" | .msg style="literal"' -
      _parse_success_message
      SIGNED_BOOL='true'
      echo "::set-output name=signed::${SIGNED_BOOL}"
    else
      echo "Verify commit failed"
      jo  func='_verify_commit()' \
        type=result \
        exit_code=1 \
        msg="$result" | jq -r| yq e '... style="" | .msg style="literal"' -
      SIGNED_BOOL='false'
      echo "::set-output name=signed::${SIGNED_BOOL}"
    fi
}

_verify_tag() {
    if result=$(git verify-tag "${INPUT_TAG}" --raw 2>&1); then
      echo "Verify tag successful"
      VERIFY_SUCCESS="$result"
      _parse_success_message
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

_gpg_permissions_fix() {
  # To fix the " gpg: WARNING: unsafe permissions on homedir '/home/path/to/user/.gnupg' " error
  # Make sure that the .gnupg directory and its contents is accessibile by your user.
  mkdir -p ~/.gnupg
  chown -R "$(whoami)" ~/.gnupg/

  # Also correct the permissions and access rights on the directory
  # chmod 600 ~/.gnupg/*
  chmod 700 ~/.gnupg
}

_init_gpg_config() {
  _gpg_permissions_fix
  mkdir -p ~/.gnupg
  touch ~/.gnupg/trustdb.gpg
  touch ~/.gnupg/pubring.kbx # newer default syntax in some versions of gnupg
  echo "keyserver hkp://pgp.rediris.es" >> ~/.gnupg/gpg.conf # works, but why? loop afew ks maybecat 
  # echo "keyserver hkps://keyserver.ubuntu.com" >> ~/.gnupg/gpg.conf
  # echo "keyserver hkps://keys.openpgp.org" >> ~/.gnupg/gpg.conf
  # echo "keyserver hkp://keys.gnupg.net " >> ~/.gnupg/gpg.conf
  # echo "keyserver hkps://pgp.surf.nl" >> ~/.gnupg/gpg.conf
  # echo "keyserver hkp://pgp.mit.edu" >> ~/.gnupg/gpg.conf
}

_opengpg_api_getkey() {
  if [ "$(echo ${#INPUT_PUBKEY})" = 16 ]; then
    echo "got a long key id"
    wget -qO- "https://keys.openpgp.org/vks/v1/by-keyid/$INPUT_PUBKEY" | gpg --import
  else
    echo "got a key fingerprint"
    wget -qO- "https://keys.openpgp.org/vks/v1/by-fingerprint/$INPUT_PUBKEY" | gpg --import
  fi
}


_import_from_keyserver() {
  echo "Importing from keyserver"
  # _init_gpg_config
  # if result=$(_opengpg_api_getkey); then
  if result=$(gpg --batch --recv-key --yes "${INPUT_PUBKEY}" 2>&1); then
    echo "Import successful"
    jo -p func='_import_from_keyserver()' \
      type=result \
      msg="$result" | jq | yq e -P '.' -
  else
    echo "Import failed"

    ERROR=$(echo "$result" | tail -5 | sed --expression='s/\"/\\"/g') # escape any quotes for json
    echo '{"func": "_import_from_keyserver()","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $ERROR\"" | jq -r \
      | yq e -P '.' -
    exit 1
  fi
}

_import_from_url() {
  echo "Importing from url"
  # _init_gpg_config
  if result=$( { wget -qO- "${INPUT_PUBKEY_URL}" | gpg --import; } 2>&1 ); then
    echo "Import successful"
    jo -p func='_import_from_keyserver()' \
      type=result \
      msg="$result" | jq | yq e -P '.' -
  else
    echo "Import failed"
    ERROR=$(echo "$result" | tail -5 | sed --expression='s/\"/\\"/g') # escape any quotes for json
    echo '{"func": "_import_from_url()","exit_code": 1,"msg": "ERR:  =--"}' | jq -r ".msg |= \"ERR:  $ERROR\"" | jq -r | yq e -P '.' -
    exit 1
  fi
}

_list_fingerprints() {
  __runcmd='gpg --list-keys --fingerprint --with-colons'

  if __cmd=$(eval "$__runcmd" 2>&1); then
  jo func='_list_fingerprints()' \
    type=result \
    command="$__runcmd"  \
    internal=true \
    no_yq_pretty=true \
    exit_code=0 \
    stdout="$__cmd"
  fi

}



    # if result=$(git verify-commit "${INPUT_REF}" --raw 2>&1); then
    #   echo "Verify commit successful"
    #   VERIFY_SUCCESS="$result"
    #   jo -p func='_verify_commit()' \
    #     type=result \
    #     exit_code=1 \
    #     msg="$result" | jq | yq e -P '.' -


_set_key_trust() {
  echo "Setting key trust"

  # List fingerprints, capture result
  if result=$(_list_fingerprints); then
    jo -p func='_set_key_trust()' \
      type=result \
      called_cmd='_list_fingerprints' \
      exit_code=0 \
      result="$result" \
      stdout="$(echo $result | yq e '.stdout style="literal"' - | jq -r .stdout)"  | yq e -P '.' -
  fi

      # Echo key to set ultimate trust
      # echo "$result"
      # echo "$result" | yq e '.stdout style="literal"' - | jq -r .stdout

      # echo "$result" #| yq e '.result.stdout style="literal"' - #| jq -r .stdout
      

      # echo $result | yq e '... style="" | .stdout style="literal"' -
      # echo -n $result | yq e -P '.stdout' -
      # __DEBUGSTOP
      echo "$result" | jq -r .stdout | grep pub | awk -F: '{print "trusted-key "$5}' >> ~/.gnupg/gpg.conf
      # __runcmd='echo "$result" | jq -r .msg | grep pub | awk -F: '\''{print "trusted-key "$5}'\'' >> ~/.gnupg/gpg.conf'

      jo func='_set_key_trust()' \
        type=result \
        filecontent='~/.gnupg/gpg.conf' \
        msg="$(cat  /root/.gnupg/gpg.conf)" | yq e -P '.' -
        # msg="$(cat ~/.gnupg/gpg.conf 2>&1)" | jq -r | yq e -P '.' -

      # if __cmd=$(eval "$__runcmd"); then
      # jo func='_set_key_trust()' \
      #   type=result \
      #   command="$__runcmd"  \
      #   internal=true \
      #   no_yq_pretty=true \
      #   msg="$__cmd" | yq e -P '.' -
      # fi

      # jo func='_set_key_trust()' \
      #   type=result \
      #   cmd='set_ultimate_trust___' \
      #   msg="$set_ult" | jq -r | yq e -P '.' -

  # __runcmd='gpg --list-keys --fingerprint --with-colons 2>&1'

  # if __cmd=$(eval "$__runcmd"); then
  # jo func='_list_fingerprints()' \
  #   type=result \
  #   command="$__runcmd"  \
  #   internal=true \
  #   no_yq_pretty=true \
  #   msg="$__cmd"
  # fi


    # filecontent='~/.gnupg/gpg.conf' \
  #     type=result \
  #     exit_code=0 \
  #     msg="$result" | yq e -P '.' -
  # echo $result | yq e -P '.' -
  # IMPORTED_KEYS=$(gpg --list-keys --fingerprint --with-colons 2>&1)
    # msg="$(cat ~/.gnupg/gpg.conf 2>&1)" | jq -r | yq e -P '.' -

  # will show ultimate trust, as this cmd is run after first listing the keys
  # jo func='_set_key_trust()' \
  #   type=keysfpr \
  #   msg="$(gpg --list-keys --fingerprint)" | yq e -P '.' -


  # jo func='_set_key_trust()' \
  #   type=keys \
  #   msg="$IMPORTED_KEYS" | yq e -P '.' -
}

_update_trustdb() {
  echo "Updating trustdb"
  __runcmd='gpg --update-trustdb 2>&1'

  if __cmd=$(eval "$__runcmd" 2>&1); then
  jo func='_update_trustdb()' \
    type=result \
    command="$__runcmd"  \
    internal=true \
    no_yq_pretty=false \
    exit_code=0 \
    stdout="$__cmd" \
    | jq | yq e -P '.' -
  fi
}

_list_keys() {
  echo "Listing keys"
  __runcmd='gpg --list-keys --fingerprint'

  if __cmd=$(eval "$__runcmd" 2>&1); then
  jo func='_list_keys()' \
    type=result \
    command="$__runcmd"  \
    internal=true \
    no_yq_pretty=false \
    exit_code=0 \
    stdout="$__cmd" \
    | jq | yq e -P '.' -
  fi
}

_import_pubkey() {
  SIGN_KEY=$(_has_pubkey_or_url | jq -r '.type')

  if [ "$SIGN_KEY" = "key" ]; then
    echo "got a key"
    _import_from_keyserver
    _set_key_trust
    _update_trustdb
    _list_keys
  elif [ "$SIGN_KEY" = "url" ]; then
    echo "got a url"
    _import_from_url
    _set_key_trust
    _update_trustdb
    _list_keys
  fi
}

_pull_repo() {
  if [ -n "${INPUT_REPO}" ]; then
    echo "Cloning repo ${INPUT_REPO}"
    git clone "${INPUT_REPO}" /tmp/repo_to_validate
    cd /tmp/repo_to_validate || exit
  fi
}

_get_tag_type() {
  TT=$(git for-each-ref "refs/tags/$INPUT_TAG" | awk -F' ' '{print $2}')
  echo "${TT}"
}

_verify_all() {
  GIT_OBJ=$(_has_commit_or_tag | jq -r '.type')
  GIT_REF=$(_has_commit_or_tag | jq -r '.ref')
  GIT_COMMIT=$(git rev-parse "$GIT_REF")

  if [ "$GIT_OBJ" = "tag" ]; then
    if [ "$(_get_tag_type)" = "commit" ]; then
      echo "doing a verify-commit cause its a lightweight tag"
      echo '::echo::on'
      _verify_commit "$INPUT_TAG"
      _set_ouputs
    elif [ "$(_get_tag_type)" = "tag" ]; then
      echo "doing a verify-tag cause its an annotated tag"
      echo '::echo::on'
      _verify_tag
      _set_ouputs
    fi
  elif [ "$GIT_OBJ" = "commit" ]; then
      echo "doing a verify-commit cause its a commit"
      echo '::echo::on'
      _verify_commit "$INPUT_REF"
      _set_ouputs
  fi
}

##########
## Start #
##########

_init_gpg_config
_check_args
_import_pubkey
_pull_repo
_verify_all
