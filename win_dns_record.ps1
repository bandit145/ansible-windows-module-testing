#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2
#sort params
$params = Parse-Args -Arguments $args -supports_check_mode $false
$domain = Get-AnsibleParam -Obj $params -Name "domain" -Type "str" -FailIfEmpty $true
$record_type = Get-AnsibleParam -Obj $params -Name "record_type" -Type "str" -FailIfEmpty $true
$record_name = Get-AnsibleParam -Obj $params -Name "record_name" -Type "str" -FailIfEmpty $true
$record_data = Get-AnsibleParam -Obj $params -Name  "record_data" -Type "dict" -FailIfEmpty $true
$ttl = Get-AnsibleParam -Obj $params -Name "ttl" -Type "dict" -FailIfEmpty $false
$state = Get-AnsibleParam -Obj $params -Name "state" -Type "str" -Default "present" -ValidateSet @("present","absent")
$result = @{
    changed = $false
}

try {
    Import-Module -Name DnsServer
}
catch {
    Fail-Json -Obj $result -Message "Host missing DNS PowerShell module"
}

function Diff-DNSRecord{
    if((Compare-Object -DifferenceObject $record_new -ReferenceObject $record_old -Property HostName,TimeToLive,RecordData) -ne $null){
        return $true
    }
    return $false
}

function Get-TimeSpan{
    switch($ttl["time_type"]){
        "seconds" {return [System.TimeSpan]::FromSeconds($ttl["span"])}
        "minutes" {return [System.TimeSpan]::FromMinutes($ttl["span"])}
        "hours" {return [System.TimeSpan]::FromHours($ttl["span"])}
        "days" {return [System.TimeSpan]::FromDays($ttl["span"])}
        default {Fail-Json -Obj $result -Message "ttl time_type not valid"}
    }
}

function Build-NewObject{
    switch($record_old){
        {$_.RecordData.($record_data["key"]) -ne $record_data["key"]}{$record_new.RecordData.($record_data["key"]) = $record_data["value"]}
        {$_.TimeToLive -ne $record_name -and $ttl -ne $null}{return $record_new.TimeToLive = Get-TimeSpan}
        
    }
}

#check for existance of record
#note: this become an issue with muliple A records
function Ensure-DNSRecord{
    #Search for matching record
    $record_old = $false
    foreach($record in (Get-DNSServerResourceRecord -ZoneName $domain -RRType $record_type)){
        #if found assign and break
        if ($record.RecordData.($record_data["key"]) -eq $record_data["value"] -and $record.HostName -eq $record_name){
            $record_old = $record
            break
        }
    }
    #Check if record exists if wanted absent then remove
    if ($record_old){
        if ($state -eq "absent"){
            Remove-DNSServerResourceRecord -InputObject $record_old -ZoneName $domain -Force
            $result["changed"] = $true
        }
        #else check if object needs to be changed
        else{
            $record_new = $record_old.Clone()
            Build-NewObject
            if(Diff-DNSRecord){
                Set-DNSServerResourceRecord -NewInputObject $record_new -OldInputObject $record_old -ZoneName $domain
                $result["changed"] = $true
            }
        }
    }
    #if it doesn't exist and needs to be present create object
    elseif($state -eq "present"){
        #use splatting for building one with and withou TimeToLive
        $resource_args = @{
            Name=$record_name;
            ZoneName=$domain
        }
        $resource_args.Add($record_type,$true)
        $resource_args.Add($record_data["key"],$record_data["value"])
        if($ttl){
            $resource_args.Add("TimeToLive",(Get-TimeSpan))
        }
        Add-DNSServerResourceRecord @resource_args
        $result["changed"] = $true
    }
}

Ensure-DNSRecord
Exit-Json -Obj $result