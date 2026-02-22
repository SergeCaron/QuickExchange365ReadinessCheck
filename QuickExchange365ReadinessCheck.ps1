
<#PSScriptInfo

.VERSION 1.5

.GUID b9efde78-8f87-4b05-9b16-fdcec5884415

.AUTHOR scaron@pcevolution.com

.COMPANYNAME PC-Évolution enr.

.COPYRIGHT Copyright (c) 2023-2026 PC-Évolution enr. This code is licensed under the GNU General Public License (GPL).

.TAGS Exchange365 Office365 migration

.LICENSEURI https://www.gnu.org/licenses/gpl-3.0.en.html

.PROJECTURI https://github.com/SergeCaron/QuickExchange365ReadinessCheck

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES ExchangeOnlineManagement, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Users, and Microsoft.Graph.Reports modules

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 Aid in migrating to Exchange 365
 Aid in managing Office 365

#> 
param(
	[Parameter()]
	[String]$ExternalDNS = "dns.google",
	[String]$RequiredMGVersion = "2.30.0",
	[String]$RequiredEXOVersion = "3.8.0",
	[string[]]$Scopes = @(
		'Policy.Read.All',
		'Policy.Read.ConditionalAccess',
		'Policy.Read.AuthenticationMethod',
		'IdentityProvider.Read.All',
		'Directory.Read.All'
	)

)

# Log a transcript of this session
$DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
Start-Transcript -Path "$DesktopPath\QuickExchange365ReadinessCheck.txt" -Append

Write-Host
Write-Host "Quick Microsoft 365 / Exchange 365 tenant audit (Version 1.5)" -ForegroundColor Cyan
Write-Host "Portions (C) theitbros.com (https://theitbros.com/)"  -ForegroundColor Cyan
Write-Host "Portions (C) ALI TAJRAN (https:/www.alitajran.com/export-onedrive-usage-report)"  -ForegroundColor Cyan



# Section separator
$Separator = $("=" * 60)

# Ensure a minimum version of .Net is installed
# Note: this test is based on https://funwithiagengineering.blogspot.com/2023/06/issue-migrating-to-exchangeonlinemanage.html
#		where the author notes an incompatibility between .Net 4.6 and the ExchangeOnlineManagement module.
#		.Net 4.8 can be installed on Windows Server 2016/2019 by using the "Offline installer"
#		https://support.microsoft.com/en-us/topic/microsoft-net-framework-4-8-offline-installer-for-windows-9d23f658-3b97-68ab-d013-aa3c3e7495e0
#		However, on Windows server 2016, it seems to break (at least) Server Manager and I don't want to go down this rabbit hole...
#		I did not test .Net 4.7.2 on up-to-date Windows Server 2019.

if ((Get-ItemPropertyValue -LiteralPath 'HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release) -lt 528040) {
	Write-Warning ".Net 4.8 or later is required by the ExchangeOnlineManagement module v3.4 or later"
	Write-Warning "Note: installing .Net 4.8 on a Windows Server 2016 Domain Controller will break things ..."
	exit 911
}

# Ensure a minimum security protocol will be used to connect to the PowerShell libraries
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

### Install and load required Microsoft 365 modules
Write-Host
Write-Host "Please wait..."

# Install required modules to get the tenant's security defaults
$MgModules = @()

$MgModules += @{
	Name          = "Microsoft.Graph.Identity.SignIns"
	Warning       = "Security Defaults status is not available if module Microsoft.Graph.Identity.SignIns is not installed."
	VersionHeader = "Microsoft Graph Identity SignIns available versions:"
}

$MgModules += @{
	Name          = "Microsoft.Graph.Users"
	Warning       = "Properties and relationships of user object are not available if module Microsoft.Graph.Users is not installed."
	VersionHeader = "Microsoft Graph Users available versions:"
}

$MgModules += @{
	Name          = "Microsoft.Graph.Reports"
	Warning       = "Reports are not available if module Microsoft.Graph.Reports is not installed."
	VersionHeader = "Microsoft Graph Reports available versions:"
}

for ($module = 0; $module -lt $MgModules.Count; $module++) {

	if ($Null -eq $(Get-InstalledModule -Name $MgModules[$module].Name -RequiredVersion $RequiredMGVersion -ErrorAction SilentlyContinue)) {
		$UserExecutionPolicy = $(Get-ExecutionPolicy -Scope CurrentUser)
		try {
			Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
			Write-Host
			Write-Host "Installing Microsoft Graph modules..."
			Install-Module -Name $MgModules[$module].Name -RequiredVersion $RequiredMGVersion -Scope CurrentUser -ErrorAction Stop
		}
		catch {
			Write-Warning MgModules[$module].Warning
		}
		finally {
			Set-ExecutionPolicy -ExecutionPolicy $UserExecutionPolicy -Scope CurrentUser
		}
	}

	# Load the modules if they are available
	Import-Module $MgModules[$module].Name -RequiredVersion $RequiredMGVersion -ErrorAction SilentlyContinue
	$Versions = (Get-Module -Name $MgModules[$module].Name -ListAvailable).Version
	Write-Host $MgModules[$module].VersionHeader, $Versions

}

# Current PowerShell Exchange Management Module
if ($Null -eq $(Get-InstalledModule -Name ExchangeOnlineManagement -RequiredVersion $RequiredMGVersion -ErrorAction SilentlyContinue)) {
	$UserExecutionPolicy = $(Get-ExecutionPolicy -Scope CurrentUser)
	try {
		Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
		Write-Host
		Write-Host "Installing ExchangeOnlineManagement module ..."
		Install-Module -Name ExchangeOnlineManagement -RequiredVersion $RequiredEXOVersion -Scope CurrentUser -ErrorAction Stop
	}
	catch {
		Write-Warning "Exchange 365 parameters are not available if module ExchangeOnlineManagement is not installed."
		exit 911
	}
	finally {
		Set-ExecutionPolicy -ExecutionPolicy $UserExecutionPolicy -Scope CurrentUser
	}
}

# Load Exchange Online Management module (Abort on error!)
Import-Module ExchangeOnlineManagement -RequiredVersion $RequiredEXOVersion -ErrorAction SilentlyContinue
$Versions = (Get-Module -Name ExchangeOnlineManagement -ListAvailable).Version
Write-Host "Exchange Online Management module available versions:", $Versions

### Connect to Microsoft 365 tenant

# Display tenant security defaults
if ($Null -ne $(Get-Module -Name Microsoft.Graph.Identity.SignIns)) {
	try {
		Write-Host
		# Refer to https://graphpermissions.merill.net/permission/ for details
		Connect-MgGraph -NoWelcome -Scopes $Scopes -ErrorAction Stop
		Write-Host "Enforcement policy status:"
		Write-Host "--------------------------"
		(Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy | Format-List Description, DisplayName, IsEnabled | Out-String).Trim()
		Write-Host
	}
	catch {
		Write-Warning "Unable to login to tenant."
		exit 911
	}
}

# Display Microsoft Graph scopes: some cmdlet are finicky ;-)
Write-Host "Current Microsoft Graph scopes:" -ForegroundColor Cyan
Write-Host $separator -ForegroundColor Cyan
Write-Host
Write-Host "See https://learn.microsoft.com/en-us/graph/permissions-reference for details."
Write-Host
(Get-MgContext).Scopes

# Login management console
if ($Null -ne $(Get-Module -Name ExchangeOnlineManagement)) {
	try {
		# Dump SMTP client email submissions permissions
		Write-Host
		Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
		Write-Host "Authenticated client SMTP submission (SMTP AUTH) Status:" -ForegroundColor Cyan
		Write-Host $separator -ForegroundColor Cyan
		Write-Host
		Write-Host "Organization-wide:"
		(Get-TransportConfig | Format-List SmtpClientAuthenticationDisabled | Out-String).Trim()
		Write-Host
		Write-Host "Per-mailbox setting overrides:"
		(Get-CASMailbox | Format-Table DisplayName, SmtpClientAuthenticationDisabled | Out-String).Trim()
		Write-Host "--------------------------------------------------------"
	}
	catch {
		Write-Warning "Unable to login to Exchange Online."
		exit 911
	}
}

### Display DNS MX Setup

Write-Host
Write-Host "DNS and DKIM entries:" -ForegroundColor Cyan
Write-Host $Separator -ForegroundColor Cyan

# Gestion de DKIM
#	-> (Accueil) Centre d'administration -- Sécurité
#		-> Email et collaboration -- Stratégies et règles
#			-> Stratégies de menace
#				-> Paramètres d'authentification des e-mails
#					-> DomainKeys Identified Mail (DKIM)

Write-Host
Write-Host "DKIM Status:"
Write-Host "------------"
(Get-DkimSigningConfig | Format-Table Domain, Enabled, Status, Selector*KeySize | Out-String).Trim()
Write-Host

# Select an external recursive DNS server
try {
	$RecursiveDNS = (Get-DnsServerForwarder -ErrorAction Stop).IPAddress.IPAddressToString
}
catch {
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

	try {
		$ActualValue = $(Resolve-DnsName -Name "autodiscover.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction SilentlyContinue).NameHost
		if ($ActualValue -eq "autodiscover.outlook.com") {
			Write-Host "                Verified: autodiscover.$Domain"
		}
		elseif ($Null -eq $ActualValue) {
			Write-Warning "autodiscover.$Domain is undefined in public DNS"
		}
		else {
			Write-Warning "autodiscover.$Domain [$ActualValue] does not match the expected value: autodiscover.outlook.com"
		}

		$ActualValue = $(Resolve-DnsName -Name "lyncdiscover.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction SilentlyContinue).NameHost
		if ($ActualValue -eq "webdir.online.lync.com") {
			Write-Host "                Verified: lyncdiscover.$Domain"
		}
		elseif ($Null -eq $ActualValue) {
			Write-Warning "lyncdiscover.$Domain is undefined in public DNS"
		}
		else {
			Write-Warning "lyncdiscover.$Domain [$ActualValue] does not match the expected value: webdir.online.lync.com"
		}

		$ActualValue = $(Resolve-DnsName -Name "sip.$Domain" -Type CNAME -Server $ExternalDNS -ErrorAction SilentlyContinue).NameHost
		if ($ActualValue -eq "sipdir.online.lync.com") {
			Write-Host "                Verified: sip.$Domain"
		}
		elseif ($Null -eq $ActualValue) {
			Write-Warning "sip.$Domain is undefined in public DNS"
		}
		else {
			Write-Warning "sip.$Domain [$ActualValue] does not match the expected value: sipdir.online.lync.com"
		}

		$ActualValue = $(Resolve-DnsName -Name "_sip._tls.$Domain" -Type SRV -Server $ExternalDNS -ErrorAction SilentlyContinue).NameTarget
		if ($ActualValue -eq "sipdir.online.lync.com") {
			Write-Host "                Verified: _sip._tls.$Domain"
		}
		elseif ($Null -eq $ActualValue) {
			Write-Warning "_sip._tls.$Domain is undefined in public DNS"
		}
		else {
			Write-Warning "_sip._tls.$Domain [$ActualValue] does not match the expected value: sipdir.online.lync.com"
		}

		$ActualValue = $(Resolve-DnsName -Name "_sipfederationtls._tcp.$Domain" -Type SRV -Server $ExternalDNS -ErrorAction SilentlyContinue).NameTarget
		if ($ActualValue -eq "sipfed.online.lync.com") {
			Write-Host "                Verified: _sipfederationtls._tcp.$Domain"
		}
		elseif ($Null -eq $ActualValue) {
			Write-Warning "_sipfederationtls._tcp.$Domain is undefined in public DNS"
		}
		else {
			Write-Warning "_sipfederationtls._tcp.$Domain [$ActualValue] does not match the expected value: sipfed.online.lync.com"
		}

		foreach ($n in 1, 2) {
			$ExpectedValue = "selector$n" + "-$DecoratedDomain._domainkey.$MSRoot"
			$Selector = "selector$n._domainkey.$Domain"

			$ActualValue = $(Resolve-DnsName -Name $Selector -Type CNAME -Server $ExternalDNS -ErrorAction SilentlyContinue).NameHost
			if ($ActualValue -eq $ExpectedValue) {
				Write-Host "                Verified: $Selector"
			}
			elseif ($Null -eq $ActualValue) {
				Write-Warning "$Selector is undefined in public DNS. Expected value: [$ExpectedValue]."
			}
			else {
				Write-Warning "Selector does not match the expected value: $ExpectedValue."
			}
		}
	}
	catch {
		Write-Warning "Aborting name resolution of DNS entries for $Domain."
	}

	Write-Host ""
	
}

Write-Host $Separator -ForegroundColor Cyan

try {
	# Connect to Exchange Online
	# Connect-ExchangeOnline -ErrorAction Stop

	# Retrieve organization configuration, including data location
	$orgConfig = Get-OrganizationConfig

	# Display relevant location information
	Write-Host "Microsoft 365 Data Location and Forwarding Information:" -ForegroundColor Cyan
	Write-Host $Separator -ForegroundColor Cyan
	Write-Host "Organization Name: $($orgConfig.DisplayName)"
	Write-Host "Mailbox Data Encryption Enabled: $($orgConfig.MailboxDataEncryptionEnabled)"
	Write-Host "Default Data Encryption Policy: $($orgConfig.DefaultDataEncryptionPolicy)"
	Write-Host "Default Data Location:" $(Get-OrganizationConfig | Select-Object -ExpandProperty DefaultMailboxRegion).ToUpper()
	Write-Host "Allowed Data Location:" $(Get-OrganizationConfig | Select-Object -ExpandProperty AllowedMailboxRegions)[0]
	Write-Host
	Get-OrganizationalUnit | Select-Object OrganizationID
	
	Get-AcceptedDomain | Where-Object { $_.DomainType -eq 'Authoritative' } | `
			Select-Object Name, DomainName, DomainType, Default | Format-Table -AutoSize
		
	Get-Mailbox | Format-Table DisplayName, Database, ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward -AutoSize
	
	Write-Host "Explicit Microsoft 365 Policies" -ForegroundColor Cyan
	Write-Host $Separator -ForegroundColor Cyan

	Write-Host
	Write-Host "Explicit AntiPhish policies:"
	Get-AntiPhishPolicy | Where-Object { $_.IsDefault -eq $False } | Select-Object Name, Enable* | Format-List *

	Write-Host
	Write-Host "Explicit Unsollicited email filters:"
	Get-HostedContentFilterPolicy | Where-Object { $_.IsDefault -eq $False } | Select-Object Name, Enable* | Format-List *
	
	Write-Host
	Write-Host "Explicit Malware Filters:"
	Get-MalwareFilterPolicy | Where-Object { $_.IsDefault -eq $False } | Select-Object Name, Enable* | Format-List *

	Write-Host
	Write-Host "Explicit Safe Attachments protection for email messages filters:"
	Get-SafeAttachmentPolicy | Where-Object { $_.IsBuiltInProtection -eq $False } | Select-Object Name, Enable* | Format-List *

	Write-Host
	Write-Host "Explicit URL scanning and rewriting filters:"
	Get-SafeLinksPolicy | Where-Object { $_.IsBuiltInProtection -eq $False } | Select-Object Name, Enable* | Format-List *

	Write-Host "Licences and Multi-Factor Authentication" -ForegroundColor Cyan
	Write-Host $Separator -ForegroundColor Cyan

	# Dump MFA status for each user.
	# Copied (almost) verbatim from https://theitbros.com "Get MFA Status for Microsoft 365 Users with PowerShell"

	$ExchangeUsers = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited | Select-Object UserPrincipalName

	foreach ($AzureUserUPN in $ExchangeUsers) {
		$MFAUserData = Get-MgUserAuthenticationMethod -UserId $AzureUserUPN.UserPrincipalName

		$AzureUserObject = [PSCustomObject]@{
			"User"                       = 'n/a'
			"Licences"                   = "none"
			"MFA status"                 = "Disabled"
			"Email authentication"       = "False"
			"FIDO2 authentication"       = "False"
			"Microsoft Authenticator"    = "False"
			"Password authentication"    = "False"
			"Phone authentication"       = "False"
			"Software Oath"              = "False"
			"Temporary Access Pass"      = "False"
			"Windows Hello for Business" = "False"
			"Passwordless Authenticator" = "False"
		}

		$AzureUserObject.user = $AzureUserUPN.UserPrincipalName
		$AzureUserObject."Licences" = $(Get-MgUserLicenseDetail -UserId $AzureUserUPN.UserPrincipalName).SkuPartNumber


		foreach ($method in $MFAUserData) {

			switch ($method.AdditionalProperties["@odata.type"]) {

				"#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" {
					$AzureUserObject."Microsoft Authenticator" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.emailAuthenticationMethod" {
					$AzureUserObject."Email authentication" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.passwordAuthenticationMethod" {
					$AzureUserObject."Password authentication" = $true
					if ($AzureUserObject."MFA status" -ne "Enabled") {
						$AzureUserObject."MFA status" = "Disabled"
					}
				}

				"#microsoft.graph.fido2AuthenticationMethod" {
					$AzureUserObject."FIDO2 authentication" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.phoneAuthenticationMethod" {
					$AzureUserObject."Phone authentication" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.softwareOathAuthenticationMethod" {
					$AzureUserObject."Software Oath" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.temporaryAccessPassAuthenticationMethod" {
					$AzureUserObject."Temporary Access Pass" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}

				"#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" {
					$AzureUserObject."Windows Hello for Business" = $true
					$AzureUserObject."MFA status" = "Enabled"
				}
			}
		}    

		$AzureUserObject | Out-String
	}
}
catch {
	Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

### OneDrive / SharePoint storage usage report
#	Copied almost verbatim from https:/www.alitajran.com/export-onedrive-usage-report/


Write-Host "OneDrive usage:" -ForegroundColor Cyan
Write-Host $Separator -ForegroundColor Cyan

# Create unique file name
$tempFile = Join-Path $env:TEMP ("psout_{0}.txt" -f ([guid]::NewGuid()))

# Check if tenant reports have concealed user data, and adjust settings if necessary
if ((Get-MgAdminReportSetting).DisplayConcealedNames -eq $true) {
	$Parameters = @{ displayConcealedNames = $false }
	Write-Host "Unhiding concealed report data to retrieve full user information..." -ForegroundColor Cyan
	Update-MgAdminReportSetting -BodyParameter $Parameters
	$ConcealedFlag = $true
}
else {
	$ConcealedFlag = $false
	Write-Host "User data is already fully visible in the reports." -ForegroundColor Cyan
}

# Retrieve detailed user account information
Write-Host "Fetching user account details from Microsoft Graph..." -ForegroundColor Cyan

# Define user properties to be retrieved
$Properties = 'Id', 'displayName', 'userPrincipalName', 'city', 'country', 'department', 'jobTitle', 'officeLocation'

# Define parameters for retrieving users with assigned licenses
$userParams = @{
	All              = $true
	Filter           = "assignedLicenses/`$count ne 0 and userType eq 'Member'"
	ConsistencyLevel = 'Eventual'
	CountVariable    = 'UserCount'
	Sort             = 'displayName'
}

# Get user account information and select the desired properties
$Users = Get-MgUser @UserParams -Property $Properties | Select-Object -Property $Properties

# Create a hashtable to map UPNs (User Principal Names) to user details
$UserHash = @{}
foreach ($User in $Users) {
	$UserHash[$User.userPrincipalName] = $User
}

# Retrieve OneDrive for Business site usage details for the last 30 days and export to a temporary CSV file
Write-Host "Retrieving OneDrive for Business site usage details..." -ForegroundColor Cyan
Get-MgReportOneDriveUsageAccountDetail -Period D30 -Outfile $tempFile

# Import the data from the temporary CSV file
$ODFBSites = Import-Csv $tempFile | Sort-Object 'User display name'

if (-not $ODFBSites) {
	Write-Host "No OneDrive sites found." -ForegroundColor Yellow
}
else {
	# Calculate total storage used by all OneDrive for Business accounts
	$TotalODFBGBUsed = [Math]::Round(($ODFBSites.'Storage Used (Byte)' | Measure-Object -Sum).Sum / 1GB, 2)

	# Initialize a list to store report data
	$Report = [System.Collections.Generic.List[Object]]::new()

	# Populate the report with detailed information for each OneDrive site
	foreach ($Site in $ODFBSites) {
		$UserData = $UserHash[$Site.'Owner Principal name']
		$ReportLine = [PSCustomObject]@{
			Owner             = $Site.'Owner display name'
			UserPrincipalName = $Site.'Owner Principal name'
			SiteId            = $Site.'Site Id'
			IsDeleted         = $Site.'Is Deleted'
			LastActivityDate  = $Site.'Last Activity Date'
			FileCount         = [int]$Site.'File Count'
			ActiveFileCount   = [int]$Site.'Active File Count'
			QuotaGB           = [Math]::Round($Site.'Storage Allocated (Byte)' / 1GB, 2)
			UsedGB            = [Math]::Round($Site.'Storage Used (Byte)' / 1GB, 2)
			PercentUsed       = [Math]::Round($Site.'Storage Used (Byte)' / $Site.'Storage Allocated (Byte)' * 100, 2)
			City              = $UserData.city
			Country           = $UserData.country
			Department        = $UserData.department
			JobTitle          = $UserData.jobTitle
		}
		$Report.Add($ReportLine)
	}

	# Export the report to a CSV file and display the data in a grid view
	$Report | Format-Table UserPrincipalName, IsDeleted, LastActivityDate, ActiveFileCount, QuotaGB, UsedGB, PercentUsed -AutoSize

	Write-Host ("Current OneDrive for Business storage consumption is {0} GB." -f $TotalODFBGBUsed) -ForegroundColor Cyan
	Write-Host
}

# Clean up the temporary export file
if (Test-Path $tempFile) {
	Remove-Item $tempFile
	Write-Host "Temporary export file removed." -ForegroundColor Cyan
}

Write-Host "Retrieving SharePoint site usage details..." -ForegroundColor Cyan
Get-MgReportSharePointActivityUserDetail -Period D30 -OutFile $tempFile

# Import the data from the temporary CSV file
$SPOSites = Import-Csv $tempFile | Sort-Object 'User display name'

if (-not $SPOSites) {
	Write-Host "No Sharepoint sites found." -ForegroundColor Yellow
}
else {
	# Calculate total files used by all SharePoint for Business accounts
	$TotalSPOFilesUsed = [Math]::Round(($SPOSites.'Synced File Count' | Measure-Object -Sum).Sum)

	# Initialize a list to store report data
	$Report = [System.Collections.Generic.List[Object]]::new()

	# Populate the report with detailed information for each OneDrive site
	foreach ($User in $SPOSites) {
		$ReportLine = [PSCustomObject]@{
			#			Owner             = "(n/a)"
			UserPrincipalName = $User.'User Principal name'
			IsDeleted         = $User.'Is Deleted'
			LastActivityDate  = $User.'Last Activity Date'
			FileCount         = $User.'Synced File Count'
			Products          = $User.'Assigned Products'
		}
		$Report.Add($ReportLine)
	}

	# Export the report to a CSV file and display the data in a grid view
	$Report | Format-Table -AutoSize

	Write-Host ("Current SharePoint for Business file count is {0}." -f $TotalSPOFilesUsed) -ForegroundColor Cyan
	Write-Host
	
}

# Reset tenant report data concealment setting if it was modified earlier
if ($ConcealedFlag -eq $true) {
	Write-Host "Re-enabling data concealment in tenant reports..." -ForegroundColor Cyan
	$Parameters = @{ displayConcealedNames = $true }
	Update-MgAdminReportSetting -BodyParameter $Parameters
}

# Clean up the temporary export file
if (Test-Path $tempFile) {
	Remove-Item $tempFile
	Write-Host "Temporary export file removed." -ForegroundColor Cyan
}

# Logout Exchange
Write-Host
Disconnect-ExchangeOnline -Confirm:$false

# Logout Microsoft Graph
Write-Host "Disconnected from: ", (Disconnect-MgGraph -ErrorAction SilentlyContinue).AppName

# Close the log.
Stop-Transcript


