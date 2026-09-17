# Magentic MIND in an OpenShell VM

One OpenShell microVM per user MIND. The Magentic compose pod stays on the
host. Vault, BACK, SWITCH, and NATS stay outside the guest.

This is the isolation boundary Magentic currently only states in the MIND
harness: default-deny egress, no provider keys in the agent process, Monty
still runs CodeAct cells inside the guest.

## What this example provides

| File | Role |
| --- | --- |
| `policy.yaml` | Default-deny. Native TCP to `host.openshell.internal:4222` (NATS) and `:8789` (SWITCH), Python binaries only. |
| `compose.mind-host-ports.yml` | Magentic compose overlay that publishes NATS and SWITCH on loopback. Does not invent a `mind` service. |
| `create-mind-sandbox.sh` | Create or start one VM sandbox per user. Refuses provider keys. |

OpenShell's VM driver is NIC-less. `openshell-sandbox` is guest PID 1.
`openshell-supervisor` runs on the host and mediates DNS/TCP over vsock.
There is no TAP path to `169.254.169.254`.

## Prerequisites

- Linux KVM host (production isolation claim). macOS Hypervisor.framework is a
  development path only.
- A running OpenShell gateway with `compute_driver = "vm"`.
- Magentic compose with NATS and SWITCH. Keep MIND out of the default `up`:

```shell
docker compose \
  -f docker-compose.yml \
  -f /path/to/OpenShell/examples/mind-vm-isolation/compose.mind-host-ports.yml \
  up --scale mind=0
```

Do not publish those ports on `0.0.0.0`.

## Create one sandbox per user

Reuse the sandbox for the user's session. Do not create a VM per tool call.

```shell
MIND_IMAGE=<mind-image> bash examples/mind-vm-isolation/create-mind-sandbox.sh
```

The helper starts an existing sandbox instead of creating a second VM. It
exits if `MIND_API_KEY` or other provider keys are set. Durable sqlite is
`/sandbox/nooa.sqlite3` so Landlock does not depend on a `/mind-data` directory
that distroless images do not ship.

Or create it directly:

```shell
openshell sandbox create \
  --name mind-$USER \
  --from <mind-image> \
  --cpu 2 \
  --memory 4Gi \
  --policy examples/mind-vm-isolation/policy.yaml \
  --detach \
  --env MM_NATS_URL=nats://host.openshell.internal:4222 \
  --env SWITCH_URL=http://host.openshell.internal:8789/v1 \
  --env DB_PATH=/sandbox/nooa.sqlite3 \
  -- harness.py
```

`--cpu` and `--memory` size the microVM. They override `[openshell.drivers.vm]`
`vcpus` / `mem_mib` for that sandbox. Requests (`resources.requests.*`) are
rejected; a dedicated VM has no shared-request model.

Do not pass provider API keys. SWITCH reads vault on the host side.

Stop/start the same sandbox across sessions. Delete only when the user is gone.

## Magentic launch cut

`bin/docker-containers` keeps FRONT, BACK, VAULT, SWITCH, NATS, GRAPH.
`--scale mind=0` keeps the in-compose agent off. Treat "MIND Ready" as OpenShell
sandbox `Ready` for that user, not `depends_on: mind`.
`create-mind-sandbox.sh` maps **user → one sandbox**.

Monty stays in the MIND image (ADR 0071). OpenShell does not replace CPCP,
SHACL, or vault allowlists. NATS still has no broker auth; this policy removes
L3 reachability to GRAPH, Milvus, and the internet.

## Host hardening (operator, not the sandbox)

On multi-tenant hosts:

- Disable Kernel Samepage Merging.
- Disable swap so guest memory does not land on disk.
- Disable SMT or use core scheduling so trust domains do not share sibling threads.
- Keep host and guest kernels and microcode patched.

Jailer-wrapping libkrun and confidential VMs (SEV-SNP / TDX) are out of scope
unless the host operator is in the threat model.

## Success

A MIND process that opens `graph:7878`, `169.254.169.254`, or an arbitrary
internet socket is denied by the supervisor and has no guest route.
Completions through SWITCH and CPCP through NATS still work. Vault keys are
absent from the guest environment and disk.
