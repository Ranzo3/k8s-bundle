import json
import argparse
import re

parser = argparse.ArgumentParser(description='Process k8s bundle')
parser.add_argument('--config', dest='config_file', help='Path to the configuration file')
parser.add_argument('--output', dest='output_dir', help='Path to the output directory')
args = parser.parse_args()



# Read a configuration file
def read_config_file(file_path):
    """Reads a configuration file and returns its content as a Python object."""
    config = {}
    try:
        for line in open(file_path, encoding="utf8"):
            line = line.strip()
            if line:
                # Skip comments
                if line.startswith("#"):
                    continue
                # Create dictionary of key value pairs
                parts = line.split("=")
                if len(parts) == 2:
                    key = parts[0].strip()
                    value = parts[1].strip().strip("'\"")
                    config[key] = value
        return config        
    except FileNotFoundError:
        print(f"Error: File not found at {file_path}")
        raise
        

def read_json_file(file_path):
    """Reads a JSON file and returns its content as a Python object."""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            return data
    except FileNotFoundError:
        print(f"Warning: File not found at {file_path}")
        raise
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON format in {file_path}")
        raise
        

def print_pods(pods):
    namespaceWidth=32
    nameWidth = 64
    phaseWidth=16
    hostIPWidth=16
    startTimeWidth=32

    print("{0:<{nsw}} {1:<{nw}} {2:<{pw}} {3:<{hiw}} {4:<{sw}}".format(
        "Namespace", "Name", "Phase", "Host IP", "Start Time", nw=nameWidth, nsw=namespaceWidth, pw=phaseWidth, hiw=hostIPWidth, sw=startTimeWidth))
    print("-" * (nameWidth + namespaceWidth + phaseWidth + hostIPWidth + startTimeWidth))
    for pod in pods:
        metadata = pod.get('metadata', {})
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        phase=pod.get('status',{}).get('phase')
        host_ip=pod.get('status',{}).get('hostIP')
        startTime=pod.get('status',{}).get('startTime')
        print("{0:<{nsw}} {1:<{nw}}  {2:<{pw}} {3:<{hiw}} {4:<{sw}}".format(
            namespace, name, phase, host_ip, startTime, nw=nameWidth, nsw=namespaceWidth, pw=phaseWidth, hiw=hostIPWidth, sw=startTimeWidth))

def print_wekacontainers(wekacontainers):
    namespaceWidth=32
    nameWidth = 64    
    statusWidth=32
    modeWidth=16
    startTimeWidth=32
    
    print("{0:<{nw}} {1:<{nsw}} {2:<{sw}} {3:<{mw}} {4:<{stw}}".format(
        "Name", "Namespace", "Status", "Mode", "Start Time", nw=nameWidth, nsw=namespaceWidth, sw=statusWidth, mw=modeWidth, stw=startTimeWidth))
        
    print("-" * (nameWidth + namespaceWidth + statusWidth + modeWidth + startTimeWidth))

    for wekacontainer in wekacontainers:
        metadata = wekacontainer.get('metadata', {})
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        # Sometimes status of a container is empty (None)
        status=wekacontainer.get('status',{}).get('status') or ""
        mode=metadata.get('labels',{}).get('weka.io/mode')
        startTime=metadata.get('creationTimestamp')
        print("{0:<{nw}} {1:<{nsw}} {2:<{sw}} {3:<{mw}} {4:<{stw}}".format(
            name, namespace, status, mode, startTime, nw=nameWidth, nsw=namespaceWidth, sw=statusWidth, mw=modeWidth, stw=startTimeWidth))

def print_wekaclients(wekaclients):
    namespaceWidth=32
    nameWidth = 64    
    statusWidth=32
    
    print("{0:<{nsw}} {1:<{nw}} {2:<{sw}} ".format(
        "Namespace", "Name", "Status", nsw=namespaceWidth, nw=nameWidth, sw=statusWidth))
        
    print("-" * (nameWidth + namespaceWidth + statusWidth))

    for wekaclient in wekaclients:
        metadata = wekaclient.get('metadata', {})
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        # Sometimes status of a container is empty (None)
        status=wekaclient.get('status',{}).get('status') or ""
        print("{0:<{nsw}} {1:<{nw}} {2:<{sw}} ".format(
            namespace, name, status, nsw=namespaceWidth, nw=nameWidth, sw=statusWidth))

def print_wekaclusters(wekaclusters):
    namespaceWidth=32
    nameWidth = 64    
    statusWidth=32
    
    print("{0:<{nsw}} {1:<{nw}} {2:<{sw}} ".format(
        "Namespace", "Name", "Status", nsw=namespaceWidth, nw=nameWidth, sw=statusWidth))
        
    print("-" * (nameWidth + namespaceWidth + statusWidth))

    for wekacluster in wekaclusters:
        metadata = wekacluster.get('metadata', {})
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        # Sometimes status of a container is empty (None)
        status=wekacluster.get('status',{}).get('status') or ""
        print("{0:<{nsw}} {1:<{nw}} {2:<{sw}} ".format(
            namespace, name, status, nsw=namespaceWidth, nw=nameWidth, sw=statusWidth))

       
def get_namespaces(config):
     regex_pattern = r"NAMESPACE"
     namespaces = {k: v for k, v in config.items() if re.search(regex_pattern, str(k))}
     return namespaces


def main():
    # Read config file
    if args.config_file:
        config = read_config_file(args.config_file)
        if config:
            print("Configuration loaded successfully.")
        else:
            print("Failed to load configuration.")
    else:
        print("No configuration file provided.")
        return

    namespaces = get_namespaces(config)
    print(namespaces)
    
    # For each namespace, print info
    for namespace in namespaces.values():
        pods=[]
        wekacontainers=[]
        wekaclusters=[]
        wekaclients=[]  

        print("")
        print("")
        print("Namespace: " + namespace)
        print("=" * 180)

        print("")
        print("Pods:")
        file_path = args.output_dir + '/cluster-info/' + namespace + '/pods.json'
        try:
            data = read_json_file(file_path)
            pods = data.get('items', [])
        except (FileNotFoundError) as err:
            print(file_path+" not found, probably no data for this object type in this namespace, continuing...")

        if pods:
            print_pods(pods)
        else:
            print("No pods found in this namespace.")
            
        print("")
        print("WekaContainers:")
        file_path = args.output_dir + '/cluster-info/' + namespace + '/wekacontainer.json'
        try:
            data = read_json_file(file_path)
            wekacontainers = data.get('items', [])
        except (FileNotFoundError) as err:
            print(file_path+" not found, probably no data for this object type in this namespace, continuing...")

        if wekacontainers:
            print_wekacontainers(wekacontainers)
        else:
            print("No WekaContainers found in this namespace.")

        print("")
        print("WekaClusters:")
        file_path = args.output_dir + '/cluster-info/' + namespace + '/wekacluster.json'
        try:
            data = read_json_file(file_path)
            wekaclusters = data.get('items', [])
        except (FileNotFoundError) as err:
            print(file_path+" not found, probably no data for this object type in this namespace, continuing...")

        if wekaclusters:
            print_wekaclusters(wekaclusters)
        else:
            print("No WekaClusters found in this namespace.")
        
        print("")
        print("WekaClients:")
        file_path = args.output_dir + '/cluster-info/' + namespace + '/wekaclient.json'
        try:
            data = read_json_file(file_path)
            wekaclients = data.get('items', [])
        except (FileNotFoundError) as err:
            print(file_path+" not found, probably no data for this object type in this namespace, continuing...")
            
        if wekaclients:
            print_wekaclients(wekaclients)
        else:
            print("No WekaClients found in this namespace.")
        
    """
    Print pods
    file_path = 'logs/dev/cluster-info/weka-operator-system/pods.json'
    data = read_json_file(file_path)
    pods = data.get('items', [])
    print_pods(pods)
    """


    for pod in pods:
        metadata = pod.get('metadata', {})
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        phase=pod.get('status',{}).get('phase')
        host_ip=pod.get('status',{}).get('hostIP')
        startTime=pod.get('status',{}).get('startTime')
        

if __name__ == "__main__":
    main()  