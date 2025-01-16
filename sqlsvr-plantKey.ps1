#Set permission for key to access the webserver(s) on which to setup the ssh tunnels
$mypath = "C:\"
$myfile = "co.txt" #already copied to here via ansible-playbook
$fullpath = $mypath + $myfile

# Reset to remove explict permissions
icacls.exe $fullpath /reset
# Give current user explicit read-permission
icacls.exe $fullpath /GRANT:R "$($env:USERNAME):(R)"
# Disable inheritance and remove inherited permissions
icacls.exe $fullpath /inheritance:r
write-host "====== Key fixed"