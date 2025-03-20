#!/usr/bin/env bash
# Config file path (you can change this)
CONFIG_FILE="./config.env"

# Function to source a config file and set environment variables
source_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "Error: Config file '$config_file' not found." >&2
    return 1
  fi

  # Source the config file in a subshell to avoid polluting the current environment
  # and then export the variables to the current environment.
  # This also handles comments and empty lines.
  
  set -a # Automatically export all variables
  source "$config_file"
  
  
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to source config file '$config_file'." >&2
    return 1
  fi

  echo "Successfully loaded config from '$config_file'."
  return 0
}


# Source the config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
  source_config "$CONFIG_FILE"
fi

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

# Default values
namespace=$NAMESPACE
operator_namespace=$OPERATOR_NAMESPACE
wekacluster_namespace=$WEKACLUSTER_NAMESPACE
wekaclient_namespace=$WEKACLIENT_NAMESPACE
csi_namespace=$CSI_NAMESPACE
output_dir="./logs/"$(date +%Y-%m-%d_%H-%M-%S)
since="1h"
tail_lines="100"
kubeconfig=~/.kube/config
dump_cluster=false
wekacluster_info=false




# Function to display usage information
usage() {
  echo "Usage: $0 [-o <output_dir>] [-s <since>] [-t <tail_lines>]"
  echo "  -o <output_dir>  : Output directory for logs (default: $output_dir)"
  echo "  -s <since>       : Time duration for logs (e.g., 1h, 30m, 1d) (default: $since)"
  echo "  -t <tail_lines>  : Number of lines to tail from the end of the logs (default: $tail_lines)"
  echo "  -k <kubeconfig>  : Path to the kubeconfig file (default: ~/.kube/config)"
  echo "  -d               : Dump cluster info (flag: default: Off)"
  echo "  -c               : Capture WekaCluster specific info (flag: default: Off)"
  echo "  -h               : Display this help message"
  exit 1
}

if [ $# -eq 0 ]; then
  usage
fi


# Parse command-line arguments
while getopts "o:s:t:k:dch" opt; do
  case $opt in
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
    d)
      dump_cluster=true
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


# Function to dump cluster info for WEKA namespaces
dump_cluster_info() {
  echo "Gathering cluster info..."
  echo "Running command: kubectl --kubeconfig $kubeconfig cluster-info dump --output-directory $output_dir/cluster-info -ojson --namespaces $namespace,$operator_namespace,$wekacluster_namespace,$wekaclient_namespace,$csi_namespace"
  kubectl --kubeconfig $kubeconfig cluster-info dump --output-directory $output_dir/cluster-info -ojson --namespaces $namespace,$operator_namespace,$wekacluster_namespace,$wekaclient_namespace,$csi_namespace
  if [ $? -ne 0 ]; then
    echo "Error getting cluster info"
  fi
}



### Start Untested functions ###

# Function to get all namespaces
dump_namespaces() {
  local namespaces_file="$output_dir/namespaces.txt"
  echo "Gathering namespaces..."
  echo "Running command: kubectl --kubeconfig $kubeconfig get namespaces"
  kubectl --kubeconfig "$kubeconfig" get namespaces > "$namespaces_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error getting namespaces"
  fi
}

# Function to dump all events
dump_events() {
  local events_file="$output_dir/events.txt"
  echo "Gathering events..."
  echo "Running command: kubectl --kubeconfig $kubeconfig get events --all-namespaces"
  kubectl --kubeconfig "$kubeconfig" get events --all-namespaces > "$events_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error getting events"
  fi
}

# Function to dump all persistent volumes
dump_pvs() {
  local pvs_file="$output_dir/persistent_volumes.txt"
  echo "Gathering persistent volumes..."
  echo "Running command: kubectl --kubeconfig $kubeconfig get pv"
  kubectl --kubeconfig "$kubeconfig" get pv > "$pvs_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error getting persistent volumes"
  fi
}

# Function to dump all persistent volume claims
dump_pvcs() {
  local pvcs_file="$output_dir/persistent_volume_claims.txt"
  echo "Gathering persistent volume claims..."
  echo "Running command: kubectl --kubeconfig $kubeconfig get pvc --all-namespaces"
  kubectl --kubeconfig "$kubeconfig" get pvc --all-namespaces > "$pvcs_file"
  if [ $? -ne 0 ]; then
    echo "Error getting persistent volume claims"
  fi
}

### End Untested Functions ###


# Function to get logs for one container in one pod
get_pod_logs() {
  local pod_name="$1"
  local container_name="$2"
  local pod_namespace="$3"
  local log_file="$output_dir/${pod_name}_${container_name}.log"

  echo "Gathering logs for pod: $pod_name, container: $container_name"
  echo "Running command: kubectl --kubeconfig $kubeconfig logs $pod_name -n $pod_namespace -c $container_name --since=$since --tail=$tail_lines"
  kubectl --kubeconfig "$kubeconfig" logs "$pod_name" -n "$pod_namespace" -c "$container_name" --since="$since" --tail="$tail_lines" > "$log_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error getting logs for pod: $pod_name, container: $container_name, namespace: $pod_namespace"
  fi
}

# Function to desribe one pod
describe_pod() {
  local pod_name="$1"
  local pod_namespace="$2"
  local pod_file="$output_dir/pod_${pod_name}.describe"

  echo "Describing pod: $pod_name, namespace: $pod_namespace"
  echo "Running command: kubectl --kubeconfig $kubeconfig describe pod $pod_name -n $pod_namespace -o yaml"
  kubectl --kubeconfig "$kubeconfig" describe pod "$pod_name" -n "$pod_namespace" > "$pod_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error describing pod: $pod_name, namespace: $pod_namespace"
  fi
}


# Function to describe one node
describe_node() {
  local node_name="$1"
  local node_file="$output_dir/node_${node_name}.describe"

  echo "Describing node: $node_name"
  echo "Running command: kubectl --kubeconfig $kubeconfig describe node $node_name"
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
  echo "Running command: kubectl --kubeconfig $kubeconfig debug node/$node_name -q --image=busybox --attach=true --target=host -- chroot /host cat $logfile"
  kubectl --kubeconfig "$kubeconfig" debug node/"$node_name" -q --image=busybox --attach=true --target=host -- chroot /host cat "$logfile" > "$log_file" 2>&1
  #  kubectl --kubeconfig kube-ranzo-20250311.yaml debug node/18.144.156.82 --attach=true --image=busybox -- ls

  if [ $? -ne 0 ]; then
    echo "Error getting logfile: $logfile from node: $node_name"
  fi
}

# Function to capture output from one 'weka' command run on one pod
run_wekacluster_cmd() {
  local pod_name="$1"
  local pod_namespace="$2"
  local cmd="$3"
  local log_file="$output_dir/wekacluster.log"
  echo "Running command: $cmd, pod: $pod_name, namespace: $pod_namespace"
  echo "Running command: kubectl --kubeconfig $kubeconfig exec -n $pod_namespace $pod_name -- $cmd"
  kubectl --kubeconfig "$kubeconfig" exec -n $pod_namespace $pod_name -- $cmd >> "$log_file" 2>&1
  if [ $? -ne 0 ]; then
    echo "Error running command: $cmd"
    return 1
  fi
}

# Function to get all pods in a namespace
get_all_pods() {
  local namespace="$1"
  echo "Running command: kubectl --kubeconfig $kubeconfig get pods -n $namespace -o jsonpath='{.items[*].metadata.name}'"
  kubectl --kubeconfig "$kubeconfig" get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}'
  if [ $? -ne 0 ]; then 
    echo "Error getting pods in namespace: $namespace"
    exit 1
  fi
  if [ "$pods" == "" ]; then
    echo "No pods found in namespace: $namespace"
    exit 1
  fi
}

# Function to clean up debugger pods
cleanup_debug_pods() {
  #echo "Cleaning up debug pods..."
  # echo "Running command: kubectl --kubeconfig $kubeconfig get pods -n default -o=custom-columns=NAME:.metadata.name | grep node-debugger | xargs -I {} kubectl --kubeconfig $kubeconfig delete pod -n default {}"
  # kubectl get pods -n default -o=custom-columns=NAME:.metadata.name | grep node-debugger | xargs -I {} kubectl delete pod -n default {}
  # ^^^ Some bug prevents this from working when called from the script but it works with zsh

 echo "Please review and run the following command: kubectl --kubeconfig $kubeconfig get pods -n default -o=custom-columns=NAME:.metadata.name | grep node-debugger | xargs -I {} kubectl --kubeconfig $kubeconfig delete pod -n default {}"

  
  if [ $? -ne 0 ]; then
    echo "Error cleaning up debug pods"
  fi
}


if [[ $dump_cluster == "true" ]]; then
  dump_cluster_info
fi

# Get all nodes in the K8s cluster
nodes=$(kubectl --kubeconfig "$kubeconfig" get nodes -o jsonpath='{.items[*].metadata.name}')

# Get all compute pods in the WekaCluster namespace
compute_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$wekacluster_namespace" --selector weka.io/mode=compute -o jsonpath='{.items[*].metadata.name}')

# Get all drive pods in the WekaCluster namespace
drive_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$wekacluster_namespace" --selector weka.io/mode=drive -o jsonpath='{.items[*].metadata.name}')

# Get all client pods in the WekaClient namespace
client_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$wekaclient_namespace" --selector weka.io/mode=client -o jsonpath='{.items[*].metadata.name}')

# Get all pods in the Weka Operator namespace
operator_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$operator_namespace" -o jsonpath='{.items[*].metadata.name}')

# Get all pods in the CSI namespace
csi_pods=$(kubectl --kubeconfig "$kubeconfig" get pods -n "$csi_namespace" -o jsonpath='{.items[*].metadata.name}')



# If wekacluster_info is true, run wekacluster commands for one pod
if [ "$wekacluster_info" = "true" ]; then
  # Iterate over each compute pod in the WekaCluster namespace until one of them works
  for cmd in "${weka_cmd_array[@]}"; do
      for pod in $compute_pods; do
        run_wekacluster_cmd "$pod" "$wekacluster_namespace" "$cmd"
        if [ $? -eq 0 ]; then
          break
        fi
      done
  done
fi



# Iterate over each compute pod in the Weka Cluster namespace
for pod in $compute_pods; do
  # Describe the pod and place in logs
  describe_pod "$pod" "$wekacluster_namespace"

  # Get all containers in the current pod
  containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')

  # Iterate over each container in the current pod
  for container in $containers; do
    get_pod_logs "$pod" "$container" "$wekacluster_namespace"
  done
done

# Iterate over each drive pod in the Weka Cluster namespace
for pod in $drive_pods; do
  # Describe the pod and place in logs
  describe_pod "$pod" "$wekacluster_namespace"

  # Get all containers in the current pod
  containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')

  # Iterate over each container in the current pod
  for container in $containers; do
    get_pod_logs "$pod" "$container" "$wekacluster_namespace"
  done
done

# Iterate over each client pod in the Weka Client namespace
for pod in $client_pods; do
  # Describe the pod and place in logs
  describe_pod "$pod" "$wekaclient_namespace"

  # Get all containers in the current pod
  containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')

  # Iterate over each container in the current pod
  for container in $containers; do
    get_pod_logs "$pod" "$container" "$wekaclient_namespace"
  done
done


# Iterate over each pod in the CSI namespace
for pod in $csi_pods; do
  # Describe the pod and place in logs
  describe_pod "$pod" "$csi_namespace"

  # Get all containers in the current pod
  containers=$(kubectl --kubeconfig "$kubeconfig" get pod "$pod" -n "$csi_namespace" -o jsonpath='{.spec.containers[*].name}')

  # Iterate over each container in the current pod
  for container in $containers; do
    get_pod_logs "$pod" "$container" "$csi_namespace"
  done
done


# Iterate over each node
for node in $nodes; do
  # Describe the node and place in logs
  describe_node "$node"
  # Iterate over each logfile
#  for logfile in "${logfile_array[@]}"; do
#    get_node_logfile "$node" "$logfile"
#  done
done


echo "Logs saved to: $output_dir"

cleanup_debug_pods




