## Setup reverse ssh tunnel on webserver(s)
#So the webservers access the SQL Server Dtatase Server via 127.0.0.1:8888 (from their
#point of view) this port id forwarded to port 1433 on the dtabase server.  No VPN to AWS necessary!
#hardev@nutanix.com Aug'22

$fullpath = "C:\co.txt"
$webs = "C:\webs.txt"
$tunnel_log = "C:\setuptunnel.txt"
$webservers = Get-Content -Path $webs #File with two webserver public IPs
Write-Host "webservers: " $webserver
New-Item -Path $tunnel_log -ItemType File
$webserverarr = $webservers -split ","
foreach ($singlewebserver in $webserverarr)
{
  write-host "Webserver is: $singlewebserver, about to setup tunnel"
  Add-Content -Path 'C:\debug.txt' -Value "Webserver is: $singlewebserver, about to setup tunnel"
  write-host "Executing as a scheduled task in about 3 minutes:  ssh -vvv -o StrictHostKeyChecking=no -i $fullpath -R 8888:127.0.0.1:1433 -N webadmin@$singlewebserver"
  $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-Command & {ssh -vvv -o StrictHostKeyChecking=no -i $fullpath -R 8888:127.0.0.1:1433 -N webadmin@$singlewebserver; sleep 14400}"
  #2. Create trigger - run in 1 minute
  $timespan = New-TimeSpan -Days 0 -Hours 0 -Minutes 1
  $when = (Get-Date) + $timespan
  $tasktrigger = New-ScheduledTaskTrigger -Once -At $when
  Register-ScheduledTask -TaskName "STunnel-$singlewebserver" -Action $taskAction -Trigger $tasktrigger -Description "Start Tunnel on webserver $singlewebserver"
}
write-host "====Done" 