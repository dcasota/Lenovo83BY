# Lenovo83BY - Initial ESXi setup

1. Download bits

   - ESXi
   - NVidia ESXi 8.x Bits from https://nvid.nvidia.com/dashboard/#/dashboard, see https://ui.licensing.nvidia.com/software > Software Downloads. Download e.g. NVIDIA-GRID-vSphere-8.0-525.147.01-525.147.05-529.19.zip


2. Attach peripherical devices 

   - usb type-c network adapter
   - usb type-a device with installed ESXi
   - usb type-a device with existing vmfs datastore
   
3. VMware Workstation

   In VMware Workstation, configure temporarily an ESXi VM and install ESXi on a physically attached usb drive.

4. Initial boot from usb drive

   Press Shift-O and add the following parameters on cmdline:  
   `cpuUniformityHardCheckPanic=FALSE ignoreMsrFaults=TRUE tscSyncSkip=TRUE timerforceTSC=TRUE` 
   
   In DCUI, system customization, configure management network, network adapters, make sure vusb0 is selected.
   With a dhcp server in the lan, it should get now an ip address.
   
   Start TSM-SSH in ESXi web client. Start Putty and login to the ESXi host.

5. Initial datastore configuration

   Mount the existing vmfs datastore by disabling the device from passthrough device list.
      
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
   ```

   Check the storage devices.

   ```
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

   Put ESXi in maintenancemode.
   
   Unzip the NVIDIA-GRID-vSphere-8.0-525.147.01-525.147.05-529.19.zip.  
   Upload the host drivers NVD-VGPU-800_525.147.01-1OEM.800.1.0.20613240_22626827.zip and nvd-gpu-mgmt-daemon_525.147.01-0.0.0000_22624911.zip to the datastore.
   
   
   Run the following command.

   ```
   esxcli software vib install -d /vmfs/volumes/sandisk/nvd-gpu-mgmt-daemon_525.147.01-0.0.0000_22624911.zip
   Installation Result
      Message: The update completed successfully, but the system needs to be rebooted for the changes to be effective.
      VIBs Installed: NVD_bootbank_nvdgpumgmtdaemon_525.147.01-1OEM.700.1.0.15843807
      VIBs Removed:
      VIBs Skipped:
      Reboot Required: true
      DPU Results:
   ```

   Run the following command.

   ```
   esxcli software vib install -d /vmfs/volumes/sandisk/NVD-VGPU-800_525.147.01-1OEM.800.1.0.20613240_22626827.zip
   Installation Result
      Message: The update completed successfully, but the system needs to be rebooted for the changes to be effective.
      VIBs Installed:
      VIBs Removed:
      VIBs Skipped: NVD_bootbank_NVD-VMware_ESXi_8.0.0_Driver_525.147.01-1OEM.800.1.0.20613240
      Reboot Required: true
      DPU Results:
   ```

   Run the following code snippet to make the initial usb boot settings permanent.
   `sed -i 's/autoPartition.*/autoPartition=FALSE cpuUniformityHardCheckPanic=FALSE ignoreMsrFaults=TRUE tscSyncSkip=TRUE timerforceTSC=TRUE/g' /vmfs/volumes/BOOTBANK1/boot.cfg`

6. Next boot from usb drive

   In DCUI, system customization, configure management network, network adapters, make sure vusb0 is selected.
   Unfortunately, run `esxcli system module parameters set -p "usbnBusFullScanOBootEnabled=1" -m vmkusb` does make vusb0 permanent, and for secure boot I haven't found a solution yet.
   
7. Install VCSA


8. Install PowerCLI
   ```
   install-module -name VMware.PowerCLI
   set-PowerCLIConfiguration -InvalidCertificateAction:Ignore
   ```

9. Download and configure Automated Lab Deployment

   https://github.com/lamw/vsphere-with-tanzu-nsxt-automated-lab-deployment

144AN-LC10M-J82N5-0C0KP-8ME1H
