$jobFunctions = {
	function publishResults {
	  <#
	  .SYNOPSIS
	  .DESCRIPTION
	  .EXAMPLE
	  .EXAMPLE
	  #>

	  param(
	    [Parameter(Mandatory=$true)] 
	    [string] $inFile
	  )
	  
	  # Most of what is in this function probably won't be too useful to anyone.  You'd probably need to re-write it.  
	  
	  $method = 'POST'
	  $uri = [System.Uri] "http://2.2.3.1:6543/api/v1/data_sets?gridname=vm&clustername=vcenter"
	  $outputFile = 'C:\Users\chris\Documents\powercli\stats\publish-result.txt'
	 
	  $request = Invoke-RestMethod -uri $uri -method $method -InFile $inFile
	  
	  if ($request.'Job Status' -eq 'Success') {
	    add-content $outputFile "Successfully published results for $inFile"
	  }
	  else {
	    add-content $outputFile "Failed to published results for $inFile"
	  }
	}
}

$scriptBlock = {
  param($vmName, $vc, $statTypes, $outputDirectory)
  
  # Even though I pass in the vCenter connection, I have to re-establish it.  I'd like to know of a way to prevent this.  
  $vc = Connect-VIServer $vc.name -Session $vc.sessionId
  
  # Even if I pass in the VM object (and not just the name as is currently being done), I still have to retrieve the VM again.  I'd like to know of a way to prevent this.  
  try {
    $vm = Get-VM $vmName -server $vc
  }
  catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem   = $_.Exception.ItemName
    add-content "$($outputDirectory)\log.txt" "$errormessage, $faileditem"
  }
  
  $filteredStatTypes = @()
  
  # Get all of the stat types for the time interval (realtime) specified.  
  # When querying for realtime stats, if no results are returned, this most likely means the VM has been powered off for an hour, 
  # the host the VM is on wasn't sending data to vCenter, the host the VM is on was disconnected, etc.  
  $availableStatTypes = get-stattype -entity $vm -realtime -Server $vc | sort

  # There is no point continuing if there is no data for the VM so return to the calling context.
  if ($availableStatTypes -eq $null) { return }

  # We need to place all the stats we want to query into $filteredStatTypes.  If the user doesn't specify any stat types ($statTypes),
  # then we just assign all available stats ($availableStatTypes) into $filteredStatTypes.  
  # If the user does specify stat types, we iterate through each one and make sure it's available in $availableStatTypes and add it 
  # to $filteredStatTypes.
  if ($statTypes -eq $null) { 
    $filteredStatTypes = $availableStatTypes	
  }
  else { 
    foreach ($statType in $statTypes) {
	  if ($statType -in $availableStatTypes) {
	    $filteredStatTypes += $statType
      }
	}		
  }
    
  if ($filteredStatTypes -eq $null) { return }
  
  # Collection info to be used in building the report.
  $vmName       = $vm.name
  $persistentId = $vm.PersistentId
  $vmPowerState = $vm.powerstate
  $cluster      = ($vm | get-cluster).name
  $outputFile = $outputDirectory + $persistentId + '.txt'

  # If the output file already exists, go ahead and delete it.  
  # if (Test-Path $outputFile) { Add-Content "$($outputDirectory)\dups.txt" "$($vm.name)" ; Remove-Item $outputFile }
  if (Test-Path $outputFile) { Remove-Item $outputFile }

  # During testing you may want limit the number of results you get back. Uncomment the following line and select the first X amount of stat types to limit the the results.
  #$statTypes = $statTypes | select -first 5

  $finish = Get-Date
  
  # Since realtime stats only go back an hour before they are rolled up, we only need to get an hours worth of data.
  $start = $finish.AddHours(-1)
  $stats = Get-Stat -entity $vm -server $vc -realtime -stat $filteredStatTypes -start $start -finish $finish | ? { $_.instance -eq "" }
	  
  foreach ($stat in $stats) {
    $temp = @()
    # Build up a temp array that will contain each of the items to be used to build up a line in the report.
    $temp += $vmName, $persistentId, $vmPowerState, $cluster, $stat.MetricId, $stat.Timestamp, $stat.Value, $stat.Unit
    # Combine each of the items in the temp array to create a line of comma separated values.
    $content = '"' + $($temp -join '","') + '"'
	# Store each line into our output file.   
    Add-Content $outputFile $content
	}
	
  try {
    #publishResults $outputFile
  }
  catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem   = $_.Exception.ItemName
    add-content "$($outputDirectory)\log.txt" "$errormessage, $faileditem, $vmName, $persistentId"
  }
  
  # Disconnect this (and only this) instance of vCenter so we don't leave unused sessions lying around.
  Disconnect-VIServer $vc -Confirm $false
}

# Record the time the script started.
$start = Get-Date

$vCenterName = 'vc5c.vmware.local'

$vcConnection = Connect-VIServer $vCenterName

# This is where we will store the CSV files with the performance data. 
$outputDirectory = 'C:\Users\chris\Desktop\perfdumps\'

# Max amount of jobs (processes) we want running at any time.  You may need to tweak this depending on the resources of your machine.
$maxJobCount = 4

# sleep time in seconds between checking to see if it's okay to run another job.
$sleepTimer = 3

# Here we can define an array of the counters we want to retrieve.  If you have a large list of counters, it may be easier to store them in an external file. For example:
#$statTypes = @('mem.active.average', 'mem.granted.average')
# If you don't define this array, all performance counters will be pulled. 

# Retrieve the VMs we want to retrieve stats from.  
# When you're testing you may want to only grab a subset of all VMs.  Here are a few examples
# get all VMs in the vCenter(s) you're conneted to: $vms = get-vm
# get all VMs in a specific cluster:                $vms = get-cluster 'resource cluster' | get-vm
# get the first 10 VMs that are powered on:         $vms = get-vm | ? { $_.powerstate -eq 'PoweredOn' } | select -First 10

$vms = get-vm | ? { $_.powerstate -eq 'PoweredOn' } | select -First 10

# Create our job queue.
$jobQueue = New-Object System.Collections.ArrayList

# Main loop of the script.  
# Loop through each VM and start a new job if we have less than $maxJobCount outstanding jobs.  
# If the $maxJobCount has been reached, sleep 3 seconds and check again.  
foreach ($vm in $vms) {
  # Wait until job queue has a slot available.
  while ($jobQueue.count -ge $maxJobCount) {
    echo "jobQueue count is $($jobQueue.count): Waiting for jobs to finish before adding more."
    foreach ($jobObject in $jobQueue.toArray()) {
	    if ($jobObject.job.state -eq 'Completed') { 
	      echo "jobQueue count is $($jobQueue.count): Removing job: $($jobObject.vm.name)"
	      $jobQueue.remove($jobObject) 		
	    }
	  }
	sleep $sleepTimer
  }  
  
  echo "jobQueue count is $($jobQueue.count): Adding new job: $($vm.name)"
  $job = Start-Job -name $vm.name -InitializationScript $jobFunctions -ScriptBlock $scriptBlock -ArgumentList $vm.name, $vcConnection, $statTypes, $outputDirectory
  $jobObject     = "" | select vm, job
  $jobObject.vm  = $vm
  $jobObject.job = $job
  $jobQueue.add($jobObject) | Out-Null
}

Get-Job | Wait-Job | Out-Null

#$regex = '([a-zA-Z0-9]+-){4}[a-zA-Z0-9]+.txt'
#gci $outputDirectory | ? { $_.name -match $regex } | % { 
#  publishResults "$($outputDirectory)\$($_.name)"
  #sleep 3
#}

# Record the time the script started.
$end = Get-Date

echo "Start: $($start), End: $($end)"
