# OCP Installer on Fyre

This is a Script to install OCP on Fyre Quick Burn stacks. 

**This script assumes you are already logged into the system as a cluster admin**

It also assumes a specific layout of the servers and uses the 200GB of extra disks that are attached to the servers. If this changes in Future Fyre builds the scripts will need to be modified. (eventually I intend to discover the spare capacity and where it is mounted)

The script takes these steps:

1. Installs the local disk operator
2. configures local volumes for OCP to use
3. installs the OCP operator
4. Configures an OCP instance.

At each step it waits for successful completion before continuing to the next step.

There is a shell version:
https://github.com/tivolinick/ocpinstaller/blob/main/shell/setup-ocs.sh

and a Python version:
https://github.com/tivolinick/ocpinstaller/blob/main/python/setup_ocs.py

*There is also a quick script that sets up rook-ceph:*
https://github.com/tivolinick/ocpinstaller/blob/main/shell/rook-ceph.sh

