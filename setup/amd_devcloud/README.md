# AMD Developer Cloud Manual Provisioning

This guide is the canonical provider-side path for manually provisioning the
experimental AMD Developer Cloud environment used by this repository. It uses
DigitalOcean's `doctl` client with AMD's DevCloud API endpoint, but it is not an
instance-lifecycle manager and `doctl` is not a guest-side ROCm dependency.

The provider discovery, create, firewall-attachment, inspection, and delete
commands below were accepted from an Ubuntu 24.04 x86-64 control system with
`doctl` 1.177.0 on 2026-10-03 and 2026-10-04. Account entitlements, regions,
prices, images, and private size slugs can change. Discover them again before
every paid create rather than treating this receipt as a permanent provider
promise.

## Non-authoritative Snap-free `doctl` installation example

The project does not require or recommend Snap. DigitalOcean's current
[installation guide](https://docs.digitalocean.com/reference/doctl/how-to/install/)
and the selected upstream release are always authoritative for obtaining
`doctl`; the inline example below is not. Cross-check both upstream sources
immediately before using the example, even when retaining the same version and
platform. Stop if the documented archive name, checksum-manifest name or
format, release version, or installation guidance no longer agrees.

The example is intentionally limited to Ubuntu 24.04 x86-64 and the official
`doctl` 1.177.0 Linux amd64 archive. It pins that release, verifies the archive
against the checksum manifest published with the same release, and installs it
for the current user without `sudo`, package-manager changes, or shell-startup
edits. The exact block has received static shell review but has not yet been
executed end to end as written. It is not installation guidance for another OS,
architecture, release, update, or concurrent installation. See the upstream
[`v1.177.0` release](https://github.com/digitalocean/doctl/releases/tag/v1.177.0)
for the pinned artifacts.

```bash
(
  set -euo pipefail

  doctl_version=1.177.0
  doctl_asset="doctl-${doctl_version}-linux-amd64.tar.gz"
  doctl_manifest="doctl-${doctl_version}-checksums.sha256"

  if [ -e "${HOME}/.local/bin/doctl" ] ||
    [ -L "${HOME}/.local/bin/doctl" ]; then
    echo "ERROR: ${HOME}/.local/bin/doctl already exists; inspect it instead of overwriting it." >&2
    exit 1
  fi
  doctl_download_dir="$(mktemp --directory)"
  printf 'doctl download directory: %s\n' "${doctl_download_dir}"

  curl --fail --location --show-error \
    --output "${doctl_download_dir}/${doctl_manifest}" \
    "https://github.com/digitalocean/doctl/releases/download/v${doctl_version}/${doctl_manifest}"

  curl --fail --location --show-error \
    --output "${doctl_download_dir}/${doctl_asset}" \
    "https://github.com/digitalocean/doctl/releases/download/v${doctl_version}/${doctl_asset}"

  cd "${doctl_download_dir}"
  awk -v asset="${doctl_asset}" \
    'NF == 2 && $2 == asset { print }' "${doctl_manifest}" \
    > "${doctl_asset}.sha256"
  test "$(wc --lines < "${doctl_asset}.sha256")" -eq 1
  sha256sum --check "${doctl_asset}.sha256"
  test "$(tar --list --gzip --file "${doctl_asset}")" = doctl
  tar --extract --gzip --file "${doctl_asset}"
  test -f doctl
  test ! -L doctl
  test -x doctl
  ./doctl version | grep --fixed-strings --line-regexp \
    "doctl version ${doctl_version}-release"

  install --directory --mode=0755 "${HOME}/.local/bin"
  install --mode=0755 doctl "${HOME}/.local/bin/doctl"

  "${HOME}/.local/bin/doctl" version
)
```

The two release files come through the same GitHub HTTPS channel. This
checksum detects corruption or mismatched bytes; it is not independent
publisher authentication. The commands deliberately stop if the destination
already exists so they do not overwrite an installation that has not been
reviewed. The printed temporary directory is left available for inspection
and may be removed manually after the installation is accepted. This small
fresh-install example does not inherit the separate unpublished installer's
update, atomic replacement, concurrency, destination-hardening, architecture,
or test-suite contract.

The rest of this guide invokes the binary by its absolute user-local path, so
`${HOME}/.local/bin` does not have to be added to persistent `PATH`.

## Create a narrowly scoped API context

Generate the token through the AMD DevCloud account's **Manage Personal Access
Tokens** page. Do not use an ordinary DigitalOcean account or assume its
resources and entitlements are interchangeable with AMD DevCloud.

The accepted manual create, inspect, and delete path used these custom scopes:

- `account:read`
- `actions:read`
- `regions:read`
- `sizes:read`
- `image:read`
- `snapshot:read`
- `vpc:read`
- `droplet:read`
- `droplet:create`
- `droplet:delete`
- `ssh_key:read`

Add these only when the corresponding step is needed:

- `ssh_key:create` permits importing a local public key when no suitable
  account key exists. Include it when creating the token if key import may be
  necessary because token scopes cannot later be edited.
- `firewall:read` and `firewall:update` permit discovering an existing cloud
  firewall and attaching the new Droplet to it.
- `firewall:create` is additionally needed only if the user deliberately
  chooses to create a cloud firewall through the API. Firewall creation was
  not exercised against the AMD endpoint in this acceptance round, and this
  guide does not supply an unvalidated creation command. Do not add
  `firewall:delete` unless the user's separate firewall-management workflow
  genuinely needs deletion.

This is not an exhaustive scope recipe for tags, monitoring, backups, volumes,
or other provider features. If a user adds one of those features, they must
review its current API operations and grant only the additional scopes needed
for that workflow. Do not respond to an unrelated permission error by granting
global Full Access by default. DigitalOcean documents the current dependency
relationships in its [API token scope reference](https://docs.digitalocean.com/reference/api/scopes/).

Initialize a named context and paste the token only at the interactive prompt:

```bash
doctl_bin="${HOME}/.local/bin/doctl"
devcloud_api_url="https://api.devcloud.amd.com"
devcloud_context="amd-devcloud-provisioning"

"${doctl_bin}" auth init --context "${devcloud_context}"
```

Do not put the token on a command line, in this repository, in retained logs,
or in environment receipts. Do not enable `--trace` while handling a real
account. Every provider-resource command below includes both the named context
and the AMD endpoint explicitly. Omitting the endpoint queries the ordinary
DigitalOcean API and can expose a different size catalog and price.
The three shell variables above contain no token, but they must be redefined
when continuing the workflow from a new local shell.

## Discover account-visible resources

Run the read-only commands before filling in any create parameters:

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  account get

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute region list \
  --format Slug,Name,Available

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute size list \
  --output json

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute image list-distribution \
  --format ID,Distribution,Slug,Public,MinDisk

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute ssh-key list \
  --format ID,Name,FingerPrint

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet list \
  --gpus \
  --format ID,Name,Region,Image,Status
```

Account output and Droplet listings can contain identifying information and
public addresses. Inspect them locally; do not paste unredacted output into
repository files, issues, or public acceptance logs.

The accepted environment used size `gpu-mi300x1-192gb-devcloud` and image
`ubuntu-24-04-x64`. Continue on the validated path only when the current AMD
endpoint still exposes that MI300X size and Ubuntu 24.04 Bare OS image. Select
an available region shown by the current account; `atl1` was only the observed
2026-10-03 region, not a universal requirement. Compare the API-visible price
and the DevCloud portal before creating, confirm sufficient account credit or
funding, and set a time and cost budget for the session. Stop and investigate
material disagreement instead of substituting a public DigitalOcean GPU size.

## Select or import an SSH key

If `compute ssh-key list` shows the intended public key, record its ID or
fingerprint for the create command. Do not assume every account already has a
suitable key.

If a dedicated key pair is needed, create it locally with a descriptive path
and protect the private key. The following filenames are examples and may be
customized:

```bash
ssh_private_key_file="${HOME}/.ssh/amd_devcloud_local_access"
ssh_public_key_file="${ssh_private_key_file}.pub"

ssh-keygen \
  -t ed25519 \
  -f "${ssh_private_key_file}" \
  -C amd-devcloud-local-access
```

Import only the `.pub` file, using a customizable account-visible name:

```bash
ssh_key_name="amd-devcloud-local-access"

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute ssh-key import "${ssh_key_name}" \
  --public-key-file "${ssh_public_key_file}" \
  --format ID,Name,FingerPrint
```

Never upload, print, or commit the private-key file. Importing a public key
does not change existing Droplets. The
[`ssh-key import` reference](https://docs.digitalocean.com/reference/doctl/reference/compute/ssh-key/import/)
documents the provider operation.

## Decide on the optional provider firewall

The repository requires its guest-side UFW baseline, which setup applies only
after conservative admission checks. A DigitalOcean cloud firewall is a
separate, optional defense-in-depth layer; it does not replace UFW.

For this SSH-only bootstrap workflow, a conservative cloud-firewall design is:

- allow inbound TCP port 22 only from an operator-controlled source network
  when that network can be identified and maintained reliably;
- do not add inbound HTTP, HTTPS, ROCm, or workload ports merely for bootstrap;
- retain enough outbound access for DNS, time synchronization, Ubuntu and AMD
  repositories, Git hosting, and Python package sources; and
- inspect every firewall applied to the Droplet because combined rules can
  produce a broader effective policy than any one firewall suggests.

DigitalOcean cloud firewalls are stateful, so allowed outbound connections do
not require matching inbound response rules. DigitalOcean's current
[rule documentation](https://docs.digitalocean.com/products/networking/firewalls/how-to/configure-rules/)
is authoritative for rule semantics and explains how cloud rules interact
with host firewalls. This repository has not validated a narrowly restricted
egress policy, so it does not prescribe one. Users who restrict egress must
inventory and test the external services their selected setup path needs.

This guide does not create or reconcile general firewall rules, discover the
user's public source address, or publish an address. If an appropriate
account-owned cloud firewall already exists, inspect its inbound and outbound
rules locally before recording its ID:

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute firewall list \
  --format ID,Name,Status,InboundRules,OutboundRules
```

An SSH allowlist must match the operator's current network path. Treat that
source address as private operational data and do not place it in repository
examples, issues, or retained public logs. A changed public address can lock
the operator out; verify and deliberately update the provider rule when the
network path changes. The provider's current
[SSH troubleshooting guidance](https://docs.digitalocean.com/support/how-to-troubleshoot-ssh-connectivity-issues/)
documents that failure mode. Avoiding unnecessary publication is data
minimization, not a substitute for the firewall, key-only SSH authentication,
or other access controls.

After attaching an existing firewall, confirm its successful association with
`compute firewall list-by-droplet` as shown below. Then prove root SSH access
and, after the root handoff, prove a separate ordinary-user SSH login before
ending the root session. Users without an appropriate cloud firewall must make
an explicit risk decision: configure and review one through the provider's
current [firewall-creation guidance](https://docs.digitalocean.com/products/networking/firewalls/how-to/create/)
before Droplet creation, or accept the image's initial network exposure until
the repository applies its UFW baseline. The former may be done through the
account UI without broadening this guide into a second authoritative workflow;
using `doctl` instead requires separately confirming AMD-endpoint support and
selecting the conditional scope above. Do not preconfigure guest UFW merely to
imitate this layer; doing so leaves the repository's validated fresh-UFW path
and causes setup to preserve and report custom state instead.

## Create the Droplet manually

Fill these values only from the discovery output. The name is intentionally
short, unique, and customizable. The size and image must remain the accepted
values to stay on this repository's validated environment path; the region and
SSH key are account-specific selections.

```bash
droplet_name="rocm-dc-validation-$(date --utc +%Y%m%d-%H%M%S)"
region_slug="<DISCOVERED_AVAILABLE_REGION>"
size_slug="gpu-mi300x1-192gb-devcloud"
image_slug="ubuntu-24-04-x64"
ssh_key_id="<DISCOVERED_OR_IMPORTED_SSH_KEY_ID>"
ssh_private_key_file="<MATCHING_LOCAL_PRIVATE_KEY_PATH>"

printf 'Name: %s\nRegion: %s\nSize: %s\nImage: %s\nSSH key ID: %s\n' \
  "${droplet_name}" \
  "${region_slug}" \
  "${size_slug}" \
  "${image_slug}" \
  "${ssh_key_id}"
```

Review those values and the current price before manually running the paid
create command. The current command surface is described by DigitalOcean's
[`droplet create` reference](https://docs.digitalocean.com/reference/doctl/reference/compute/droplet/create/).

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet create "${droplet_name}" \
  --region "${region_slug}" \
  --size "${size_slug}" \
  --image "${image_slug}" \
  --ssh-keys "${ssh_key_id}" \
  --format ID,Name,Status
```

Do not add `--project-id`; the validated path relies on the account's existing
default-project placement. Project creation, selection, and reassignment are
separate provider administration tasks and require separately reviewed scopes.
The command also deliberately omits tags, monitoring, backups, and volumes.

Record the returned Droplet ID locally. If using a previously reviewed cloud
firewall, attach it promptly and confirm the association:

```bash
droplet_id="<NEW_DROPLET_ID>"
firewall_id="<REVIEWED_EXISTING_FIREWALL_ID>"

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute firewall add-droplets "${firewall_id}" \
  --droplet-ids "${droplet_id}"

"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute firewall list-by-droplet "${droplet_id}" \
  --format ID,Name,Status
```

Firewall attachment is optional, so omit that entire block when no reviewed
firewall was selected. Do not invent an ID or attach an unrelated firewall.

Inspect the exact Droplet until it reports `active` and has a public IPv4
address:

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet get "${droplet_id}" \
  --format ID,Name,PublicIPv4,Region,Image,Status
```

Use ordinary OpenSSH with the matching private key rather than making `doctl`
a guest dependency:

```bash
droplet_ipv4="<DROPLET_PUBLIC_IPV4>"

ssh \
  -o IdentitiesOnly=yes \
  -i "${ssh_private_key_file}" \
  "root@${droplet_ipv4}"
```

Provider-side provisioning ends here. Continue with the reviewed
`amd_devcloud_root_bootstrap.sh` root-to-user handoff, prove a separate
ordinary-user SSH login, and then run `amd_devcloud_env_setup.sh` as that user.
Do not pipe a mutable network response into a root shell.

GPU Droplet billing begins at creation and ends only when the Droplet is
destroyed; powering it off does not stop billing. See DigitalOcean's
[Droplet pricing documentation](https://docs.digitalocean.com/products/droplets/details/pricing/).

## Destroy the Droplet manually

Retrieve needed results and logs before deletion. Then inspect the exact ID,
name, and status one final time. If this is a new local shell, first redefine
`doctl_bin`, `devcloud_api_url`, `devcloud_context`, and `droplet_id` from the
locally retained values; never recover them from an untrusted command snippet.

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet get "${droplet_id}" \
  --format ID,Name,Status
```

Delete by immutable ID without `--force`, and answer the interactive prompt
only after confirming the target. Deletion is permanent and irreversible, as
documented by the [`droplet delete` reference](https://docs.digitalocean.com/reference/doctl/reference/compute/droplet/delete/).

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet delete "${droplet_id}"
```

Verify that the exact ID is gone:

```bash
"${doctl_bin}" \
  --api-url "${devcloud_api_url}" \
  --context "${devcloud_context}" \
  compute droplet get "${droplet_id}" \
  --format ID,Name,Status
```

The expected result is an API `404`. An optional portal refresh can provide a
second observation, but the guide does not promise a propagation interval.
Deleting the Droplet does not delete a separately managed cloud firewall or
account SSH key.
