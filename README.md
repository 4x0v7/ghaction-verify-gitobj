[![](https://img.shields.io/github/v/tag/4x0v7/ghaction-verify-gitobj)](https://github.com/4x0v7/ghaction-verify-gitobj)
[![Test Action](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/test.yml/badge.svg)](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/test.yml)
[![Verify Action](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/ci.yml/badge.svg)](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/ci.yml)
[![Verify Docs](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/docs.yml/badge.svg)](https://github.com/4x0v7/ghaction-verify-gitobj/actions/workflows/docs.yml)

# Verify git object

> This action validates a commit or tag, in a given repo, is signed by a given key

## Usage

```yaml
with:
  ref: 4f93cda5846bd5a42044522ca055d7b53d3e6af8
```

```yaml
with:
  tag: v4.0.7
```

Provide a git **ref** to verify.
This can be a commit sha, tag or other reference

These are all valid refs:

- refs/heads/main
- HEAD
- v0.1.0
- 2965f6b

## Tags

Use **tag** rather than ref when you have an annotated tag. Lightweight tags are simply pointers to commits and can be supplied to **ref** _or_ **tag**

`tag:` will verify annotated tags, as well as lightweight tags.
Passing an annotated tag to **ref** will produce an error

## Keys

Lookup a public key and import it

```yaml
with:
  pubkey: 4AEE18F83AFDEB23
```

Or provide a url to the key

```yaml
with:
  pubkey_url: https://github.com/web-flow.gpg
```

> `pubkey` and `pubkey_url` are mutually exclusive. Providing a key _and_ a url will produce an error

Public keys can be provided either directly, or as a url to a key.
The GitHub web-flow commit signing key is used by default. See the [documentation](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)

Set `pubkey_url:` to the url of a valid public key

Public keys can be imported by setting `pubkey:` to a valid public key.
keys can be in one of 3 possible formats

- key fingerprint (eg. 5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23)
- long key id (eg. 4AEE18F83AFDEB23)
- hexadecimal notation (eg. '0x5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23')

> Note that the hexadecimal notation must be enclosed in single quotes so yaml has a string

## Repo

By default, it is assumed the currently checked out repository is being verified.
Checkout a different repository by setting `repo:`

```yaml
with:
  repo: https://github.com/github/platform-samples
```

## Output

A number of outputs are generated from the commit signature. Reference the [action.yml](./action.yml)

```sh
::set-output name=signed::true
::set-output name=ref::37ae55f6942b62b6801d1656d7b51e6aaa9aab27
::set-output name=commit::37ae55f6942b62b6801d1656d7b51e6aaa9aab27
::set-output name=signer_name::GitHub (web-flow commit signing)
::set-output name=signer_email::noreply@github.com
::set-output name=signature_date::2021-12-02T18:02:44Z
::set-output name=signer_fingerprint::5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23
::set-output name=signer_longid::4AEE18F83AFDEB23
```

## Example

```yaml
# .github/workflows/ci.yml

name: Verify Action

on:
  push:
  repository_dispatch:

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout
        uses: actions/checkout@v2
      -
        name: Verify
        uses: 4x0v7/ghaction-verify-gitobj@v0.2.0
        with:
          repo: https://github.com/github/platform-samples
          ref: 37ae55f6942b62b6801d1656d7b51e6aaa9aab27
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master

```

## Tests

See the [test workflow](./.github/workflows/test.yml)
