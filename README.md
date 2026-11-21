# sond-publish-action

Publishes a verified RFC-0018 bundle to a Sond registry (dist.sond.dev by
default). The publisher signs the entry with an Ed25519 key, the registry adds
it to its transparency log, and the action then checks the inclusion proof
against the log's signed tree head before it succeeds.

The client (`sondpkg`) comes from
[fredyk/sond-distro-pkg](https://github.com/fredyk/sond-distro-pkg). When
[fredyk/sond-build-action](https://github.com/fredyk/sond-build-action) ran
earlier in the job, its checkout is reused.

## Usage

```yaml
      - id: sond
        uses: fredyk/sond-build-action@v1
        with:
          name: toybox
          version: 0.8.11
          license: 0BSD
          upstream: github.com/landley/toybox@<sha40>
          build: make CC="$SOND_CC" toybox && install -D toybox "$SOND_PAYLOAD/bin/toybox"
      - uses: fredyk/sond-publish-action@v1
        with:
          bundle: ${{ steps.sond.outputs.bundle }}
          token: ${{ secrets.SOND_PUBLISH_TOKEN }}
          signing-key: ${{ secrets.SOND_SIGNING_KEY }}
```

The first publish of a name pins its key (trust on first use): later versions
of that name are accepted only when signed by the same key. A version that is
already published is never repointed to another object.

## Inputs

| input | required | default | meaning |
|---|---|---|---|
| `bundle` | yes | | bundle directory from sond-build-action |
| `source-bundle` | no | | the `source_bundle` output of sond-build-action (copyleft packages): published and verified before `bundle` |
| `token` | yes | | registry publish token, scoped to this package |
| `signing-key` | yes | | private key file written by `sondpkg keygen` |
| `url` | no | `https://dist.sond.dev` | registry base URL |
| `log-key` | no | dist.sond.dev's log key | public key the inclusion proof is checked against |
| `distro-pkg-ref` | no | `main` | branch or tag of sond-distro-pkg |

## Outputs

| output | meaning |
|---|---|
| `object` | published object, `sha256:<hex>` |
| `log_index` | index of the entry in the transparency log |
| `tree_size` | size of the tree the inclusion proof was checked against |

Publishing the same name, version and object again is not an error: the action
leaves a notice and still verifies the existing entry.

## Keys

```sh
sondpkg keygen --out publisher.key   # prints the public key in hex
```

Store the file's contents as the `SOND_SIGNING_KEY` secret of the repository.
Secrets are written to a mode 0600 temporary directory and removed when the
step ends.

## Tests

```sh
bash tests/test-action.sh
```

## License

MIT
