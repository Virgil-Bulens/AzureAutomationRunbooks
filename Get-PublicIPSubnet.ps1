#
# Variables
#
$ErrorActionPreference = "Stop"
$Domain = "o-o.myaddr.l.google.com"
$Uri = "https://dns.google.com/resolve?name=" + `
    $Domain + `
    "&type=txt"


#
# Main
#
$Response = Invoke-RestMethod -Uri $URI
($Response.Answer.data)[-1].Split(" ")[-1]