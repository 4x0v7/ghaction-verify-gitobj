[![](https://img.shields.io/github/v/tag/4x0v7/ghaction-verify-gitobj)](https://github.com/4x0v7/ghaction-verify-gitobj)


# Verify git object

This action can be used to validate a commit or tag is signed.


## Usage
```yaml
name: Verify tag
on:
  push:

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout
        uses: actions/checkout@v2
      -
        name: Verify
        uses: 4x0v7/ghaction-verify-gitobj@main
        with:
          # repo: https://github.com/4x0v7/ghaction-verify-gitobj
          tag: v0.0.0
          # commit: c32c14ac334a486b319135dfbd22a8be360745dd
          # trusted_signer_pubkey: '0x5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23'
          pubkey_url: https://github.com/web-flow.gpg
          pubkey_url_hash: cd8772f507a2a56eab2c0b3c78e43c3d7aa2fe290a5e844c271dbd56ca4ded33

```
