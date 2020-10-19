import openshift as oc
import time
"""                        if 'pod' in resource_type:
                            pod = oc.selector(name).as_dict()
                            print(f'POD: {pod}')
                            status = pod['status']['phase']
                            print(f'Status: {status}')
                            if status == 'Running' or status == 'Succeeded':
                                count += 1
                                print(f'Count: {count}')
                        else:
"""

def create_resource(yaml,success,tries):
    with oc.tracking() as tracker:
        try:
            oc.create(yaml)
        except oc.OpenShiftPythonException:
            if 'AlreadyExists' in tracker.get_result().err():
                # if 'AlreadyExists' in oc.OpenShiftPythonException.get_result()
                print("Resource already exists")
            else:
                raise Exception(f'Failed: {tracker.get_result().err()}')
        except:
            raise Exception(f'Failed: {tracker.get_result().err()}')
    if success:
        try_count=0
        while len(success) > 0 and try_count < tries:
            try_count += 1
            print(f'TRY: {try_count} of {tries}')
            for criteria in success:
                resource_type=criteria[0]
                resource_name=criteria[1]
                resource_count=criteria[2]
                found=oc.selector(resource_type)
                count = 0
                for item in found:
                    name = item.qname()
                    print(f'{resource_name} in {name}')
                    if resource_name in name:
                        if 'pod' in resource_type:
                            pod = item.as_dict()
                            status = pod['status']['phase']
                            print(f'Status: {status}')
                            if status == 'Running' or status == 'Succeeded':
                                count += 1
                                print(f'Found {count} of {resource_count}')
                        else:
                            count += 1
                            print(f'Found {count} of {resource_count}')
                        if count >= resource_count:
                            success.remove(criteria)
                            break
            if len(success) == 0:
                return
            time.sleep(10)
        else:
            if try_count >= tries:
                raise Exception('Failed to create resource in time')


"""
with oc.tracking() as tracker:
    try:
        print('Current project: {}'.format(oc.get_project_name()))
        print('Current user: {}'.format(oc.whoami()))
    except:
        print('Error acquire details about project/user')

    # Print out details about the invocations made within this context.
    print(tracker.get_result())

print(__name__)
"""
"""
with oc.project("Kube_system") as project:
    print('Current user: {}'.format(oc.whoami()))
    print(project.project_name)
    print('Current project: {}'.format(oc.get_project_name()))
    print(f'Current project: {oc.get_project_name()}')
    print('Found the following pods in {}: {}'.format(oc.get_project_name(), oc.selector('pods').qnames()))
    nodes=oc.selector('nodes')
    print(f'Nodes: {nodes}')
    print(len(nodes.qnames()))
    count=0
    for node in nodes:
        if node.get_label('node-role.kubernetes.io/worker') != None:
            print(f"Name {node.name()} label:{node.get_label('node-role.kubernetes.io/worker')}")
            count+=1
    print(count)
    # nodecount=len(nodes)
    print(nodes.qnames())
    # print(nodes.count_existing())
"""

worker_count=0
for node in oc.selector('nodes'):
    if node.get_label('node-role.kubernetes.io/worker') != None:
        node.label({"cluster.ocs.openshift.io/openshift-storage": ''})
        print(f"Name {node.name()} label:{node.get_label('node-role.kubernetes.io/worker')}")
        worker_count+=1
    print("worker_count: {}".format(worker_count))
namespace="""
apiVersion: v1
kind: Namespace
metadata:
  name: local-storage
    """
created = [('namespace', 'local-storage', 1)]
create_resource(namespace,created,5)

with oc.project("local-storage") as project:
    OperatorGroup = """
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: local-storage
spec:
  targetNamespaces:
    - local-storage
    """
    created = [('OperatorGroup', 'local-operator-group', 1)]
    create_resource(OperatorGroup, created, 5)
    Subscription = """
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: local-storage
spec:
  channel: "4.5" 
  installPlanApproval: Automatic
  name: local-storage-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
"""
    created = [('pod', 'local-storage-operator', 1)]
    create_resource(Subscription, created, 10)

    localblock = """
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: block
  namespace: local-storage
spec:
  storageClassDevices:
    - devicePaths:
        - /dev/vdb
      storageClassName: localblock
      volumeMode: Block
"""
    created = [
        ('pod', 'block-local-diskmaker',worker_count),
        ('pod', 'block-local-provisioner', worker_count),
        ('sc', 'localblock', 1),
        ('pv', 'local-pv', worker_count),
    ]

    create_resource(localblock, created, 30)

    localfile = """
    apiVersion: local.storage.openshift.io/v1
    kind: LocalVolume
    metadata:
      name: file
      namespace: local-storage
    spec:
      storageClassDevices:
        - devicePaths:
            - /dev/vdc
          fsType: ext4
          storageClassName: localfile
          volumeMode: Filesystem
    """
    created = [
        ('pod', 'file-local-diskmaker', worker_count),
        ('pod', 'file-local-provisioner', worker_count),
        ('sc', 'localfile', 1),
        ('pv', 'local-pv', worker_count*2)
    ]
    create_resource(localfile, created, 30)

namespace = """
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    openshift.io/node-selector: ""
  name: openshift-storage
  """
created = [('namespace', 'openshift-storage', 1)]
create_resource(namespace,created,5)

ns_selector = oc.selector(["namespace/openshift-storage"])
ns_selector.label({"openshift.io/cluster-monitoring" : 'true'})
ns_selector.annotate({'openshift.io/node-selector': ''})
with oc.project("openshift-storage") as project:


    """oc label ns/openshift-storage openshift.io/cluster-monitoring=true
oc annotate namespace openshift-storage openshift.io/node-selector=
    """

    OperatorGroup="""
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: ocs-operator-group
  namespace: openshift-storage
spec:
  targetNamespaces:
    - openshift-storage
"""
    created = [('OperatorGroup', 'ocs-operator-group', 1)]
    create_resource(OperatorGroup, created, 5)

    Subscription="""
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-operator
  namespace: openshift-storage
spec:
  channel: stable-4.4
  installPlanApproval: Automatic
  name: ocs-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
"""
    created = [('pod', 'operator', 3)]
    create_resource(Subscription, created, 10)
    widdly='{}'
    StorageCluster = f""" 
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  monPVCTemplate:
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1
      storageClassName: localfile
      volumeMode: Filesystem
  storageDeviceSets:
    - count: 1
      dataPVCTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1
          storageClassName: localblock
          volumeMode: Block
      name: ocs-deviceset
      placement: {widdly}
      portable: false
      replica: {worker_count}
      resources: {widdly}
"""
    created = [('pod', '', worker_count * 7 + 14)]
    create_resource(StorageCluster, created, 10)

