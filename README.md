# Lenovo83BY

1. Download bits


2. Attach peripherical devices 

   usb network adapter
   usb device 1
   usb device datastore
   
3. VMware Workstation

In VMware Workstation, configure temporarily an ESXi VM to install ESXi on a phyiscally attached usb drive.

4. Initial boot from usb drive

cpuUniformityHardCheckPanic=FALSE ignoreMsrFaults=TRUE tscSyncSkip=TRUE timerforceTSC=TRUE   

6. Initial datastore configuration


```
[root@localhost:~] esxcli hardware usb passthrough device list
Bus  Dev  VendorId  ProductId  Enabled  Can Connect to VM          Name
---  ---  --------  ---------  -------  -------------------------  ----
1    3    bda       8153         false  no (passthrough disabled)  Realtek Semiconductor Corp. RTL8153 Gigabit Ethernet Adapter
2    2    4f2       b7c1          true  yes                        Chicony Electronics Co., Ltd
2    3    8087      33            true  yes                        Intel Corp.
2    6    781       55ab          true  yes                        SanDisk Corp.
2    4    90c       2000         false  no (passthrough disabled)  Silicon Motion, Inc. - Taiwan (formerly
                                                                   Feiya Technology Corp.)
[root@localhost:~] esxcli hardware usb passthrough device disable -d 2:6:781:55ab
[root@localhost:~] esxcli hardware usb passthrough device disable -d 2:6:781:55ab
[root@localhost:~] vdq -q
[
   {
      "Name"     : "t10.NVMe____SKHynix_HFS001TEJ9XXXXX_________________C20C523500xxxxx",
      "VSANUUID" : "",
      "State"    : "Ineligible for use by VSAN",
      "Reason"   : "Has partitions",
"StoragePoolState": "Ineligible for use by Storage Pool",
"StoragePoolReason": "Has partitions",
      "IsSSD"    : "1",
"IsCapacityFlash": "0",
      "IsPDL"    : "0",
      "Size(MB)" : "976762",
    "FormatType" : "512e",
   "IsVsanDirectDisk" : "0"
   },

   {
      "Name"     : "mpx.vmhba32:C0:T0:L0",
      "VSANUUID" : "",
      "State"    : "Ineligible for use by VSAN",
      "Reason"   : "Has partitions",
"StoragePoolState": "Ineligible for use by Storage Pool",
"StoragePoolReason": "Has partitions",
      "IsSSD"    : "0",
"IsCapacityFlash": "0",
      "IsPDL"    : "0",
      "Size(MB)" : "60000",
    "FormatType" : "512n",
   "IsVsanDirectDisk" : "0"
   },

   {
      "Name"     : "mpx.vmhba34:C0:T0:L0",
      "VSANUUID" : "",
      "State"    : "Ineligible for use by VSAN",
      "Reason"   : "Has partitions",
"StoragePoolState": "Ineligible for use by Storage Pool",
"StoragePoolReason": "Has partitions",
      "IsSSD"    : "0",
"IsCapacityFlash": "0",
      "IsPDL"    : "0",
      "Size(MB)" : "942480",
    "FormatType" : "512n",
   "IsVsanDirectDisk" : "0"
   }

]
[root@localhost:~] 
```

```
esxcli software vib install -d /vmfs/volume
s/sandisk/nvd-gpu-mgmt-daemon_525.147.01-0.0.0000_22624911.zip
Installation Result
   Message: The update completed successfully, but the system needs to be rebooted for the changes to be effective.
   VIBs Installed: NVD_bootbank_nvdgpumgmtdaemon_525.147.01-1OEM.700.1.0.15843807
   VIBs Removed:
   VIBs Skipped:
   Reboot Required: true
   DPU Results:
[root@localhost:/vmfs/volumes/60ace419-78bc052c-deca-dca632c8a3b6]
```
