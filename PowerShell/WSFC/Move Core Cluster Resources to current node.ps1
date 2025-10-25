$group = 'Cluster Group'

$OwnerNode = (Get-ClusterGroup $group).OwnerNode.Name

$env:COMPUTERNAME
$OwnerNode


if ($env:COMPUTERNAME -ne $OwnerNode) {
    Write-Host "The owner node of the FCI cluster: '$(($group -split '[()]')[1])' is not the correct first node!!! Failing over!!!" -ForegroundColor Red
    Move-ClusterGroup -Name $group -Node $env:COMPUTERNAME
}
else {
    Write-Host "The FCI cluster: '$(($group -split '[()]')[1])' already has its first node as the owner" -ForegroundColor Green
}

