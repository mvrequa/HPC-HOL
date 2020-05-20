# Managing an EDA environment using CycleCloud

This project demonstrates configuration for LSF cluster
leveraging Azure NetAPP files for storage and CycleCloud
for automation.

This project assumes several prerequisites are setup, configured and running.

Cluster Pre-requisites
* LSF Installer and License Files
* Virtual Network
* Azure NetAPP Files Volume
* CycleCloud

Application pre-requisites
* Cadence Xcelium Licenses and Running License Server
* Cadence download username and password
* InstallScape installer

## Setup the master node(s)

We'll use CycleCloud to do what most admins will do manually - setup the LSF master nodes.

### Uploading LSF installers
When we created the CycleCloud instance and configured subscription access, we also created or specified
a Storage Account.

Let's identify the storage account and get a temporary SAS token to access blobs therein. 

```bash
cyclecloud locker list
azure-storage (az://edalabdemo/cyclecloud)

STORAGE_ACCOUNT="edalabdemo"
SAS_TOKEN="?sv=2019-10-10&ss=bfqt&srt=sco&sp=rwdlacupx&se=2020-05-14T23:20:17Z&st=2020-05-12T15:20:17Z&spr=https&sig=REMOVED"
``` 

From the CycleCloud cli we see the Storage Account (_edalabdemo_) and Container (_cyclecloud_).
Go to the Azure Portal and generate a SAS token to use when storing blobs. 

Put all the [LSF installers](https://github.com/Azure/cyclecloud-lsf#ibm-spectrum-lsf) into
a _blobs/_ directory and upload them to the CycleCloud User Blobs location.

```bash
BLOB="cyclecloud/blobs/lsf/"
azcopy cp "./blobs/*" "https://$STORAGE_ACCOUNT.blob.core.windows.net/${BLOB}$SAS_TOKEN"
```

### Update the LSF cluster template

Let's use the [fully-managed LSF template](https://github.com/Azure/cyclecloud-lsf/blob/master/examples/lsf-full.txt) 
in cyclecloud-lsf as a starting point for the master node(s).
All the changes we want are concerning NFS mounts. We want to move the LSF mount
from the project fileserver to an Azure NetAPP Volume.
In this lab we'll use two methods to accomplish the same thing.

On the execute nodes we'll update _/etc/fstab_ to have this mount: 

```/etc/fstab
10.0.16.4:/main /stor nfs rw,hard,tcp,vers=3,rsize=65536,wsize=65536 0 0
```

On the master nodes we'll update the cluster template to have an [NFS mount](https://docs.microsoft.com/azure/cyclecloud/how-to/mount-fileserver).
Both methods are equivalent. The LSF template also has a hard reference to the shared filesystem host.
We'll want to move the NFS filesystem mount away from _$LSF_TOP_ and to an alternate place on the filesystem.
Where we see _sched-exp_ we'll change _$LSF_TOP_ to _/backup_. So _$LSF_TOP_ is now backed by the NetAPP filesystem and no longer the in-project filesystem.
The diff of the example lsf cluster is shown below. A few lines replace the
internally managed file system to 

```diff
--- a/examples/lsf-full.txt
+++ b/examples/lsf-full.txt
@@ -32,6 +32,12 @@

         cyclecloud.selinux.policy = permissive

+       # CUSTOM SECTION FOR EDA-LAB, ANF
+        [[[configuration cyclecloud.mounts.anf]]]
+           type = nfs
+           address = 10.0.16.4
+           mountpoint = /stor
+           export_path = /main

         [[[cluster-init cyclecloud/lsf:default:$LsfProjectVersion]]]

@@ -104,7 +110,7 @@

         [[[configuration cyclecloud.mounts.sched-exp]]]
         type = nfs
-        mountpoint = $LSF_TOP
+        mountpoint = /backup
         export_path = /mnt/raid/lsf

         [[[configuration cyclecloud.mounts.home]]]
@@ -151,7 +157,7 @@

         [[[configuration cyclecloud.mounts.sched-exp]]]
         type = nfs
-        mountpoint = $LSF_TOP
+        mountpoint = /backup
         export_path = /mnt/raid/lsf
```

### Import modified cluster template and create the cluster

Now that we've updated the master template to contain the appropriate mounts let's
import the cluster. This call imports as a template, such that instances of this 
template can be created via the UI with only configuration.

```bash
cyclecloud import_cluster lsf-master-DEMO -c lsf -f lsf-full.txt -t
```

Proceed to the UI and add a cluster of this type in the virtual network
containing the NetAPP Volume.

## Configure the LSF Master and the Worker Array

Allowing the LSF master cluster to start will set the baseline configuration for LSF.
However, we want to treat the master node as a manually configured host and 
configure LSF to work with a different CycleCloud cluster.

To move LSF do a different filesystem, change the _LSF_TOP_ property in the 
cluster menu to _/stor/lsf_. This location is defined with the template
modifications to fall on ANF.

### Create a CycleCloud user for API access

LSF must be provided API keys (username, password) to interact with CycleCloud. Create a basic
user in the Settings / User tab to be used as the "API user". Retain the username and password.

### Create the LSF worker cluster

CycleCloud has an LSF type built into the project. This cluster is designed to work with an 
independent master node which could even be in a private (non-Azure) data center. Let's create
this cluster, grant the API user privileges, and make a config change, all in the UI.

Using the Add cluster menu, create a LSF cluster. Make sure to use the appropriate subnet to
access the NetAPP filesystem. Use the VM chooser to pick two different types of execute VMs; Standard_F32s_v2 and Standard_H44rs. Note that we'll select the basic CentOS Marketplace image.
Save the settings and the cluster will appear in the cluster list will full edit capabilities.

Use the UI to make the following customizations:

* Grant the API user the "Manage this cluster" permission.
* Add `cuser.base_home_dir = /shared/home` to the configuration section in each of the node arrays.
* Change the _LSF_TOP_ property in the edit menu to _/stor/lsf_.

Start the cluster and we're ready to integrate the master node with this new cluster.

### Configure the LSF resource connector

Log into the LSF master with the cyclecloud command line:
```bash
cyclecloud connect master-1 -c $LSF_MASTER_CLUSTER
```

You'll find that the LSF master daemons are running and that the resource connector is already
configured for the master cluster. The configurations we're going to change are described in
the [IBM documentation](https://www.ibm.com/support/knowledgecenter/SSWRJV_10.1.0/lsf_resource_connector/lsf_rc_config_cycle.html) for this solution. To complete the integration
we'll want to update three files in _$LSF_TOP/conf/resource_connector/cyclecloud/conf_.

1. _cyclecloudprov_config.json_ - CycleCloud connection information
1. _cyclecloudprov_templates.json_ - LSF autoscaling template definitions
1. _user_data.sh_ - LSF worker boot-up script

####  _cyclecloudprov_config.json_

Modify [this file](https://www.ibm.com/support/knowledgecenter/SSWRJV_10.1.0/lsf_resource_connector/lsf_rc_azureccprovconfig.html) 
to access the lsf worker cluster created in the previous steps.
Use the CycleCloud details, new LSF cluster name, API user details

| config  | value  | 
|---|---|
| AZURE_CC_SERVER  | URL of CycleCloud  |
| AZURE_CC_CLUSTER  | LSF cluster name  |
| AZURE_CC_USER  | API user name  |
| AZURE_CC_PASSWORD  | API user password  |

#### _cyclecloudprov_templates.json_

[This file](https://www.ibm.com/support/knowledgecenter/SSWRJV_10.1.0/lsf_resource_connector/lsf_rc_azureccprovtemplates.html) 
will already exist with boilerplate. It's also available in the [github project](https://github.com/Azure/cyclecloud-lsf/blob/master/examples/cyclecloudprov_templates.json).
 Update the templates to use new *vmSize*; *Standard_F32s_v2* for the *ondemand* nodes and *Standard_Hc44rs* for the *ondemandmpi*
templates. **For LSF to properly autoscale, you must update the ncpus/ncores/mem values according to the new vmSize**, e.g. ncores=ncpus=44 for *Standard_Hc44rs*. 

We'll be adding a new custom script in the next section. Add a reference to it in this file by
setting _customScriptUri_. 
The URI should be a SAS-signed URL to a blob in the same storage account having the format below.

```bash
https://$STORAGE_ACCOUNT.blob.core.windows.net/cyclecloud/lsf/user_data.sh$SAS_TOKEN
```

This file has templates which already correspond to lsf queues so it leverages
the extended LSF configuration that is part of the master node recipes in _lsf-full.txt_.

#### _user_data.sh_

This file has a single essential goal; to properly start the LSF daemons. There are
several configurations that we will add to support proper daemon configuration. 
The CycleCloud [LSF project example](https://github.com/Azure/cyclecloud-lsf/blob/master/examples/user_data.sh) is a good starting point. Once the updates are complete, this script 
will serve to:

* add the lsfadmin user 
* mount the in-project (for _/shared/home_) and ANF (for _/stor_) filesystem
* make a local copy of _lsf.conf_ and populate [_LSF_LOCAL_RESOURCES_](https://www.ibm.com/support/knowledgecenter/SSETD4_9.1.2/lsf_config_ref/lsf.conf.lsf_local_resources.5.html) for heterogeneous clusters
* set _LSF_ENVDIR_ and start the daemons 

The diff resulting of this file compared to the original example is here:

```diff
--- a/examples/user_data.sh
+++ b/examples/user_data.sh
@@ -1,15 +1,34 @@
 #!/bin/bash
 set -x

-LSF_TOP_LOCAL=/grid/lsf
-LSF_CONF=$LSF_TOP_LOCAL/conf/lsf.conf
+if ! grep -q lsfadmin /etc/passwd ; then
+  useradd lsfadmin
+fi
+
+mkdir -p /stor
+
+if ! grep -q "10.0.0.6" /etc/fstab ; then
+  echo "10.0.0.6:/mnt/raid/home /shared/home nfs defaults,proto=tcp,nfsvers=3,rsize=65536,wsize=65536,noatime 0 0" >> /etc/fstab
+fi
+
+if ! grep -q "10.0.16.4" /etc/fstab ; then
+  echo "10.0.16.4:/main /stor nfs rw,hard,tcp,vers=3,rsize=65536,wsize=65536 0 0" >> /etc/fstab
+fi
+
+mount -a
+
+mkdir -p /etc/lsf
+cp /stor/lsf/conf/lsf.conf /etc/lsf/
+LSF_CONF=/etc/lsf/lsf.conf
+LSF_TOP_LOCAL=/stor/lsf
+


@@ -58,7 +77,7 @@ if [ -n "${placement_group_id}" ]; then
 fi

 echo "LSF_LOCAL_RESOURCES=\"${TEMP_LOCAL_RESOURCES}\"" >> $LSF_CONF
-
+export LSF_ENVDIR=/etc/lsf

 lsadmin limstartup
 lsadmin resstartup
 badmin hstartup
```

### Submit test jobs

The LSF RC configuration is complete and the LSF master node is ready to dynamically autoscale the LSF cluster. Submit a job to the default queue and observe that a node is added.

```bash 
bsub /bin/sleep 60
bsub -q ondemandmpi /bin/sleep 60
```

These two jobs will run on different nodes. One node will be _Standard_F32s_v2_ and the other will be _Standard_H44rs_, demonstrating
the heterogeneous node capability of this solution. 
You can now continue to tune an stratify your cluster based on matching
job requirements with VM resources.

## Setup the EDA workflow

Xcelium is a licensed simulator for design verification. When you setup this lab,
realize that you must bring-your-own license. This will be set as a license server
environment variable during runtime.

Pre-requisites
* Test case in object store
* Shared access token for storage account
* License server access
* Cadence download credentials

### Install Xcelium to NetApp Volume

This lab makes use of Xcelium by Cadence. To install we'll use the Cadence InstallScape 
tool chain. Use the following script to install Xcelium - it can take 20 min for this
to run as it downloads installers and artifacts for the Xcelium software. 


```bash
#!/bin/bash

LOCAL_SSD=/mnt/resource
INST_DIR=/stor/apps

mkdir -p $INST_DIR
chmod 777 $INST_DIR
cd $INST_DIR

azcopy cp "https://$STORAGE_ACCOUNT.blob.core.windows.net/${BLOB}${SAS_TOKEN}" .

tar -xf IScape04.23-s012lnx86.t.Z -C $INST_DIR

yum -y install java-1.8.0-openjdk
yum -y install redhat-lsb.i686

#http://sw.cadence.com/is/XCELIUM1809/lnx86/Hotfix_XCELIUMMAIN18.09.011

cat <<EOF > xcelium_ctl.txt
sourceLocation=http://sw.cadence.com/is/XCELIUM1809/lnx86/Base
minorAction=Install
MajorAction=Download
installDirectory=$INST_DIR/cadence
archiveDirectory=$LOCAL_SSD/archive
cacheDirectory=$LOCAL_SSD/cache
saveCadenceUserNameAndPassword=true
EOF

$INST_DIR/iscape.04.23-s012/bin/iscape.sh  -batch optionsFile=$(pwd)/xcelium_ctl.txt
```
### Change to a smaller VM configuration

We'll run the Xcelium jobs on a smaller VM, _Standard_F2s_v2_ instead
of _Standard_F32s_v2_. So make sure to add the smaller VM to the list
of VM sizes in the UI and update _cyclecloudprov_templates.json_.


### Update cluster for Xcelium requirements

The Xcelium binaries are installed on NFS but the run time requires OS packages to be installed.
Let's add these packages to the user_data.sh script to prepare the hosts as they come up.

We'll add the following line to user_data.sh and upload the script to the storage account.

```bash
yum install -y redhat-lsb.i686 glibc-devel.i686
```

We're also going to pull down the simulation projects as part of the job script. We'll
need `azcopy` to be available on all the hosts, so let's add it to the user home directory.

```bash
wget https://aka.ms/downloadazcopy-v10-linux
tar -xf downloadazcopy-v10-linux
mkdir ~/bin
mv azcopy_linux_*/azcopy ~/bin
```


### Prepare job script



```bash
#!/bin/bash
set -x
export LM_LICENSE_FILE=5280@$LICENSE_SERVER

EXP=`uuidgen`
mkdir ~/$EXP
cd ~/$EXP

# Copy the project
BLOB=cyclecloud/test_case.tar.gz
~/bin/azcopy cp "https://$STORAGE_ACCOUNT.blob.core.windows.net/$BLOB$SAS_TOKEN" ./
tar -xf test_case.tar.gz

# Run the test
pushd uvm_test_long/lab03_test/sv
sed -i 's/100000/1000000/' yapp_tx_seqs.sv
popd
cd uvm_test_long/lab03_test/tb
time /stor/apps/cadence/tools.lnx86/bin/xrun -f lab03run.f
```

