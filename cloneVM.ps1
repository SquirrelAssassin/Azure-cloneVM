##### Read Me #####
#
# - Tested as of 2/21/2017
# - Authored by William.Lee@SPR.com
#
# Basic Info
# - This script is written to clone everything that goes along with a vm to somewhere new
# - Resouces that require a unique name will have a random 3 char number added to the end of the name
# - Future releass will include a move feature
# - Right now a new public nic will be created
# - No Source content will be removed
# - All interfaces will be replicated
# - If you specifiy a storage account type this will be used for all storage accounts associated with the VM
# 
# Assumptions
# - All storage accounts go into the same Resource Group
# - Single Machines not in Availablity Sets
# 
#  .Parameter [String] $sourceVmName = Source VM Name
#
#  .Parameter [String] $destinationVmName = Destination VM Name
#
#  .Parameter [string] $destinationResourceGroup = If you want the Destination Name to be different from the destionationVmName
#
#  .Parameter [string] $subscriptionID = Subscription ID
#
#  .Parameter [string] $destinationResourceGroupLocation = Destination Location IE eastus,centralus
#
#  .Parameter [string] $destinationStorageType = Destination Storage Type IE Premium_LRS, Standard_GRS, Standard_LRS, Standard_RAGRS
#
#  .parameter [switch] $powerDownSource = If you want to power down the source VM
#
#  .parameter [switch] $newVmSize = If you want to pick some other size then what the source is
#
#  .Parameter [switch] $skipAuth = If you want to skip logging into azure rm because you already are logged in
#
#  Example : .\cloneVM.ps1 -sourceVmName desktop-123 -destinationVmName waka-44rfv -skipauth -powerdownsource -subscriptionID 0c644443-3333-4444-4444-3444de4444ef -destinationResourceGroupLocation eastus -destinationStorageType Standard_LRS
#
###################



   [CmdletBinding()]Param (
       [Parameter(Mandatory = $True)]
                  [String] $sourceVmName,

       [Parameter(Mandatory = $True)]
                  [String] $destinationVmName,

       [Parameter(Mandatory = $False)]
                  [string] $destinationResourceGroup,

       [Parameter(Mandatory = $False)]
                  [string] $subscriptionID,

       [Parameter(Mandatory = $False)]
                  [string] $destinationResourceGroupLocation,

       [Parameter(Mandatory = $False)]
                  [string] $destinationStorageType,

       [Parameter(Mandatory = $False)]
                  [switch]$powerDownSource,

       [Parameter(Mandatory = $False)]
                  [switch]$newVmSize,

       [Parameter(Mandatory = $False)]
                  [switch]$skipAuth

   )
do {
if ($destinationVmName.Length -gt 15) {
    Write-host "The destination VM name has be be 15 charecters or less"; $destinationVmName = Read-Host "Please enter a new name Under 15 charecters"}
}
until ($destinationVmName.Length -le 15)

# If you testing and already authed you can skip it
if ($skipauth -ne $true) {
Login-AzureRmAccount
}

# Select the subscription
if (!$subscriptionID) {
    $sub = Set-AzureRmContext -SubscriptionId (Get-AzureRmSubscription | Out-GridView -Title "Pick A Subscription" -PassThru).subscriptionid
    $subscription = $sub.Subscription.SubscriptionId 
    }
    Else {
        $subscription = $subscriptionID
    }

# Destination VM Size
if ($newVmSize -eq $true) {
    $vmSize = (Get-AzureRoleSize | where SupportedByVirtualMachines -eq $true | select InstanceSize | Out-GridView -PassThru).instancesize
    }
    Else {$vmSize = (Get-AzureRmVM -wa Ignore -InformationAction Ignore | where {$_.name -eq $sourceVmName}).HardwareProfile.VmSize
    }
        


#
# Destionation Resource Group
if (!$destinationResourceGroup) {
    $destinationResourceGroup = $destinationVmName.ToLower()
    }

# Gather Source Info
$sourceResourceGroup = (Get-AzureRmVM -ea SilentlyContinue -wa Ignore -InformationAction Ignore | where {$_.name -eq $sourceVmName}).ResourceGroupName
$sourcevhdOSName = (Get-AzureRmVM -InformationAction Ignore -wa Ignore | where {$_.name -eq $sourceVmName} -ea SilentlyContinue -wa Ignore -InformationAction Ignore).StorageProfile.OsDisk
$sourceDataDisks = (Get-AzureRmVM -name $sourceVmName -ResourceGroupName $sourceResourceGroup -ea SilentlyContinue -wa Ignore -InformationAction Ignore).StorageProfile.DataDisks.vhd.uri
$sourceDataDisksProperties = (Get-AzureRmVM -name $sourceVmName -ResourceGroupName $sourceResourceGroup -ea SilentlyContinue -wa Ignore -InformationAction Ignore).StorageProfile.DataDisks
$sourceOSDisks = (Get-AzureRmVM -name $sourceVmName -ResourceGroupName $sourceResourceGroup -ea SilentlyContinue -wa Ignore -InformationAction Ignore).StorageProfile.OSDisk.vhd.uri

# Deallocat Old VM
if ($powerdownsource -eq $true) {
    if ($(Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -Status -wa Ignore -InformationAction Ignore | select -ExpandProperty Statuses | ?{ $_.Code -match "PowerState" } | select `
    -ExpandProperty DisplayStatus) -ne 'vm deallocated'){
        $continue = 'yes'
        }}
    Else {
        if ($(Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -Status -wa Ignore -InformationAction Ignore | select -ExpandProperty Statuses | ?{ $_.Code -match "PowerState" } | select `
            -ExpandProperty DisplayStatus) -ne 'vm deallocated'){
            write-host "In order to copy the VM $sourceVmName it must be Deallocated, Enter yes to Deallocate the $sourceVmName or enter no to exit"
            $continue = $($yn = 'yes','no' ; $yn | Out-GridView -PassThru -Title "Shutdown VM $sourceVmName ????")
            }
        }

if ($continue -eq "yes") {
    Write-host "Please wait while the VM is deallocated"; Stop-AzureRmVM -Name $sourceVmName -ResourceGroupName $sourceResourceGroup -force -wa Ignore -InformationAction Ignore
    }
    elseif ($continue -eq "no") {exit}


# Create Destination Resource Group
$dstResourceGroup = Get-AzureRmResourceGroup -Name $destinationResourceGroup -ea SilentlyContinue
if(!$dstResourceGroup){
  if (!$destinationResourceGroupLocation) {
    Write-Host "Resource group '$destinationResourceGroup' does not exist. To create a new resource group, please enter a location.";
    $resourceGroupLocation = ((Get-AzureRmLocation | select location) | Out-GridView -Title "Pick The Destination Location" -PassThru).location
    }
    else {
        $resourceGroupLocation = $destinationResourceGroupLocation
        }
    Write-Host "Creating resource group '$destinationResourceGroup' in location '$resourceGroupLocation'";
    New-AzureRmResourceGroup -Name $destinationResourceGroup -Location $resourceGroupLocation -wa SilentlyContinue -InformationAction Ignore
    }
    Else{
        Write-Host "Using existing resource group $destinationResourceGroup"
        }


# Create Storage Account if it doesnt exist
$randomNumber = 1..9
# You can change randomNumber to whatever value you want to add to the end of all resources
$randomNumber = (-join (Get-Random $randomNumber -count 3))
$saArray = @(); $upArray = @()
foreach ($sa in ($sourceDataDisks + $sourceOSDisks)) {$saArray +=@(($sa.split('//')[2]).split('.')[0])}
$saArray = $saArray | select -Unique
$saArray | % {$upArray +=, @($_,($_ + $randomNumber ))}
foreach ($Storage in $upArray) {
$storageAct = $storage[1]
if (!(Get-AzureRmStorageAccount -ResourceGroupName $destinationResourceGroup -Name $storageAct.ToLower() -ea SilentlyContinue -wa Ignore -InformationAction Ignore)) {
    do {
    if ((Get-AzureRmStorageAccountNameAvailability -Name $storageAct.ToLower() -wa Ignore -InformationAction Ignore).NameAvailable -eq $True) {
        if (!$destinationStorageType) {
            write-host "Pick The Storage Type For $storageAct"
            $storageType = $($sTypes = 'Standard_LRS','Premium_LRS', 'Standard_GRS', 'Standard_RAGRS'; $sTypes | Out-GridView -Title "Pick The Storage Type For $storageAct" -PassThru)
            }
        else {$storageType = $destinationStorageType}
            $strQuit = 'Yes'; New-AzureRmStorageAccount -ResourceGroupName $destinationResourceGroup -Name $storageAct.ToLower() -Location $resourceGroupLocation -SkuName $storageType -wa SilentlyContinue -InformationAction Ignore
            } 
    else {
      write-host "That name is already taken please try running the script again"
      exit
      }
    }
    until ($strQuit -eq 'Yes')  
  }
}


# Create Container if it doesnt exist
foreach ($vhdFolder in ($sourceDataDisks + $sourceOSDisks)) {
    $vhdContainer = $vhdFolder.split('//')[3]
    $vhdContainerSa = ($VhdFolder.split('//')[2]).split('.')[0]
    $azureRmStorageAccount = (Get-AzureRmStorageAccount -ResourceGroupName $destinationResourceGroup -Name $($vhdContainerSa + $randomNumber) -wa Ignore -InformationAction Ignore | Get-AzureStorageContainer -ea SilentlyContinue -wa Ignore -InformationAction Ignore)
    if (($azureRmStorageAccount | where {$_.name -eq $vhdContainer}).count -eq 1) {} 
        else {
            Get-AzureRmStorageAccount -resourcegroup $destinationResourceGroup -name $($vhdContainerSa + $randomNumber) -wa Ignore -InformationAction Ignore | New-AzureStorageContainer -Name $vhdContainer -wa SilentlyContinue -InformationAction Ignore
            }
    }

# COPY BLOBS
$diskArray = @()
# Loop Through Disks 
foreach ($disk in ($sourceDataDisks + $sourceOSDisks)) {
    # Strip apart the blob URL
    $storageAccount = ($disk.split('//')[2]).split('.')[0];
    $containerName = $disk.split('//')[3];
    $vhdName = $disk.split('//')[4]
    # Get Keys and Contect
    $srcKey = ((Get-AzureRmStorageAccountKey -ResourceGroupName $((Get-AzureRmStorageAccount | ? {$_.StorageAccountName -eq $storageAccount}).ResourceGroupName) -Name $storageAccount -wa SilentlyContinue).Value)[0]
    $srcContext = New-AzureStorageContext -StorageAccountName $storageAccount -StorageAccountKey $srckey -wa SilentlyContinue
    $destKey = ((Get-AzureRmStorageAccountKey -ResourceGroupName $destinationResourceGroup -Name $($storageAccount + $randomNumber) -wa SilentlyContinue).Value)[0]
    $destContext = New-AzureStorageContext -StorageAccountName $($storageAccount + $randomNumber) -StorageAccountKey $destKey -wa SilentlyContinue
    $vhds = Get-AzureStorageBlob -Container $containerName -Context $srcContext -wa SilentlyContinue| ? {$_.name -like "$($vhdName)"}
    # Start the Copy
    $copy = Start-AzureStorageBlobCopy -DestContainer $containerName -DestContext $destContext -SrcBlob $vhdName -DestBlob $vhdName -Context $srcContext -SrcContainer $containerName -Force -wa SilentlyContinue -InformationAction Ignore
    $diskArray +=,@($destContext, $vhdname, $containerName)
    }

# Create a Network Subnet
# make subnet
$subIntId = (Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -ea SilentlyContinue -wa ignore).NetworkProfile.NetworkInterfaces
$subIntId | % {
    $subNicInfo1 = (Get-AzureRmNetworkInterface -ResourceGroupName $sourceResourceGroup -Name $($_.id.Split("/")| select -Last 1) -ea SilentlyContinue -wa ignore)
    $subVnetName1 = (($subnicinfo1.IpConfigurations.subnet.id).Split("/") | select -Last 3)[0]
    $subNicInfo = (Get-AzureRmNetworkInterface -ResourceGroupName $sourceResourceGroup -Name $($_.id.Split("/")| select -Last 1) -ea SilentlyContinue -wa ignore)
    $subSubNetId = $subnicinfo.IpConfigurations.subnet.id
    $subSubNetConfig = (Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork (Get-AzureRmVirtualNetwork -ResourceGroupName $sourceResourceGroup -name $subVnetName1))
    $subSubNetConfigFinal = New-AzureRmVirtualNetworkSubnetConfig -Name $subSubNetConfig.name -AddressPrefix $subSubNetConfig.AddressPrefix
    }

# Create a Network
$netIntId = (Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -ea SilentlyContinue -wa SilentlyContinue).NetworkProfile.NetworkInterfaces
$netIntId | % {
    $netNicInfo = (Get-AzureRmNetworkInterface -ResourceGroupName $sourceResourceGroup -Name $($_.id.Split("/")| select -Last 1) -ea SilentlyContinue -wa SilentlyContinue)
    $netVnetName = (($netnicinfo.IpConfigurations.subnet.id).Split("/") | select -Last 3)[0]
    $netAddressPrefix = $((Get-AzureRmVirtualNetwork -ResourceGroupName $sourceResourceGroup -Name $netVnetName -wa SilentlyContinue).Subnets.addressprefix)
    $netVnetFinal = New-AzureRmVirtualNetwork -ResourceGroupName $destinationResourceGroup -Name $netVnetName -Location $resourceGroupLocation -Subnet $subSubNetConfigFinal -AddressPrefix $netAddressPrefix -wa SilentlyContinue -InformationAction Ignore
    }

# Create NSG 
$intId = (Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -ea SilentlyContinue -wa SilentlyContinue).NetworkProfile.NetworkInterfaces
$intId | % {
    $nicInfo = (Get-AzureRmNetworkInterface -ResourceGroupName $sourceResourceGroup -Name $($_.id.Split("/") | select -Last 1) -ea SilentlyContinue -wa SilentlyContinue)
    $nsgId = $nicInfo.NetworkSecurityGroup.Id
    $nsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $sourceresourcegroup -Name $($nsgId.split("/") | select -last 1) -ea SilentlyContinue -wa SilentlyContinue
    $newNsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $destinationResourceGroup -Name $nsg.Name -SecurityRules $nsg.SecurityRules -location $resourceGroupLocation -ea SilentlyContinue -wa SilentlyContinue -InformationAction Ignore
    }

# Creates vmconfig and sets size
$VirtualMachine = New-AzureRmVMConfig -VMName $destinationVmName -VMSize $VMSize

# Create a public ip and Network Interface and Attaches the Public IP
$pubIp = (Get-AzureRmVM -ResourceGroupName $sourceResourceGroup -Name $sourceVmName -ea SilentlyContinue -wa Ignore -InformationAction Ignore).NetworkProfile.NetworkInterfaces
$pubIp | % {
    $pubName = $($destinationVmName + $randomNumber)
    $pip=New-AzureRmPublicIpAddress -Name $pubName -ResourceGroupName $destinationResourceGroup -Location $resourceGroupLocation -AllocationMethod Dynamic -wa Ignore -InformationAction Ignore
    $NIC=New-AzureRmNetworkInterface -Name $pubName -ResourceGroupName $destinationResourceGroup -Location $resourceGroupLocation -NetworkSecurityGroupId $newNsg.Id `
    -SubnetId $netvnetfinal.Subnets.id -PublicIpAddressId $pip.Id -wa Ignore -InformationAction Ignore
    $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id -InformationAction Ignore -wa Ignore
    }

# Add OS Disk to VM
$VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $destinationVmName -VhdUri $($sourceOSDisks.replace($($sourceOSDisks.split("/").split(".")[2]), $($sourceOSDisks.split("/").split(".")[2] + $randomNumber))) -Caching "ReadWrite" -CreateOption Attach -Windows

# Add Data Disk to VM
$sourceDataDisksProperties | % {
    $virtualMachineVhdUri = $($_.vhd.uri.replace($(($_.Vhd.Uri.split("/").split(".")[2])), $(($_.Vhd.Uri.split("/").split(".")[2]) + $randomNumber)))
    $VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name $_.name -VhdUri $virtualMachineVhdUri -CreateOption Attach -Lun $_.Lun -DiskSizeInGB $_.DiskSizeGB
    }

# Wait For Drives to Finish Copying
$diskArray | % {
    Write-Host "Please wait for drives to finish copying."
    Get-AzureStorageBlobCopyState -Context $_.context -Blob $_[1] -Container $_[2] -wa SilentlyContinue -InformationAction Ignore -WaitForComplete
    }

#Create VM
New-AzureRmVM -ResourceGroupName $destinationResourceGroup -Location $resourceGroupLocation -VM $VirtualMachine