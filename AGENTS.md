# AGENTS.md — layer-krun

The krun runtime host layer. The authoritative rulebook is the umbrella `AGENTS.md` in
`opencharly/opencharly`; this file adds only what is specific to this repo.

## Load these skills first (R0)

- `/charly-image:layer` — the candy authoring reference (`charly.yml` schema, `plan:` step
  verbs, `check:` steps, `var:`/`env:`).
- `/charly-check:check` — the `check:` verb catalog, `context: [runtime]`, and the authoring
  traps (a step that SKIPS is not a step that PASSES).

## The version bounds are load-bearing — do not "simplify" them

- **crun is a COMMIT pin, not a release.** `ca04fdb6c26f0c8259871f2cccd0e6e652ec03ce` is the
  only point that carries both the passt start path and the `/proc` remount under a declared
  PID namespace (`src/libcrun/handlers/krun.c:824-838`). A released crun (1.30.1) fails
  `start passt` with rc 1 and breaks in-guest CRIU. Do not replace the build with a distro
  `crun` package.
- **libkrun is 1.x, never `main`.** The 2.0 rewrite drops `krun_set_vm_config`,
  `krun_set_gpu_options` and `krun_start_enter`, which crun's handler resolves. A build
  against `main` links but cannot start a VM.
- **`/usr/bin/krun` is the same binary as `/usr/bin/crun`**, selected by argv[0]. The
  containerd handler names that path.
- **The render server is at `/usr/libexec/virgl_render_server`** because crun hardcodes it.
  Arch installs it at `/usr/lib/`; the layer provides the hardcoded path rather than patching
  crun.
- **The Vulkan ICDs are separate packages.** `mesa` no longer ships them; without
  `vulkan-virtio`/`vulkan-swrast` every krun GPU run fails `Found no drivers`.

## The guest kernel

- Build it from **libkrunfw v5.6.2's own sources, patches and stock config** (its Makefile
  does the download/patch/`olddefconfig`), plus the committed fragment, and `make vmlinux`
  only.
- The build asserts every fragment option survived `olddefconfig`; if you add an option, add
  it to both the fragment and the assertion loop. A silently dropped option is the defect the
  assertion exists to catch.
- Ship it at `/krun/vmlinux` (`kernel_format: 1`). A custom kernel that is not an ELF image
  is not a vmlinux.

## Build / validate / test

- `charly box validate` at the repo root is the structural gate (0 warnings, 0 errors).
- The merge gate is the **org-wide** `charly/pr-validator` (required check
  `validate / validate`, defined in `opencharly/.github`); this repo has no per-repo candy
  gate.
- `/dev/kvm` and the NVIDIA ICD are venue properties: their checks are `context: [runtime]`
  and `charly check box` skips them by design. Do not make them build-scope checks.
- Builds are expensive (crun from source + a kernel). Both use cache mounts
  (`/var/cache/charly/krun-build`, `/var/cache/charly/krun-kernel`); keep them so a rebuild
  reuses the checkout and the kernel tree.

## Landing

- PR-only. Every change lands through a pull request; the org-required `charly/pr-validator`
  validates the diff and body and arms native auto-merge on PASS. Direct pushes to `main` are
  blocked.
- History lives in `CHANGELOG/` (written by `tag-on-merge` at merge time); the PR body IS the
  changelog.
- Do not restate the umbrella rulebook here.
