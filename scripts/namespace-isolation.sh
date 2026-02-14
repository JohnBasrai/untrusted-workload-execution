#!/usr/bin/env bash
set -euo pipefail

WORKER_ID="${1:-1}"
SANDBOX_HOSTNAME="janus-sandbox-w${WORKER_ID}"

hr() {
  printf '%s\n' "============================================================"
}

show_ns_snapshot_outside() {
  #
  echo "=== Outside (Host) ==="
  printf "%-25s : %s\n" "Shell PID ( \$\$ )"     "$$" 
  printf "%-25s : %s\n" "Proc PID  (/proc/self)" "$(awk '{print $1}' /proc/self/stat)"
  printf "%-25s : %s\n" "Hostname"               "$(hostname)"
  echo
  echo "Namespaces (readlink /proc/self/ns/*):" 
  # sorted for stable output
  (cd /proc/self/ns && ls -1 | sort | while read -r ns; do
    printf "  %-23s : %s\n" "${ns}:" "$(readlink "/proc/self/ns/${ns}")"
  done)
}

echo
hr
echo "	Namespace Isolation Demo"
echo "	Worker ID: ${WORKER_ID}"
hr
echo

# Outside view (host namespaces)
show_ns_snapshot_outside

hr
echo "Launching sandbox with the following properties..."
echo " - PID namespace (new):     yes"
echo " - Mount namespace (new):   yes"
echo " - /proc remounted:         yes (so /proc reflects sandbox PIDs)"
echo " - UTS namespace (new):     yes (hostname isolated)"
echo " - IPC namespace (new):     yes"
echo " - NET namespace (new):     yes"
hr

# unshare args:
#   --mount-proc - mount the proc filesystem
#                    without this '/proc' continues to reflect the host
#                    PID namespace, not the new PID namespace so tools
#                    like ps, top, and /proc/self become inconsistent
#                    with the namespace view.”
#
#   --net        - Separate network stack
#   --mount      - Separate mount namespace
#   --uts        - Separate hostname
#   --ipc        - Separate IPC
#   --cgroup     - Separate cgroup view
#   --pid        - Separate process tree [requires --fork too]
#   --fork       - Fork then child exec's the program, parent is watchdog
#   --kill-child - Kill children on exit
#                  With --fork, unshare remains as parent/supervisor and
#                  waits on the namespaced child; --kill-child makes
#                  that supervision enforceable by the kernel also

# Start unshare in the background so we can capture the *host-visible PID* of the sandbox process.
# That PID is what the host sees; inside the PID namespace, the shell will typically be PID 1.
sudo unshare --fork --pid --mount --uts --ipc --net --mount-proc \
  env "HOST_VISIBLE_PID=$$" "SANDBOX_HOSTNAME=${SANDBOX_HOSTNAME}" \
  bash -c '
    set -euo pipefail
    echo "                     --- CHILD ---"
    hr() { echo "============================================================"; }

    show_ns_snapshot_inside() {
      #
      echo "=== Inside (Sandbox) ==="
      printf "%-26s : %s\n" "Host-visible PID (passed)" "${HOST_VISIBLE_PID}"
      printf "%-26s : %s\n" "Namespace PID (\$\$)" $$ "expecting PID=1"
      printf "%-26s : %s\n" "Proc PID (/proc/self)" "$(awk "{print \$1}" /proc/self/stat)"
      printf "%-26s : %s\n" "Hostname" "$(hostname)"
      echo
      echo "Namespaces:"
      (cd /proc/self/ns && ls -1 | sort | while read -r ns; do
        printf "  %-23s : %s\n" "${ns}:" "$(readlink "/proc/self/ns/${ns}")"
      done)
    }

    # Set internal hostname to make UTS isolation obvious
    hostname "${SANDBOX_HOSTNAME}"

    hr
    show_ns_snapshot_inside ""
    hr

    # CPU hog so will bubble to the top of `top` output on host
    yes > /dev/null &
    sleep 1 ; ps -eF

    echo
    echo "Notes:"
    echo "  1) In the fresh PID namespace, the first process should be PID 1"
    echo "  2) Because we used --mount-proc, /proc/self matches the sandbox PID view."
    echo "  3) The sleep 15 is so the 'yes' cmd is visble in 'top' from the host."
    echo "  4) The PID gaps come from short-lived forked processes during shell execution"
    echo "  5) Type Control-C to exit immediately"
    sleep 15
    hr
    ps -eF
    echo "Done."
  '

hr
echo "Sandbox exited."
