#!/bin/bash

# Uncomment for debug messages and to progress in steps
#debug=1

#Function to check that pods are Running or Complete
# args <podname search> <number expected> <retries>
function checkpods {
  podname=$1
  count=$2
  retries=$3
  try=0
  [ $podname == 'ALL' ] && result=$(oc get pods 2>/dev/null | grep -e Running -e Complete | wc -l) || result=$(oc get pods 2>/dev/null | grep -e Running -e Complete | grep $podname | wc -l)
  [ "$debug" ] && echo $result -ne $count
  while [ $result -ne $count ] ; do
    try=$(expr $try + 1)
    if [ $try -gt $retries ] ; then
       [ $podname == 'ALL' ] && echo "Failed to start $count pods in time" || echo "Failed to start $count pods with name containing $podname in time"
      echo PODS:
      oc get pods
      exit 1
    fi
    [ $podname == 'ALL' ] && echo "$try of $retries: waiting for pods to start $result of $count running........."|| echo "$try of $retries: waiting for pods with names containing $podname to start $result of $count running........."
    [ $podname == 'ALL' ] && result=$(oc get pods 2>/dev/null | grep -e Running -e Complete | wc -l) || result=$(oc get pods 2>/dev/null | grep -e Running -e Complete | grep $podname | wc -l)
    [ "$debug" ] && echo $result -ne $count
    sleep 10
  done
}

#Function to check for existence of a resource with a specific name
# args <podname search> <number expected> <retries> <resource type>
function checkres {
  resname=$1
  count=$2
  retries=$3
  restype=$4

  try=0
  result=$(oc get $restype 2>/dev/null | grep $resname | wc -l)
  [ "$debug" ] && echo $result -ne $count
  while [ $result -ne $count ] ; do
    try=$(expr $try + 1)
    if [ $try -gt $retries ] ; then
      echo "$count of $restype with name $resname not created in tine"
      echo $restype
      oc get $restype
      exit 1
    fi
    echo "$try of $retries: waiting for $count $restype with names containing $resname to start........."
    result=$(oc get $restype 2>/dev/null | grep $resname | wc -l)
    [ "$debug" ] && oc get $restype 2>/dev/null
    [ "$debug" ] && echo $result -ne $count
    sleep 10
  done
}


# expects you to already be logged into OCP as a cluster admin
oc whoami &> /dev/null
if [ $? -ne 0 ] ; then
  echo log in as a cluster admin before you run this script
  exit 2
fi
#~/login
workernodes=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath={.items[*].metadata.name})
workercount=$(echo $workernodes | wc -w)
echo workers: $workernodes, count:$workercount

#install local-storage operator in local-storage ns
echo '>>>> installing local-storage operator in local-storage ns'
oc create -f - <<@
apiVersion: v1
kind: Namespace
metadata:
  name: local-storage
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: local-storage
spec:
  targetNamespaces:
    - local-storage
---
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
@
oc project local-storage

# wait for operator pod to start
checkpods operator 1 10

[ "$debug" ] && echo PV
[ "$debug" ] && oc get pv
[ "$debug" ] && echo PVC
[ "$debug" ] && oc get pvc
[ "$debug" ] && echo SC
[ "$debug" ] && oc get sc
echo '>>>> installed local-storage operator in local-storage ns'
[ ! -z "$debug" ] && echo 'hit return to continue >>>>>'
[ "$debug" ] && read a


echo '>>>> creating local storage on each worker'
oc create -f - <<EOF
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
---
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
EOF


checkpods block-local-diskmaker $workercount 10
checkpods block-local-provisioner $workercount 10
checkpods file-local-diskmaker $workercount 10
checkpods file-local-provisioner $workercount 10

checkres localblock 1 5 sc
checkres localfile 1 5 sc
checkres localblock $workercount 5 pv
checkres localfile $workercount 5 pv

[ "$debug" ] && echo pods:
[ "$debug" ] && oc get pods
[ "$debug" ] && echo pv:
[ "$debug" ] && oc get pv
echo '>>>> created local storage on each worker'
[ "$debug" ] && echo 'hit return to continue >>>>>'
[ "$debug" ] && read a

echo '>>>> installing OCS operator'
# Install OCS operator
oc create -f - <<@
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-storage
@
oc project openshift-storage
oc label ns/openshift-storage openshift.io/cluster-monitoring=true
oc annotate namespace openshift-storage openshift.io/node-selector=

oc create -f - <<@
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: ocs-operator-group
  namespace: openshift-storage
spec:
  targetNamespaces:
    - openshift-storage
---
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
@

checkpods operator 3 15

echo '>>>> installed OCS operator'
[ "$debug" ] && echo 'hit return to continue >>>>>'
[ "$debug" ] && read a

echo '>>>> creating OCS cluster on all workers'
# label all workers available for OCS cluster
for node in $workernodes ; do
  [ "$debug" ] && echo labeling $node
  oc label node/$node cluster.ocs.openshift.io/openshift-storage=""
done

# create storage cluster
oc create -f - <<@
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
      placement: {}
      portable: false
      replica: $workercount
      resources: {}
@

[ "$debug" ] && oc get pods
podcount=$(expr $workercount \* 7 + 14)

checkpods ALL $podcount 60

[ "$debug" ] && echo pv:
[ "$debug" ] && oc get pv
[ "$debug" ] && echo pvc:
[ "$debug" ] && oc get pvc
[ "$debug" ] && echo pods:
[ "$debug" ] && oc get pods

echo '>>>> created OCS cluster on all workers'
[ "$debug" ] && echo 'hit return to continue >>>>>'
[ "$debug" ] && read a
