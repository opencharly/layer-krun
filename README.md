# layer-krun

The krun runtime host: `crun` in libkrun mode, the libraries it `dlopen`s, the host paths it
hardcodes, and the guest kernel a krun microVM boots.

This is the `krun-host` requirement of `CONTAINERD-IMAGES.md` §1.3, over the measurements in
`CONTAINERD.md` §5.2 / §14.3 and `LIBKRUN.md` §10.

## The two version bounds (both measured, neither a preference)

**crun is built from a commit, not a release.** No release carries both the passt fix and
the `/proc` remount that makes passt work under a declared PID namespace. crun 1.30.1 cannot
start passt at all (`start passt`, rc 1), so a krun guest gets no `virtio-net` interface and
the in-guest CRIU path fails before its first check. This layer builds
`ca04fdb6c26f0c8259871f2cccd0e6e652ec03ce` — *"krun: Remount /proc before starting passt, if
the PID namespace was detached"* — with `./configure --with-libkrun`, and asserts
`crun --version` reports both `+LIBKRUN` and `+CRIU`.

**libkrun is the 1.x line, never `main`.** crun's krun handler resolves
`krun_set_vm_config`, `krun_set_gpu_options` and `krun_start_enter`; libkrun `main` is the 2.0
API rewrite that removes them. The distro's `libkrun` 1.19.x is the pin; `libkrunfw` is
5.6.2.

## What it provides

| Property | Value |
|---|---|
| Layer / candy | `layer-krun` |
| `crun` | built from `ca04fdb6`, `--prefix=/usr`, `--with-libkrun` |
| `krun` | `/usr/bin/krun`, the same binary by another name |
| libkrun / libkrunfw | 1.x / 5.6.2, from the distro |
| `passt` | `/usr/bin/passt` (the `krun.use_passt` backend) |
| `bwrap` | `/usr/bin/bwrap` (crun hardcodes the path) |
| render server | `/usr/libexec/virgl_render_server` (Arch installs it at `/usr/lib/`) |
| Vulkan ICDs | `vulkan-virtio` (`virtio_icd.json`) and `vulkan-swrast` (`lvp_icd.json`) |
| guest kernel | `/krun/vmlinux`, ELF, for `krun.custom_kernel` + `kernel_format: 1` |
| nested virt | optional: `CHARLY_KRUN_NESTED=1` writes `kvm_intel`/`kvm_amd` `nested=1` |

`/dev/kvm` is a **venue** property, not an image one: the layer asserts it at runtime (mode
`0666`, or the krun user in group `kvm`).

## The `libkrunfw-crabbox` guest kernel

Built from **libkrunfw v5.6.2's own sources, patches and stock config**, plus the committed
fragment `config-libkrunfw-crabbox.fragment`, then `make vmlinux` only — no libkrunfw bundle,
no initrd. The fragment adds what the stock kernel disables:

- `CHECKPOINT_RESTORE` and `INET_DIAG` / `UNIX_DIAG` / `NETLINK_DIAG` / `PACKET_DIAG` —
  in-guest CRIU (`LIBKRUN.md` §7);
- `NETFILTER_XTABLES`, `NFT_COMPAT`, `NFT_NUMGEN`, the `IP_NF_*` / `XT_*` set, `IP_SET*`,
  `IP_VS*`, `VXLAN`, `IP_MULTIPLE_TABLES` — k3s in a guest (`K3S.md` §2–§8);
- `BASE_SMALL=n`.

The build **asserts every option survived `olddefconfig`** and fails when one did not (a
missing dependency), rather than shipping a silently reduced kernel whose gaps surface later
as `Diag module missing (-2)`.

## What proves it

`charly box validate` is the structural gate. The candy's `plan:` carries the functional
checks: `crun --version` has `+LIBKRUN +CRIU`; `/usr/bin/krun` exists; `libkrun.so.1` and
`libkrunfw.so.5` are on the loader path; `/usr/bin/bwrap` and
`/usr/libexec/virgl_render_server` exist; both Vulkan ICDs are installed; `/krun/vmlinux` is
a >1 MiB ELF image. Two live-only checks are `context: [runtime]`: `/dev/kvm` is readable, and
an NVIDIA host has its Vulkan ICD (a non-NVIDIA host passes with a visible N/A).

## How to use it

```yaml
my-box:
    candy:
        base: cachyos
        candy:
            - '@github.com/opencharly/layer-krun:v<TAG>'
```

Then a krun container is `nerdctl run --runtime /usr/bin/krun …`; for containerd/CRI the
handler is named `krun` with `BinaryName = /usr/bin/krun` and
`pod_annotations = ["krun.*"]` (the sibling `layer-containerd` writes that handler). A custom
kernel is selected with `krun.custom_kernel` plus `kernel_path=/krun/vmlinux`,
`kernel_format=1`.

## Known bounds

- `nerdctl exec` / `kubectl exec` are not supported on a krun handler; `nerdctl logs` shows
  only early-boot guest console lines (`CONTAINERD.md` §5.2). Verify services over HTTP.
- The crun **annotation** form of GPU (`krun.gpu_flags`) fails on this host (it looks for
  `libEGL` inside the container rootfs); the libkrun API launcher path is the working one
  (`CONTAINERD.md` §14.3). The host NVIDIA GPU is not passed through to a krun guest.
- A krun guest's process state is checkpointable **from inside the guest**, not from the host:
  CRIU resolves the container root against the host mount table, where the guest rootfs is not
  a mount (`LIBKRUN.md` §7).

## Layout

- `charly.yml` — the `layer-krun` candy: the package arms, the crun build, the host paths, the
  optional nested-virt step, the guest-kernel build, and the checks.
- `config-libkrunfw-crabbox.fragment` — the committed kernel config fragment.
- `AGENTS.md` — the repo-specific rules.
- `CHANGELOG/` — per-CalVer release history, written by `tag-on-merge` from the PR body.
- `.github/workflows/tag-on-merge.yml` — the org CalVer tag + `CHANGELOG/` caller.
