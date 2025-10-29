$group = 'Cluster Group'

$OwnerNode = (Get-ClusterGroup $group).OwnerNode.Name

$env:COMPUTERNAME
$OwnerNode



# Define log file
$logDir   = 'C:\Source'
$logFile  = Join-Path $logDir 'Cluster_Owner.log'   

if ($env:COMPUTERNAME -ne $OwnerNode) {

    # Calculate Timestamp with format
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'

    # Original warning message
    $warnMsg = "[$timestamp] The owner node of the FCI cluster is '$ownerNode' which is not the correct first node. Initiating failover to $env:COMPUTERNAME ..."
    Write-Host $warnMsg -ForegroundColor Red
    Add-Content -Path $logFile -Value $warnMsg

    # Attempt to move the cluster group
    try {
        Move-ClusterGroup -Name $group -Node $env:COMPUTERNAME -ErrorAction Stop
        # Recalculate Timestamp with format
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'

        $successMsg = "[$timestamp] The ownership of the core cluster resources has been transferred to $env:COMPUTERNAME."
        Write-Host $successMsg -ForegroundColor Green
        Add-Content -Path $logFile -Value $successMsg
    }
    catch {
        $failMsg = "[$timestamp] Error!!! Moving cluster core resources to node $env:COMPUTERNAME has failed. Details: $($_.Exception.Message)"
        Write-Host $failMsg -ForegroundColor Yellow
        Add-Content -Path $logFile -Value $failMsg
    }
}

else {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $OK_Info_msg = "[$timestamp] It is OK! The FCI cluster has this node ($($env:COMPUTERNAME)) as its owner"
    Write-Host $OK_Info_msg -ForegroundColor Green
    Add-Content -Path $logFile -Value $OK_Info_msg
}

