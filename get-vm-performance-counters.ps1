# define where we will save our performance metrics.
$outputFile = "C:\Users\chris\Desktop\perfdumps\vCenterMetrics.csv"
 
# define a new Powershell credential and log into vCenter with the credentials
$creds = Get-Credential
$vCenter = Connect-VIServer vc6b.vmware.local -Credential $creds -SaveCredentials
 
# define our vCenter service instance and performance manager.
# https://www.vmware.com/support/developer/converter-sdk/conv43_apireference/vim.ServiceInstance.html
$serviceInstance = Get-View ServiceInstance -Server $vCenter
$perfMgr = Get-View $serviceInstance.Content.PerfManager -Server $vCenter
 
# get all available performance counters
$counters = $perfMgr.PerfCounter
 
# create an array where we will store each of our custom objects that will contain the information that we want.
$metrics = @()
 
foreach ($counter in $counters) {
# create a custom Powershell object and define attributes such as the performance metric's name, rollup type, stat level, summary, etc
$metric = New-Object System.Object
$metric | Add-Member -type NoteProperty -name GroupKey   -value $counter.GroupInfo.Key
$metric | Add-Member -type NoteProperty -name NameKey    -value $counter.NameInfo.Key
$metric | Add-Member -type NoteProperty -name Rolluptype -value $counter.RollupType
$metric | Add-Member -type NoteProperty -name Level      -value $counter.Level
$metric | Add-Member -type NoteProperty -name FullName   -value "$($counter.GroupInfo.Key).$($counter.NameInfo.Key).$($counter.RollupType)"
$metric | Add-Member -type NoteProperty -name Summary    -value $counter.NameInfo.Summary
 
# add the custom object to our array
$metrics += $metric
}
 
# each metric object will look simliar to the following.  We can use a select command to gather which attributes we want and export them to a CSV file.
#   GroupKey   : vsanDomObj
#   NameKey    : writeAvgLatency
#   Rolluptype : average
#   Level      : 4
#   FullName   : vsanDomObj.writeAvgLatency.average
#   Summary    : Average write latency in ms
 
$metrics | select fullname, level, summary | Export-Csv -NoTypeInformation $outputFile
