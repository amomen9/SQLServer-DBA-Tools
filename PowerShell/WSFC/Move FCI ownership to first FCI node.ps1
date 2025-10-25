# This script assumes that the FCI nodes contain "FC" in their host name.
# Replace "FC" with any script of your convention
# Purpose: Move the FCI ownership to the first FCI node.


$group = 'SQL Server (*)'
$group = (Get-ClusterGroup $group).Name



$OwnerNode = (Get-ClusterGroup $group).OwnerNode
$NonOwnerFirstAlphabetical = (Get-ClusterGroup $group | Get-ClusterOwnerNode).OwnerNodes.Name | Where-Object { $_ -match "FC" } |
    Where-Object { $_ -ne $OwnerNode } |
    Sort-Object |
    Select-Object -First 1

$FirstAlphabetical = (Get-ClusterGroup $group | Get-ClusterOwnerNode).OwnerNodes.Name | Sort-Object | Where-Object { $_ -match "FC" } |
    Select-Object -First 1



$NonOwnerFirstAlphabetical
$FirstAlphabetical


if ($NonOwnerFirstAlphabetical -eq $FirstAlphabetical) {
    Write-Host "The owner node of the FCI cluster: '$(($group -split '[()]')[1])' is not the correct first node!!! Failing over!!!" -ForegroundColor Red
    Move-ClusterGroup -Name $group -Node $NonOwnerFirstAlphabetical
}
else {
    Write-Host "The FCI cluster: '$(($group -split '[()]')[1])' already has its first node as the owner" -ForegroundColor Green
}
