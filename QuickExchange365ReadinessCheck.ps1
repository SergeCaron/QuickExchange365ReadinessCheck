
<#PSScriptInfo

.VERSION 1.0

.GUID b9efde78-8f87-4b05-9b16-fdcec5884415

.AUTHOR scaron@pcevolution.com

.COMPANYNAME PC-Évolution enr.

.COPYRIGHT Copyright (c) 2023-2024 PC-Évolution enr. This code is licensed under the GNU General Public License (GPL).

.TAGS Exchange365 Office365 migration

.LICENSEURI https://www.gnu.org/licenses/gpl-3.0.en.html

.PROJECTURI https://github.com/SergeCaron/QuickExchange365ReadinessCheck

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES ExchangeOnlineManagement and Microsoft.Graph.Identity.SignIns modules

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 Aid in migrating to Exchange 365 

#> 
param(
	[Parameter()]
	[String]$ExternalDNS = "dns.google"
)

# Ensure a minimum version of .Net is installed
# Note: this test is based on https://funwithiagengineering.blogspot.com/2023/06/issue-migrating-to-exchangeonlinemanage.html
#		where the author notes an incompatibility between .Net 4.6 and the ExchangeOnlineManagement module.
#		.Net 4.8 can be installed on Windows Server 2016/2019 by using the "Offline installer"
#		https://support.microsoft.com/en-us/topic/microsoft-net-framework-4-8-offline-installer-for-windows-9d23f658-3b97-68ab-d013-aa3c3e7495e0
#		However, on Windows server 2016, it seems to break (at least) Server Manager and I don't want to go down this rabbit hole...
#		I did not test .Net 4.7.2 on up-to-date Windows Server 2019.

If ((Get-ItemPropertyValue -LiteralPath 'HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release) -lt 528040) {
	Write-Warning ".Net 4.8 or later is required by the ExchangeOnlineManagement module v3.4 or later"
	Write-Warning "Note: installing .Net 4.8 on a Windows Server 2016 Domain Controller will break things ..."
	Exit 911
}

# Ensure a minimum security protocol will be used to connect to the PowerShell libraries
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host "Please wait..."

# Install required modules to get the tenant's security defaults
If ($Null -eq $(Get-InstalledModule -Name Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue)) {
	$UserExecutionPolicy = $(Get-ExecutionPolicy -Scope CurrentUser)
	Try {
		Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
		Write-Host
		Write-Host "Installing Microsoft Graph modules..."
		Install-Module -Name Microsoft.Graph.Identity.SignIns -Scope CurrentUser -ErrorAction Stop
	}
	Catch {
		Write-Warning "Security Defaults status is not available if module Microsoft.Graph.Identity.SignIns is not installed."
	}
	Finally {
		Set-ExecutionPolicy -ExecutionPolicy $UserExecutionPolicy -Scope CurrentUser
	}
}

# Load the modules if they are available
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue

# Display security defaults
If ($Null -ne $(Get-Module -Name Microsoft.Graph.Identity.SignIns)) {
	Try {
		Write-Host
		Connect-MgGraph -NoWelcome -Scopes Policy.ReadWrite.ConditionalAccess, Policy.Read.All -ErrorAction Stop
		Write-Host "Enforcement policy status:"
		Write-Host "--------------------------"
		(Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy | Format-List Description, DisplayName, IsEnabled | Out-String).Trim()
	}
	Catch {
		Write-Warning "Unable to login to tenant."
		exit 911
	}
}

# Current PowerShell Exchange Management Module
If ($Null -eq $(Get-InstalledModule -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
	$UserExecutionPolicy = $(Get-ExecutionPolicy -Scope CurrentUser)
	Try {
		Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
		Write-Host
		Write-Host "Installing ExchangeOnlineManagement module ..."
		Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -ErrorAction Stop
	}
	Catch {
		Write-Warning "Exchange 365 parameters are not available if module ExchangeOnlineManagement is not installed."
		Exit 911
	}
	Finally {
		Set-ExecutionPolicy -ExecutionPolicy $UserExecutionPolicy -Scope CurrentUser
	}
}

# Load Exchange Online Management module (Abort on error!)
Import-Module ExchangeOnlineManagement -ErrorAction Stop

$moduleVersion = (Get-Module -Name ExchangeOnlineManagement -ListAvailable).Version -join "."
Write-Host "Using Exchange Online Management module version: $moduleVersion"

# Login management console
Connect-ExchangeOnline

# Dump SMTP client email submissions permissions
Write-Host "Authenticated client SMTP submission (SMTP AUTH) Status:"
Write-Host "--------------------------------------------------------"
Write-Host
Write-Host "Organization-wide:"
(Get-TransportConfig | Format-List SmtpClientAuthenticationDisabled | Out-String).Trim()
Write-Host
Write-Host "Per-mailbox setting overrides:"
(Get-CASMailbox | Format-Table DisplayName, SmtpClientAuthenticationDisabled | Out-String).Trim()
Write-Host

# Gestion de DKIM
#	-> (Accueil) Centre d'administration -- Sécurité
#		-> Email et collaboration -- Stratégies et règles
#			-> Stratégies de menace
#				-> Paramètres d'authentification des e-mails
#					-> DomainKeys Identified Mail (DKIM)

Write-Host "DKIM Status:"
Write-Host "------------"
Write-Host
(Get-DkimSigningConfig | Format-Table Domain, Enabled, Status, Selector*KeySize | Out-String).Trim()
Write-Host

# Select an external recursive DNS server
Try {
	$RecursiveDNS = (Get-DnsServerForwarder -ErrorAction Stop).IPAddress.IPAddressToString
}
Catch {
	$RecursiveDNS = $ExternalDNS
}
Write-Host "Name resolution using external DNS server(s): $RecursiveDNS."
Write-Host "------------------------------------------------------------"

Get-DkimSigningConfig | ForEach-Object {
	$Domain = $_.Name
	$DecoratedDomain = $Domain.Replace(".", "-")
	$MSRoot = $_.OrganizationalUnitRoot

	$ExternalDNS = (Resolve-DnsName -Name $Domain -Type SOA -Server $RecursiveDNS).PrimaryServer
	$DomainMX = (Resolve-DnsName -Name $Domain -Type MX -Server $ExternalDNS).NameExchange
	Write-Host "             Domain name: $Domain"
	Write-Host "Authoritative DNS server: $ExternalDNS"
	Write-Host "            Mail servers: $DomainMX"
	Write-Host 

	Try {
		$ActualValue = $(Resolve-DnsName -Name "autodiscover.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction Stop).NameHost
		If ($ActualValue -eq "autodiscover.outlook.com") {
			Write-Host "                Verified: autodiscover.$Domain"
		}
		else {
			Write-Warning "autodiscover.$Domain [$ActualValue] does not match the expected value: autodiscover.outlook.com"
		}
	}
	Catch {
		Write-Warning "autodiscover.$Domain is undefined in public DNS"
	}

	Try {
		$ActualValue = $(Resolve-DnsName -Name "lyncdiscover.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction Stop).NameHost
		If ($ActualValue -eq "webdir.online.lync.com") {
			Write-Host "                Verified: lyncdiscover.$Domain"
		}
		else {
			Write-Warning "lyncdiscover.$Domain [$ActualValue] does not match the expected value: webdir.online.lync.com"
		}
	}
	Catch {
		Write-Warning "lyncdiscover.$Domain is undefined in public DNS"
	}

	Try {
		$ActualValue = $(Resolve-DnsName -Name "sip.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction Stop).NameHost
		If ($ActualValue -eq "sipdir.online.lync.com") {
			Write-Host "                Verified: sip.$Domain"
		}
		else {
			Write-Warning "sip.$Domain [$ActualValue] does not match the expected value: sipdir.online.lync.com"
		}
	}
	Catch {
		Write-Warning "sip.$Domain is undefined in public DNS"
	}

	Try {
		$ActualValue = $(Resolve-DnsName -Name "_sip._tls.$Domain" -Type SRV -Server $ExternalDNS -ErrorAction Stop).NameTarget
		If ($ActualValue -eq "sipdir.online.lync.com") {
			Write-Host "                Verified: _sip._tls.$Domain"
		}
		else {
			Write-Warning "_sip._tls.$Domain [$ActualValue] does not match the expected value: sipdir.online.lync.com"
		}
	}
	Catch {
		Write-Warning "_sip._tls.$Domain is undefined in public DNS"
	}

	Try {
		$ActualValue = $(Resolve-DnsName -Name "_sipfederationtls._tcp.$Domain" -Type SRV -Server $ExternalDNS -ErrorAction Stop).NameTarget
		If ($ActualValue -eq "sipfed.online.lync.com") {
			Write-Host "                Verified: _sipfederationtls._tcp.$Domain"
		}
		else {
			Write-Warning "_sipfederationtls._tcp.$Domain [$ActualValue] does not match the expected value: sipfed.online.lync.com"
		}
	}
	Catch {
		Write-Warning "_sipfederationtls._tcp.$Domain is undefined in public DNS"
	}

	ForEach ($n in 1, 2) {
		$ExpectedValue = "selector$n" + "-$DecoratedDomain._domainkey.$MSRoot"
		$Selector = "selector$n._domainkey.$Domain"
		Try {
			If ($(Resolve-DnsName -Name $Selector -Type CNAME -Server $ExternalDNS -ErrorAction Stop).NameHost -eq $ExpectedValue) {
				Write-Host "                Verified: $Selector"
			}
			else {
				Write-Warning "Selector does not match the expected value: $ExpectedValue."
			}
		}
		Catch {
			Write-Warning "$Selector is undefined in public DNS. Expected value: [$ExpectedValue]."
		}
	}
	Write-Host ""
	
}

# Logout Exchange
Disconnect-ExchangeOnline -Confirm:$false

# Logout Microsoft Graph
Write-Host "Disconnected from: ", (Disconnect-MgGraph -ErrorAction SilentlyContinue).AppName


