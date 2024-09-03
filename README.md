# Quick Exchange 365 Readiness Check

This script is strictly a diagnostic tool used to verify the public DNS parameters required to support Exchange 365 email flow for a tenant.

It relies on the ExchangeOnlineManagement Get-DkimSigningConfig cmdlet to view the DomainKeys Identified Mail (DKIM) signing policy settings for domains in a cloud-based organization.

For each domain, it relies on a recursive EXTERNAL DNS server to display/verify :
- the authoritative DNS server(s) for the domain
- the Mail server(s) (MX) in use
- each of the following CNAMES against their respective expected value:
- - autodiscover.(domain)
- - lyncdiscover.(domain)
-- sip.(domain)
- - _sip._tls.(domain)
- - _sipfederationtls._tcp.(domain)
- - selector1._domainkey.(domain)
- - selector2._domainkey.(domain)

The script also displays the status of the "Security defaults" policy and the Authenticated client SMTP submission (SMTP AUTH) Status, both globally and for each mailbox.

This is typically usefull when migrating On Premises Exchange to Exchange 365.

### Usage:

Run this script with administrator privileges.

.Net 4.8 or later is required by the ExchangeOnlineManagement module v3.4 or later

Note: the Microsoft.Graph.Identity.SignIns and ExchangeOnlineManagement modules are required and will be installed in the current user context if not available.

Standard Microsoft 365 SignIn procedures are not documented here.

If a Microsoft DNS server is running on the same host, the script will use the DNS forwarders as external servers.

If not, the -ExternalDNS parameter can be used to specify any EXTERNAL recursive DNS server. The default is "dns.google", whatever it resolves to in your environment.

On exit, the script disconnects from the Microsoft 365 applications.

Sample output:

````
Please wait...

Enforcement policy status:
--------------------------
Description : Security defaults is a set of basic identity security mechanisms recommended by Microsoft. When enabled,
              these recommendations will be automatically enforced in your organization. Administrators and users will
              be better protected from common identity related attacks.
DisplayName : Security Defaults
IsEnabled   : True
Using Exchange Online Management module version: 3.5.1

----------------------------------------------------------------------------------------
This V3 EXO PowerShell module contains new REST API backed Exchange Online cmdlets which doesn't require WinRM for Client-Server communication. You can now run these cmdlets after turning off WinRM Basic Auth in your client machine thus making it more secure.

Unlike the EXO* prefixed cmdlets, the cmdlets in this module support full functional parity with the RPS (V1) cmdlets.

V3 cmdlets in the downloaded module are resilient to transient failures, handling retries and throttling errors inherently.

REST backed EOP and SCC cmdlets are also available in the V3 module. Similar to EXO, the cmdlets can be run without WinRM basic auth enabled.

For more information check https://aka.ms/exov3-module
----------------------------------------------------------------------------------------

Authenticated client SMTP submission (SMTP AUTH) Status:
--------------------------------------------------------

Organization-wide:
SmtpClientAuthenticationDisabled : False

Per-mailbox setting overrides:
DisplayName              SmtpClientAuthenticationDisabled
-----------              --------------------------------
Discovery Search Mailbox
First User
[...]
Last User
Administrator            False

DKIM Status:
------------

Domain                       Enabled Status Selector1KeySize Selector2KeySize
------                       ------- ------ ---------------- ----------------
yourdomain0.onmicrosoft.com    True Valid              1024             1024
yourdomain.com                 True Valid              2048             2048
yourdomain.ca                  True Valid              2048             2048

Name resolution using external DNS server(s): dns.google.
------------------------------------------------------------
             Domain name: yourdomain0.onmicrosoft.com
Authoritative DNS server: ns1-208.azure-dns.com
            Mail servers: yourdomain0.mail.protection.outlook.com

                Verified: autodiscover.yourdomain0.onmicrosoft.com
                Verified: lyncdiscover.yourdomain0.onmicrosoft.com
WARNING:: sip.yourdomain0.onmicrosoft.com is undefined in public DNS
WARNING:: _sip._tls.yourdomain0.onmicrosoft.com is undefined in public DNS
                Verified: _sipfederationtls._tcp.yourdomain0.onmicrosoft.com
WARNING:: selector1._domainkey.yourdomain0.onmicrosoft.com is undefined in public DNS. Expected value:
[selector1-yourdomain0-onmicrosoft-com._domainkey.yourdomain0.onmicrosoft.com].
WARNING:: selector2._domainkey.yourdomain0.onmicrosoft.com is undefined in public DNS. Expected value:
[selector2-yourdomain0-onmicrosoft-com._domainkey.yourdomain0.onmicrosoft.com].

             Domain name: yourdomain.com
Authoritative DNS server: somednsserver.com
            Mail servers: yourdomain-com.mail.protection.outlook.com

                Verified: autodiscover.yourdomain.com
                Verified: lyncdiscover.yourdomain.com
                Verified: sip.yourdomain.com
                Verified: _sip._tls.yourdomain.com
                Verified: _sipfederationtls._tcp.yourdomain.com
                Verified: selector1._domainkey.yourdomain.com
                Verified: selector2._domainkey.yourdomain.com

             Domain name: yourdomain.ca
Authoritative DNS server: somednsserver.com
            Mail servers: yourdomain-ca.mail.protection.outlook.com

                Verified: autodiscover.yourdomain.ca
                Verified: lyncdiscover.yourdomain.ca
                Verified: sip.yourdomain.ca
WARNING:: _sip._tls.yourdomain.ca is undefined in public DNS
WARNING:: _sipfederationtls._tcp.yourdomain.ca is undefined in public DNS
                Verified: selector1._domainkey.yourdomain.ca
                Verified: selector2._domainkey.yourdomain.ca

Disconnected from:  Microsoft Graph Command Line Tools

````

