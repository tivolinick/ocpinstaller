yum -y install git
git clone --single-branch --branch v1.4.4 https://github.com/rook/rook.git
cd rook/cluster/examples/kubernetes/ceph
oc create -f common.yaml
oc create -f operator-openshift.yaml
oc create -f cluster.yaml
oc create -f ./csi/rbd/storageclass.yaml
oc create -f filesystem.yaml
oc create -f ./csi/cephfs/storageclass.yaml
oc patch storageclass rook-cephfs  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
oc create -f toolbox.yaml
