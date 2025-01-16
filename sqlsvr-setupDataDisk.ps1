#Setup and E disk for MSSQL data - Nutanix Database Service (aka Era) insists on a non C drive for this
#Get-Disk | Where-Object IsOffline –Eq $True | Set-Disk –IsOffline $False
Get-Disk
Initialize-Disk 1 –PartitionStyle MBR
New-Partition –DiskNumber 1 -UseMaximumSize -DriveLetter "E"
Format-Volume -DriveLetter "E" -FileSystem NTFS -NewFileSystemLabel DBData -Confirm:$false