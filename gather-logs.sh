#!/usr/bin/env bash

# Log this scripts ouptut to a logfile
# mylog=gather-logs.$(date +%Y-%m-%d_%H-%M-%S).log
# exec > >(tee -i $mylog)
# exec 2>&1

# Assumptions
#   bash in your environment and PATH
#   kubectl in your enviornment and PATH

# Config values
# Future enhancement: detect OS and set logfile_array accordingly
# Future enhancement: allow wildcards in logfile_array
logfile_array=("/var/log/error" "/var/log/syslog" "/proc/wekafs/interface")
weka_cmd_array=("weka events -n 10000" "weka status")
namespace_array=("default" "weka-operator-system" "csi-wekafs")

# Default values
namespace="default"
operator_namespace="weka-operator-system"
output_dir="./logs/"$(date +%Y-%m-%d_%H-%M-%S)
since="1h"
tail_lines="100"
kubeconfig=~/.kube/config


# Function to display usage information
usage() {
  echo "Usage: $0 [-n <namespace>] [-o <output_dir>] [-s <since>] [-t <tail_lines>]"
  echo "  -n <namespace>   : Kubernetes namespace of the WekaCluster and/or WekaClient (default: $namespace)"
  echo "  -w <namespace>   : Kubernetes namespace of the Weka Operator code (default: $operator_namespace)"
  echo "  -o <output_dir>  : Output directory for logs (default: $output_dir)"
  echo "  -s <since>       : Time duration for logs (e.g., 1h, 30m, 1d) (default: $since)"
  echo "  -t <tail_lines>  : Number of lines to tail from the end of the logs (default: $tail_lines)"
  echo "  -k <kubeconfig>  : Path to the kubeconfig file (default: ~/.kube/config)"
  echo "  -c               : Capture WekaCluster specific info (flag: default: Off)"
  echo "  -h               : Display this help message"
  exit 1
}

if [ $# -eq 0 ]; then
  usage
fi

# Parse command-line arguments
while getopts "n:w:o:s:t:k:ch" opt; do
  case $opt in
    n)
      namespace="$OPTARG"
      ;;
    w)
      operator_namespace="$OPTARG"
      ;;
    o)
      output_dir="$OPTARG"
      ;;
    s)
      since="$OPTARG"
      ;;
    t)
      tail_lines="$OPTARG"
      ;;
    k)
      kubeconfig="$OPTARG"
      ;;
    c)
      wekacluster_info=true
      ;;

    h)
      usage
      ;;
    *)
      usage
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done



# Create output directory if it doesn't exist
mkdir -p "$output_dir"



# Function to get logs for one container in one pod
get_pod_logs() {
  local pod_name="$1"
  local container_name="$2"
  local pod_namespace="$3"
  local log_file="$output_dir/${pod_name}_${container_name}.log"

  echo "Gathering logs for pod: $pod_name, container: $container_name"
  kubectl --kubeconfig "$kubeconfig" logs "$pod_name" -n "$pod_namespace" -c "$container_name" --since="$since" --tail="$tail_lines" > "$log_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error getting logs for pod: $pod_name, container: $container_name, namespace: $pod_namespace"
  fi
}

# Function to desribe a one pod
describe_pod() {
  local pod_name="$1"
  local pod_namespace="$2"
  local pod_file="$output_dir/pod_${pod_name}.describe"

  echo "Describing pod: $pod_name"
  kubectl --kubeconfig "$kubeconfig" describe pod "$pod_name" -n "$pod_namespace" -o yaml > "$pod_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error describing pod: $pod_name, namespace: $pod_namespace"
  fi
}


# Function to describe one node
describe_node() {
  local node_name="$1"
  local node_file="$output_dir/node_${node_name}.describe"

  echo "Describing node: $node_name"
  kubectl --kubeconfig "$kubeconfig" describe node "$node_name" > "$node_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error describing node: $node_name"
  fi
}

# Function to capture one logfile from one node
get_node_logfile() {
  local node_name="$1"
  local logfile="$2"
  local log_file="$output_dir/node_${node_name}_$(basename "$logfile").log"

  echo "Gathering logfile: $logfile from node: $node_name"
  kubectl --kubeconfig "$kubeconfig" debug node/"$node_name" -q --image=busybox --attach=true --target=host -- chroot /host cat "$logfile" > "$log_file" 2>&1
  #  kubectl --kubeconfig kube-ranzo-20250311.yaml debug node/18.144.156.82 --attach=true --image=busybox -- ls

  if [ $? -ne 0 ]; then
    echo "Error getting logfile: $logfile from node: $node_name"
  fi
}

# Function to run capture output from one 'weka' command
run_wekacluster_cmd() {
  local pod_name="$1"
  local pod_namespace="$2"
  local cmd="$3"
  local log_file="$output_dir/wekacluster.log"
  echo "Running command: $cmd, pod: $pod_name, namespace: $pod_namespace"
  kubectl --kubeconfig "$kubeconfig" exec -n $pod_namespace $pod_name -- $cmd >> "$log_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error running command: $cmd"
    return 1
  fi
}





# Get all nodes in the K8s cluster
nodes=$(kubectl --kubeconfig "$kubeconfig" get nodes -o jsonpath='{.items[*].metadata.name}')

# Get all pods in the WekaCluster and/or WekaClient namespace
pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}')

# Get all pods in the Weka Operator namespace
operator_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$operator_namespace" -o jsonpath='{.items[*].metadata.name}')

# If wekacluster_info is true, run wekacluster commands for one pod
if [ "$wekacluster_info" = "true" ]; then
  # Get all pods in the WekaCluster namespace
  #pods=$(kubectl --kubeconfig "$kubeconfig" get pods  -n "$namespace" -o jsonpath='{.items[*].metadata.name}')

  # Iterate over each pod in the WekaCluster namespace until one of them works
  for cmd in "${weka_cmd_array[@]}"; do
    echo "Running command: $cmd"
      for pod in $pods; do
        run_wekacluster_cmd "$pod" "$namespace" "$cmd"
        if [ $? -eq 0 ]; then
          break
        fi
      done
  done
fi

# Iterate over each pod in all namespaces
for namespace in '{$namespace_array[@]}'; do
  # Get all pods in the current namespace
  pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$namespace]
  for pod in $pods; do
    # Describe the pod and place in logs
    describe_pod "$pod" "$namespace"
    
    # Get all containers in the current pod
    containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')
    
    # Iterate over each container in the current pod
    for container in $containers; do
      get_pod_logs "$pod" "$container" "$namespace"
    done
  done
done

exit 0

# Iterate over each pod in the Weka Operator namespace
for pod in $operator_pods; do
  # Describe the pod and place in logs
  describe_pod "$pod" "$operator_namespace"

  # Get all containers in the current pod
  containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$operator_namespace" -o jsonpath='{.spec.containers[*].name}')

  # Iterate over each container in the current pod
  for container in $containers; do
    get_pod_logs "$pod" "$container" "$operator_namespace"
  done
done


# Iterate over each node
for node in $nodes; do
  # Describe the node and place in logs
  describe_node "$node"
  # Iterate over each logfile
  for logfile in "${logfile_array[@]}"; do
    echo $logfile
    get_node_logfile "$node" "$logfile"
  done
done


echo "Logs saved to: $output_dir"



