#!/bin/bash
# build-kernel.sh — build the libkrunfw-crabbox guest kernel.
#
# The ONE copy of the recipe. The `layer-krun` candy installs this script and
# runs it, and downstream image repos fetch it from a pinned layer-krun tag
# instead of copying the steps (R2: one canonical implementation).
#
# Sources: libkrunfw v5.6.2's own sources, patches and stock config (its
# Makefile does the download/patch/olddefconfig), plus the committed
# config-libkrunfw-crabbox.fragment, then `make vmlinux` only.
#
# Environment:
#   KRUN_KERNEL_CACHE     checkout + kernel tree cache (default /var/cache/charly/krun-kernel)
#   KRUN_KERNEL_FRAGMENT  the config fragment to append (default /tmp/krun/config-libkrunfw-crabbox.fragment)
#   KRUN_KERNEL_DEST      where the ELF vmlinux is installed (default /krun/vmlinux)
set -eu

cache="${KRUN_KERNEL_CACHE:-/var/cache/charly/krun-kernel}"
fragment="${KRUN_KERNEL_FRAGMENT:-/tmp/krun/config-libkrunfw-crabbox.fragment}"
dest="${KRUN_KERNEL_DEST:-/krun/vmlinux}"
kfw=$cache/libkrunfw
if [ ! -d "$kfw/.git" ]; then
  git clone --depth 1 --branch v5.6.2 https://github.com/containers/libkrunfw "$kfw"
fi
cd "$kfw"
# The box bootstrap exports ARCH=amd64 (the OCI TARGETARCH). libkrunfw's
# Makefile treats a NON-EMPTY ARCH as the KERNEL's arch spelling and derives
# GUESTARCH=$(ARCH), so it copies config-libkrunfw_amd64 — which does not
# exist (the file is config-libkrunfw_x86_64) — and the kernel's own build
# system would look for arch/amd64. Use the kernel spelling for this step
# (libkrunfw itself maps arm64->aarch64 and riscv->riscv64).
case "$(uname -m)" in
  x86_64) karch=x86_64 ;;
  aarch64|arm64) karch=arm64 ;;
  riscv64) karch=riscv ;;
  *) karch="$(uname -m)" ;;
esac
export ARCH="$karch"
# A killed or failed build can leave the extracted tree without the stock
# .config (the Makefile's cp is the last step of the extract recipe). The
# directory target would then read as "up to date", skip the config copy,
# and the fragment below would be appended to an empty .config. Force a
# clean extract/patched tree in that state.
if [ ! -s linux-6.12.109/.config ]; then
  rm -rf linux-6.12.109
fi
# libkrunfw's OWN Makefile downloads linux-6.12.109, applies ITS patches and
# copies ITS stock config, then runs olddefconfig. That is the "sources +
# patches + config" the contract names; this layer only ADDS a fragment.
make linux-6.12.109
if ! grep -q 'CHARLY_LIBKRUNFW_CRABBOX' linux-6.12.109/.config; then
  printf '\n# CHARLY_LIBKRUNFW_CRABBOX\n' >> linux-6.12.109/.config
  cat "$fragment" >> linux-6.12.109/.config
fi
make -C linux-6.12.109 olddefconfig
# The fragment is only real if olddefconfig KEPT it. Assert every option and
# fail the build when a dependency is missing, rather than ship a silently
# reduced kernel whose gaps surface later as "Diag module missing (-2)".
missing=""
for opt in CHECKPOINT_RESTORE INET_DIAG UNIX_DIAG NETLINK_DIAG PACKET_DIAG \
           NETFILTER NETFILTER_ADVANCED NF_CONNTRACK NF_NAT NF_TABLES \
           NETFILTER_XTABLES NFT_COMPAT NFT_NUMGEN \
           IP_NF_IPTABLES IP_NF_FILTER IP_NF_MANGLE IP_NF_NAT \
           IP_NF_TARGET_MASQUERADE IP_NF_TARGET_REJECT \
           NETFILTER_XT_MATCH_MULTIPORT NETFILTER_XT_MATCH_COMMENT \
           NETFILTER_XT_MATCH_CONNTRACK NETFILTER_XT_MATCH_ADDRTYPE \
           NETFILTER_XT_MATCH_MARK NETFILTER_XT_MATCH_TCPMSS \
           NETFILTER_XT_TARGET_MASQUERADE NETFILTER_XT_TARGET_MARK \
           IP_SET IP_VS IP_VS_PROTO_TCP IP_VS_PROTO_UDP IP_VS_NFCT IP_VS_RR \
           VXLAN IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES; do
  grep -qx "CONFIG_$opt=y" linux-6.12.109/.config || missing="$missing CONFIG_$opt"
done
if grep -qx 'CONFIG_BASE_SMALL=y' linux-6.12.109/.config; then
  missing="$missing CONFIG_BASE_SMALL=n"
fi
if [ -n "$missing" ]; then
  echo "the merged kernel config did not keep:$missing" >&2
  echo "a required option was dropped by olddefconfig - its dependency is missing" >&2
  exit 1
fi
make -C linux-6.12.109 -j"$(nproc)" vmlinux
install -d -m 0755 "$(dirname "$dest")"
install -m 0644 linux-6.12.109/vmlinux "$dest"
echo "$dest: $(stat -c %s "$dest") bytes"
