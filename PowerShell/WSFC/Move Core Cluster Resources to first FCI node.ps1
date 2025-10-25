# This script assumes that the FCI nodes contain "FC" in their host name.
# Replace "FC" with any script of your convention
# Purpose: Move the core cluster resources to the first FCI node.



$group = 'Cluster Group'



$OwnerNode = (Get-ClusterGroup $group).OwnerNode.Name
$NonOwnerFirstAlphabetical =  (Get-ClusterNode).Name | Where-Object { $_ -match "FC" } |
    Where-Object { $_ -ne $OwnerNode } |
    Sort-Object |
    Select-Object -First 1

$FirstAlphabetical = (Get-ClusterNode).Name | Where-Object { $_ -match "FC" } | Sort-Object |
    Select-Object -First 1



$NonOwnerFirstAlphabetical
$FirstAlphabetical


if ($NonOwnerFirstAlphabetical -en $FirstAlphabetical) {
    Write-Host "The owner node of the FCI cluster: '$(($group -split '[()]')[1])' is not the correct first node!!! Failing over!!!" -ForegroundColor Red
    Move-ClusterGroup -Name $group -Node $NonOwnerFirstAlphabetical
}
else {
    Write-Host "The FCI cluster: '$(($group -split '[()]')[1])' already has its first node as the owner" -ForegroundColor Green
}






