#!/usr/bin/env bash
# =============================================================================
#  Kubernetes Troubleshooting Practice Lab
# -----------------------------------------------------------------------------
#  This script deploys intentionally-broken Kubernetes manifests so you can
#  practise diagnosing and fixing the most common real-world failures:
#    * Scheduling problems (resources, affinity, taints, quotas, PVCs)
#    * Image / registry problems (ImagePullBackOff)
#    * Runtime crashes (CrashLoopBackOff — OOM, health checks, init, runtime)
#    * Config problems (missing ConfigMap / Secret, wrong Service selector)
#
#  For every scenario the script prints:
#    1. WHAT is broken
#    2. HOW to diagnose it   (kubectl commands to try)
#    3. HOW to fix it        (what the correct config would be)
#    4. A cleanup prompt
# =============================================================================

# -------- Strict-ish mode (script is meant to be resilient, not fail-fast) ----
set -u

# ============================== Colour helpers ===============================
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"
    C_BOLD="$(tput bold)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_MAGENTA="$(tput setaf 5)"
    C_CYAN="$(tput setaf 6)"
else
    C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN=""
fi

banner() { printf "\n%s%s==============================================================%s\n" "$C_BOLD" "$C_CYAN" "$C_RESET"; printf "%s%s  %s%s\n" "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; printf "%s%s==============================================================%s\n\n" "$C_BOLD" "$C_CYAN" "$C_RESET"; }
info()   { printf "%s[INFO]%s  %s\n"  "$C_BLUE"    "$C_RESET" "$1"; }
ok()     { printf "%s[ OK ]%s  %s\n"  "$C_GREEN"   "$C_RESET" "$1"; }
warn()   { printf "%s[WARN]%s  %s\n"  "$C_YELLOW"  "$C_RESET" "$1"; }
err()    { printf "%s[FAIL]%s  %s\n"  "$C_RED"     "$C_RESET" "$1"; }
tip()    { printf "%s[TIP ]%s  %s\n"  "$C_MAGENTA" "$C_RESET" "$1"; }

# ============================== Sanity checks ================================
require_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        err "kubectl is not installed or not on PATH. Please install it first."
        exit 1
    fi
    if ! kubectl cluster-info >/dev/null 2>&1; then
        err "kubectl cannot reach a cluster. Start minikube / kind first."
        exit 1
    fi
}

# Return the name of one worker node (works on single-node minikube too).
first_node() {
    kubectl get nodes -o jsonpath='{.items[0].metadata.name}'
}

# ============================== Usage / help =================================
usage() {
    clear
    printf "%s%s==============================================================%s\n"  "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf "%s%s        Kubernetes Troubleshooting Practice Lab%s\n"                   "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf "%s%s==============================================================%s\n\n" "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf "%sSyntax :%s  %s <option>\n"                                "$C_BOLD" "$C_RESET" "$0"
    printf "%sExample:%s  %s -opt1        # run scenario 1\n"           "$C_BOLD" "$C_RESET" "$0"
    printf "           %s --opt2       # long form also works\n\n"      "$0"
    printf "%sAvailable scenarios:%s\n" "$C_BOLD" "$C_RESET"
    printf "  %s-opt1 %s  Insufficient Resource        (Pending pod, not enough memory)\n"  "$C_GREEN" "$C_RESET"
    printf "  %s-opt2 %s  Node Affinity                (Pending pod, no matching node label)\n" "$C_GREEN" "$C_RESET"
    printf "  %s-opt3 %s  Unbound Persistent Volume    (Pending pod, PVC never binds)\n"    "$C_GREEN" "$C_RESET"
    printf "  %s-opt4 %s  Node Taint                   (Pending pod, no toleration)\n"      "$C_GREEN" "$C_RESET"
    printf "  %s-opt5 %s  Unavailable ConfigMap        (Pod stuck creating, volume missing)\n" "$C_GREEN" "$C_RESET"
    printf "  %s-opt6 %s  Unavailable Secret           (Pod stuck creating, volume missing)\n" "$C_GREEN" "$C_RESET"
    printf "  %s-opt7 %s  Resource Quota               (Deployment can't scale past quota)\n"  "$C_GREEN" "$C_RESET"
    printf "  %s-opt8 %s  ImagePullBackOff             (Image tag does not exist)\n"        "$C_GREEN" "$C_RESET"
    printf "  %s-opt9 %s  CrashLoopBackOff - OOM       (Container killed for memory)\n"     "$C_GREEN" "$C_RESET"
    printf "  %s-opt10%s  CrashLoopBackOff - Healthchk (Liveness probe keeps failing)\n"    "$C_GREEN" "$C_RESET"
    printf "  %s-opt11%s  CrashLoopBackOff - Init      (Init container exits non-zero)\n"   "$C_GREEN" "$C_RESET"
    printf "  %s-opt12%s  CrashLoopBackOff - Runtime   (App image crashes on start)\n"      "$C_GREEN" "$C_RESET"
    printf "  %s-opt13%s  Runtime Error - Service      (Service selector doesn't match pods)\n" "$C_GREEN" "$C_RESET"
    printf "\n  %s-h / --help%s  Show this help\n" "$C_GREEN" "$C_RESET"
    printf "\n%s==============================================================%s\n\n" "$C_CYAN" "$C_RESET"
}

# ================ Per-scenario educational hints =============================
# For each manifest we print: description, what to look for, and how to fix.
print_hints() {
    case "$manifest" in
      opt01-insufficient-resources.yml)
        info "Symptom  : Pod stays in 'Pending' state."
        info "Cause    : Pod requests 4Gi memory — more than any node has free."
        tip  "Diagnose :  kubectl describe pod  (check 'Events' -> 'FailedScheduling')"
        tip  "Diagnose :  kubectl get nodes -o custom-columns=NAME:.metadata.name,MEM:.status.allocatable.memory"
        tip  "Fix      : Lower spec.containers[].resources.requests.memory to a value your node can satisfy."
        ;;
      opt02-node-affinity.yml)
        info "Symptom  : Pod stays in 'Pending' state."
        info "Cause    : Pod uses nodeSelector 'mynode=demonode' — no node has that label."
        tip  "Diagnose :  kubectl describe pod   (Events -> 'didn't match Pod's node affinity/selector')"
        tip  "Diagnose :  kubectl get nodes --show-labels"
        tip  "Fix      : Label a node so it matches:  kubectl label node <node> mynode=demonode"
        tip  "           (Script will offer to do this for you.)"
        ;;
      opt03-unbound-pv.yml)
        info "Symptom  : Pod stays in 'Pending', PVC stays in 'Pending'."
        info "Cause    : Default StorageClass is disabled (this script disables it),"
        info "           so the PVC has no provisioner and never binds to a PV."
        tip  "Diagnose :  kubectl get pvc"
        tip  "Diagnose :  kubectl get storageclass"
        tip  "Diagnose :  kubectl describe pvc myebsvolclaim"
        tip  "Fix      : Re-enable the default StorageClass, e.g.:"
        tip  "           kubectl patch storageclass standard -p \\"
        tip  "             '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
        ;;
      opt04-taint-node.yml)
        info "Symptom  : Pod stays in 'Pending' state."
        info "Cause    : The node has a taint 'taint=true:NoSchedule' and the pod has no toleration."
        tip  "Diagnose :  kubectl describe node <node>  (look for 'Taints:')"
        tip  "Diagnose :  kubectl describe pod          (Events -> 'had untolerated taint')"
        tip  "Fix      : Add a matching toleration to the pod spec, or remove the taint:"
        tip  "           kubectl taint nodes <node> taint=true:NoSchedule-"
        ;;
      opt05-configmap.yml)
        info "Symptom  : Pod stuck in 'ContainerCreating'."
        info "Cause    : Volume references ConfigMap 'mymap' which does NOT exist."
        tip  "Diagnose :  kubectl describe pod configmap   (Events -> 'configmap \"mymap\" not found')"
        tip  "Fix      : Create the ConfigMap the pod expects, for example:"
        tip  "           kubectl create configmap mymap --from-file=sample.conf"
        ;;
      opt06-secret.yml)
        info "Symptom  : Pod stuck in 'ContainerCreating'."
        info "Cause    : Volume references Secret 'mypasswd' which does NOT exist."
        tip  "Diagnose :  kubectl describe pod secret   (Events -> 'secret \"mypasswd\" not found')"
        tip  "Fix      : Create the Secret the pod expects, for example:"
        tip  "           kubectl create secret generic mypasswd --from-literal=password=Passw0rd"
        ;;
      opt07-resource-quota.yml)
        info "Symptom  : Deployment wants 3 replicas but only 2 pods are Running."
        info "Cause    : A ResourceQuota limits the namespace to 2 pods total."
        tip  "Diagnose :  kubectl get rs"
        tip  "Diagnose :  kubectl describe rs                 (Events -> 'exceeded quota')"
        tip  "Diagnose :  kubectl describe resourcequota pod-demo"
        tip  "Fix      : Raise or delete the quota:"
        tip  "           kubectl delete resourcequota pod-demo"
        ;;
      opt08-imagepullbackoff.yml)
        info "Symptom  : Pod status = 'ImagePullBackOff' or 'ErrImagePull'."
        info "Cause    : Image tag 'yogeshk04/frontend:v41' does not exist in the registry."
        tip  "Diagnose :  kubectl describe pod imagepull  (Events -> 'Failed to pull image')"
        tip  "Fix      : Point the container to a real image/tag that exists."
        ;;
      opt09-crashloopbackoff-oom.yml)
        info "Symptom  : Pod cycles: Running -> OOMKilled -> CrashLoopBackOff."
        info "Cause    : Container allocates 250M of memory but limits are 200Mi."
        tip  "Diagnose :  kubectl get pod inres -o wide"
        tip  "Diagnose :  kubectl describe pod inres   (look for 'OOMKilled' in Last State)"
        tip  "Fix      : Raise resources.limits.memory above the workload's real usage."
        ;;
      opt10-crashloopbackoff-healthcheck.yml)
        info "Symptom  : Container starts, then is restarted every ~30s."
        info "Cause    : Liveness probe runs 'ls /tmp/lp' — that path does not exist,"
        info "           so kubelet thinks the container is unhealthy and restarts it."
        tip  "Diagnose :  kubectl describe pod   (Events -> 'Liveness probe failed')"
        tip  "Fix      : Change the probe to something meaningful (e.g. httpGet on / :80),"
        tip  "           or create the file the probe expects."
        ;;
      opt11-crashloopbackoff-init.yml)
        info "Symptom  : Pod stays in 'Init:CrashLoopBackOff'."
        info "Cause    : The init container runs 'exit 1', so main container never starts."
        tip  "Diagnose :  kubectl describe pod initpod"
        tip  "Diagnose :  kubectl logs initpod -c init"
        tip  "Fix      : Make the init container succeed (exit 0) or fix its command."
        ;;
      opt12-crashloopbackoff-runtime.yml)
        info "Symptom  : Pod status = 'CrashLoopBackOff'."
        info "Cause    : The container image itself crashes/exits shortly after startup."
        tip  "Diagnose :  kubectl logs runtimeerr --previous"
        tip  "Diagnose :  kubectl describe pod runtimeerr"
        tip  "Fix      : Use a working image, or fix the app's startup code."
        ;;
      opt13-runtimeerr-svc.yml)
        info "Symptom  : Service has no endpoints — traffic does not reach any pod."
        info "Cause    : Service selector 'wezvatech: ninjasprogram' does NOT match the"
        info "           pod labels 'wezvatech: adam'."
        tip  "Diagnose :  kubectl get endpoints demoservice   (should be <none>)"
        tip  "Diagnose :  kubectl describe svc demoservice"
        tip  "Diagnose :  kubectl get pods --show-labels"
        tip  "Fix      : Align the service selector with the pod labels, e.g. change"
        tip  "           the selector to 'wezvatech: adam'."
        ;;
      *)
        warn "No hints defined for '$manifest'."
        ;;
    esac
}

# ============================ Argument parsing ===============================
message="null"
manifest="null"

if [ "$#" -eq 0 ]; then
    err "No option supplied."
    info "Run '$0 -h' to see the list of scenarios."
    exit 1
fi

while [ "$#" -gt 0 ]; do
   flag=$1
   case $flag in
       --opt1  | -opt1  ) message="Insufficient Resource";            manifest="opt01-insufficient-resources.yml"     ;;
       --opt2  | -opt2  ) message="Node Affinity";                    manifest="opt02-node-affinity.yml"              ;;
       --opt3  | -opt3  ) message="Unbound Persistent Volume";        manifest="opt03-unbound-pv.yml"                 ;;
       --opt4  | -opt4  ) message="Node Taint";                       manifest="opt04-taint-node.yml"                 ;;
       --opt5  | -opt5  ) message="Unavailable ConfigMap";            manifest="opt05-configmap.yml"                  ;;
       --opt6  | -opt6  ) message="Unavailable Secret";               manifest="opt06-secret.yml"                     ;;
       --opt7  | -opt7  ) message="Resource Quota";                   manifest="opt07-resource-quota.yml"             ;;
       --opt8  | -opt8  ) message="ImagePullBackOff";                 manifest="opt08-imagepullbackoff.yml"           ;;
       --opt9  | -opt9  ) message="CrashLoopBackOff - OutOfMemory";   manifest="opt09-crashloopbackoff-oom.yml"       ;;
       --opt10 | -opt10 ) message="CrashLoopBackOff - Healthcheck";   manifest="opt10-crashloopbackoff-healthcheck.yml" ;;
       --opt11 | -opt11 ) message="CrashLoopBackOff - Init";          manifest="opt11-crashloopbackoff-init.yml"      ;;
       --opt12 | -opt12 ) message="CrashLoopBackOff - Runtime";       manifest="opt12-crashloopbackoff-runtime.yml"   ;;
       --opt13 | -opt13 ) message="Runtime Error - Service";          manifest="opt13-runtimeerr-svc.yml"             ;;
       -h | --h | --help )
           usage
           exit 0
           ;;
       * )
           err "Unknown option: $flag"
           info "Run '$0 -h' to get help."
           exit 1
           ;;
   esac
   shift
done

# ============================== Main workflow ================================
clear
require_kubectl

banner "Preparing scenario: $message"

# --- Pre-apply special setup ------------------------------------------------
if [ "$manifest" = "opt03-unbound-pv.yml" ]; then
    info "Disabling the default StorageClass so the PVC cannot bind..."
    kubectl patch storageclass standard \
        -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
        && ok "Default StorageClass disabled." \
        || warn "Could not patch StorageClass 'standard' (it may not exist on your cluster)."
fi

NODE="$(first_node)"

if [ "$manifest" = "opt04-taint-node.yml" ]; then
    info "Tainting node '$NODE' with 'taint=true:NoSchedule'..."
    kubectl taint nodes "$NODE" taint=true:NoSchedule \
        && ok "Taint applied on '$NODE'." \
        || warn "Could not apply taint (maybe already tainted)."
fi

# --- Apply the manifest -----------------------------------------------------
info "Applying manifest scenarios/$manifest ..."
if kubectl apply -f "scenarios/$manifest"; then
    ok "Manifest for '$message' applied successfully."
else
    err "Failed to apply manifest for '$message'."
fi

# --- Print the learning notes for this scenario -----------------------------
banner "What just went wrong? (read carefully)"
print_hints

echo
tip "General diagnosis workflow:"
tip "   1)  kubectl get pods -o wide"
tip "   2)  kubectl describe pod <pod-name>       # check 'Events' at the bottom"
tip "   3)  kubectl logs <pod-name> [--previous]  # look at container logs"

# --- Optional guided fix for node-affinity ----------------------------------
if [ "$manifest" = "opt02-node-affinity.yml" ]; then
    echo
    read -r -p "$(printf "%s?%s Apply node label 'mynode=demonode' on '%s' to fix the issue? (y/n): " "$C_YELLOW" "$C_RESET" "$NODE")" reply
    if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
        kubectl label node "$NODE" mynode=demonode --overwrite \
            && ok "Node label applied. Pod should schedule now." \
            || err "Failed to label the node."
    fi
fi

# --- Cleanup prompt ---------------------------------------------------------
echo
read -r -p "$(printf "%s?%s Do you want to delete the manifest and reset the cluster state? (y/n): " "$C_YELLOW" "$C_RESET")" answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    info "Deleting manifest scenarios/$manifest ..."
    kubectl delete -f "scenarios/$manifest" --ignore-not-found

    if [ "$manifest" = "opt02-node-affinity.yml" ]; then
        info "Removing node label 'mynode' from '$NODE' ..."
        kubectl label node "$NODE" mynode- 2>/dev/null || true
    fi

    if [ "$manifest" = "opt04-taint-node.yml" ]; then
        info "Removing taint 'taint=true:NoSchedule' from '$NODE' ..."
        kubectl taint nodes "$NODE" taint=true:NoSchedule- 2>/dev/null || true
    fi

    if [ "$manifest" = "opt03-unbound-pv.yml" ]; then
        info "Re-enabling default StorageClass 'standard' ..."
        kubectl patch storageclass standard \
            -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
            2>/dev/null || true
    fi

    ok "Cleanup done."
else
    warn "Skipping cleanup — remember to clean up manually before trying another scenario."
fi

sleep 2
banner "You practised: $message — try another scenario with '$0 -h'"
