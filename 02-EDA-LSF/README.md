# Managing an EDA environment using CycleCloud

This project demonstrates configuration for LSF cluster
leveraging Azure NetAPP files for storage and CycleCloud
for automation.

This project assumes several prerequisites are setup, configured and running.

Pre-requisites
* LSF Installer and License Files
* Virtual Network
* Azure NetAPP Files Volume
* CycleCloud

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
from the project fileserver to an Azure NetAPP filesystem.
In this lab we'll use two methods to accomplish the same thing.

On the execute nodes we'll update _/etc/fstab_ to have this mount: 

```/etc/fstab
10.0.16.4:/main /stor nfs rw,hard,tcp,vers=3,rsize=65536,wsize=65536 0 0
```

On the master nodes we'll update the cluster template to have an [NFS mount](https://docs.microsoft.com/azure/cyclecloud/how-to/mount-fileserver):
```ini
   [[[configuration cyclecloud.mounts.anf]]]
      type = nfs
      address = 10.0.16.4
      mountpoint = /stor
      export_path = /main
```

Both methods are equivalent. The LSF template also has a hard reference to the shared filesystem host.
We'll want to move the NFS filesystem mount away from _$LSF_TOP_ and to an alternate place on the filesystem.
Where we see _sched-exp_ we'll change _$LSF_TOP_ to _/backup_. So _$LSF_TOP_ is now backed by the NetAPP filesystem and no longer the in-project filesystem.

```diff
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
will already exist with boilerplate. Update the templates to use new *vmSize*; *Standard_F32s_v2* for the *ondemand* nodes and *Standard_Hc44rs* for the *ondemandmpi*
templates. **For LSF to properly autoscale, you must update the ncpus/ncores/mem values according to the new vmSize**, e.g. ncores=ncpus=44 for *Standard_Hc44rs*. 

We'll be adding a new custom script in the next section. Add a reference to it in this file by
setting _customScriptUri_ to _file:///stor/lsf/conf/resource_connector/cyclecloud/conf/user_data.sh_. This will use the user_data.sh script on the shared file system as a boot-up script.

#### _user_data.sh_

This file has a single essential goal; to properly start the LSF daemons. There are
several configurations that we will add to support proper daemon configuration. 
The CycleCloud [LSF project example](https://github.com/Azure/cyclecloud-lsf/blob/master/examples/user_data.sh) is a good starting point. Once the updates are complete, this script 
will serve to:

* mount the in-project (for _/shared/home_) and ANF (for _/stor_) filesystem
* add the lsfadmin user
* make a local copy of _lsf.conf_ and populate [_LSF_LOCAL_RESOURCES_](https://www.ibm.com/support/knowledgecenter/SSETD4_9.1.2/lsf_config_ref/lsf.conf.lsf_local_resources.5.html) for heterogeneous clusters
* set _LSF_ENVDIR_ and start the daemons 

### Submit test jobs

The LSF RC configuration is complete and the LSF master node is ready to dynamically autoscale the LSF cluster. Submit a job to the default queue and observe that a node is added.

```bash 
bsub /bin/sleep 60
```


