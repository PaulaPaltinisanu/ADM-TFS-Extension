#
# localTask.ps1
#
using namespace PSModule.UftMobile.SDK.UI
using namespace PSModule.UftMobile.SDK.Entity
using namespace System.Collections.Generic

param()
$testPathInput = Get-VstsInput -Name 'testPathInput' -Require
$timeOutIn = Get-VstsInput -Name 'timeOutIn'
$uploadArtifact = Get-VstsInput -Name 'uploadArtifact' -Require
$artifactType = Get-VstsInput -Name 'artifactType'
$rptFileName = Get-VstsInput -Name 'reportFileName'
[bool]$enableFailedTestsRpt = Get-VstsInput -Name 'enableFailedTestsReport' -AsBool

$envType = Get-VstsInput -Name 'envType'
$mcDevices = Get-VstsInput -Name 'mcDevices'

[bool]$useChrome = Get-VstsInput -Name 'chrome' -AsBool
[bool]$useChromeH = Get-VstsInput -Name 'chromeH' -AsBool
[bool]$useChromium = Get-VstsInput -Name 'chromium' -AsBool
[bool]$useEdge = Get-VstsInput -Name 'edge' -AsBool
[bool]$useFirefox = Get-VstsInput -Name 'firefox' -AsBool
[bool]$useFirefox64 = Get-VstsInput -Name 'firefox64' -AsBool
[bool]$useIExplorer = Get-VstsInput -Name 'iExplorer' -AsBool
[bool]$useIExplorer64 = Get-VstsInput -Name 'iExplorer64' -AsBool
[bool]$useSafari = Get-VstsInput -Name 'safari' -AsBool

$mcServerUrl = Get-VstsInput -Name 'mcServerUrl'
$mcUsername = Get-VstsInput -Name 'mcUsername'
$mcPassword = Get-VstsInput -Name 'mcPassword'
[int]$mcTenantId = Get-VstsInput -Name 'mcTenantId' -AsInt
[bool]$useMcProxy = Get-VstsInput -Name 'useMcProxy' -AsBool
$mcProxyUrl = Get-VstsInput -Name 'mcProxyUrl'
[bool]$useMcProxyCredentials = Get-VstsInput -Name 'useMcProxyCredentials' -AsBool
$mcProxyUsername = Get-VstsInput -Name 'mcProxyUsername'
$mcProxyPassword = Get-VstsInput -Name 'mcProxyPassword'

$uftworkdir = $env:UFT_LAUNCHER
Import-Module $uftworkdir\bin\PSModule.dll
$parallelRunnerConfig = $null
$mobileConfig = $null
$proxyConfig = $null

[List[Device]]$devices = $null
if ($envType -eq "") {
	throw "Environment type not selected."
} elseif ($envType -eq "mobile") {
	if ([string]::IsNullOrWhiteSpace($mcDevices)) {
		throw "The Devices field is required."
	} elseif ([string]::IsNullOrWhiteSpace($mcServerUrl)) {
		throw "Mobile Center Server is empty."
	} elseif ([string]::IsNullOrWhiteSpace($mcUsername)) {
		throw "Mobile Center Username is empty."
	}
	if ($useMcProxy) {
		if ([string]::IsNullOrWhiteSpace($mcProxyUrl)) {
			throw "Proxy Server is empty."
		} elseif ($useMcProxyCredentials -and [string]::IsNullOrWhiteSpace($mcProxyUsername)) {
			throw "Proxy Username is empty."
		}
		$proxySrvConfig = [ServerConfig]::new($mcProxyUrl, $mcProxyUsername, $mcProxyPassword)
		$proxyConfig = [ProxyConfig]::new($proxySrvConfig, $useMcProxyCredentials)
	}
	$mobileSrvConfig = [ServerConfig]::new($mcServerUrl, $mcUsername, $mcPassword, $mcTenantId)
	$mobileConfig = [MobileConfig]::new($mobileSrvConfig, $useMcProxy, $proxyConfig)
	[List[string]]$invalidDeviceLines = $null
	[Device]::ParseLines($mcDevices, [ref]$devices, [ref]$invalidDeviceLines)
	if ($invalidDeviceLines -and $invalidDeviceLines.Count -gt 0) {
		foreach ($line in $invalidDeviceLines) {
			Write-Warning "Invalid device line -> $($line). The expected pattern is property1:""value1"", property2:""value2""... Valid property names are: DeviceID, Manufacturer, Model, OSType and OSVersion.";
		}
	}
	if ($devices.Count -eq 0) {
		throw "Missing or invalid devices."
	}
} elseif ($envType -eq "web") {
	$browsers = [List[string]]::new()
	if ($useChrome) {
		$browsers.Add("Chrome")
	}
	if ($useChromeH) {
		$browsers.Add("Chrome_Headless")
	}
	if ($useChromium) {
		$browsers.Add("ChromiumEdge")
	}
	if ($useEdge) {
		$browsers.Add("Edge")
	}
	if ($useFirefox) {
		$browsers.Add("Firefox")
	}
	if ($useFirefox64) {
		$browsers.Add("Firefox64")
	}
	if ($useIExplorer) {
		$browsers.Add('IE')
	}
	if ($useIExplorer64) {
		$browsers.Add('IE64')
	}
	if ($useSafari) {
		$browsers.Add('Safari')
	}
	if ($browsers.Count -eq 0) {
		throw "At least one browser is required to be selected."
	}
}
$parallelRunnerConfig = [ParallelRunnerConfig]::new($envType, $devices, $browsers)

# $env:SYSTEM can be used also to determine the pipeline type "build" or "release"
if ($env:SYSTEM_HOSTTYPE -eq "build") {
	$buildNumber = $env:BUILD_BUILDNUMBER
	[int]$rerunIdx = [convert]::ToInt32($env:SYSTEM_STAGEATTEMPT, 10) - 1
	$rerunType = "rerun"
} else {
	$buildNumber = $env:RELEASE_RELEASEID
	[int]$rerunIdx = $env:RELEASE_ATTEMPTNUMBER
	$rerunType = "attempt"
}

$resDir = Join-Path $uftworkdir -ChildPath "res\Report_$buildNumber"

#---------------------------------------------------------------------------------------------------

function UploadArtifactToAzureStorage($storageContext, $container, $testPathReportInput, $artifact) {
	#upload artifact to storage container
	Set-AzStorageBlobContent -Container "$($container)" -File $testPathReportInput -Blob $artifact -Context $storageContext
}

function ArchiveReport($artifact, $rptFolder) {
	if (Test-Path $rptFolder) {
		$fullPathZipFile = Join-Path $rptFolder -ChildPath $artifact
		Compress-Archive -Path $rptFolder -DestinationPath $fullPathZipFile
		return $fullPathZipFile
	}
	return $null
}

function UploadHtmlReport() {
	$index = 0
	foreach ( $item in $rptFolders ) {
		$testPathReportInput = Join-Path $item -ChildPath "run_results.html"
		if (Test-Path -LiteralPath $testPathReportInput) {
			$artifact = $rptFileNames[$index]
			# upload resource to container
			UploadArtifactToAzureStorage $storageContext $container $testPathReportInput $artifact
		}
		$index += 1
	}
}

function UploadArchive() {
	$index = 0
	foreach ( $item in $rptFolders ) {
		#archive report folder	
		$artifact = $zipFileNames[$index]
		
		$fullPathZipFile = ArchiveReport $artifact $item
		if ($fullPathZipFile) {
			UploadArtifactToAzureStorage $storageContext $container $fullPathZipFile $artifact
		}
					
		$index += 1
	}
}

#---------------------------------------------------------------------------------------------------

$uftReport = "$resDir\UFT Report"
$runSummary = "$resDir\Run Summary"
$retcodefile = "$resDir\TestRunReturnCode.txt"
$failedTests = "$resDir\Failed Tests"

$rptFolders = [List[string]]::new()
$rptFileNames = [List[string]]::new()
$zipFileNames = [List[string]]::new()

if ($rptFileName) {
	$rptFileName += "_$buildNumber"
} else {
	$rptFileName = "${pipelineName}_${buildNumber}"
}
if ($rerunIdx) {
	$rptFileName += "_$rerunType$rerunIdx"
}

$archiveNamePattern = "${rptFileName}_Report"

#---------------------------------------------------------------------------------------------------
#storage variables validation

if($uploadArtifact -eq "yes") {
	# get resource group
	if ($null -eq $env:RESOURCE_GROUP) {
		Write-Error "Missing resource group."
	} else {
		$group = $env:RESOURCE_GROUP
		$resourceGroup = Get-AzResourceGroup -Name "$($group)"
		$groupName = $resourceGroup.ResourceGroupName
	}

	# get storage account
	$account = $env:STORAGE_ACCOUNT

	$storageAccounts = Get-AzStorageAccount -ResourceGroupName "$($groupName)"

	$correctAccount = 0
	foreach($item in $storageAccounts) {
		if ($item.storageaccountname -like $account) {
			$storageAccount = $item
			$correctAccount = 1
			break
		}
	}

	if ($correctAccount -eq 0) {
		if ([string]::IsNullOrEmpty($account)) {
			Write-Error "Missing storage account."
		} else {
			Write-Error ("Provided storage account {0} not found." -f $account)
		}
	} else {
		$storageContext = $storageAccount.Context
		
		#get container
		$container = $env:CONTAINER

		$storageContainer = Get-AzStorageContainer -Context $storageContext -ErrorAction Stop | where-object {$_.Name -eq $container}
		if ($storageContainer -eq $null) {
			if ([string]::IsNullOrEmpty($container)) {
				Write-Error "Missing storage container."
			} else {
				Write-Error ("Provided storage container {0} not found." -f $container)
			}
		}
	}
}

if ($rerunIdx) {
	Write-Host "$((Get-Culture).TextInfo.ToTitleCase($rerunType)) = $rerunIdx"
	if (Test-Path $runSummary) {
		try {
			Remove-Item $runSummary -ErrorAction Stop
		} catch {
			Write-Error "Cannot rerun because the file '$runSummary' is currently in use."
		}
	}
	if (Test-Path $uftReport) {
		try {
			Remove-Item $uftReport -ErrorAction Stop
		} catch {
			Write-Error "Cannot rerun because the file '$uftReport' is currently in use."
		}
	}
	if (Test-Path $failedTests) {
		try {
			Remove-Item $failedTests -ErrorAction Stop
		} catch {
			Write-Error "Cannot rerun because the file '$failedTests' is currently in use."
		}
	}
}

#---------------------------------------------------------------------------------------------------
#Run the tests
Invoke-FSTask $testPathInput $timeOutIn $uploadArtifact $artifactType $env:STORAGE_ACCOUNT $env:CONTAINER $rptFileName $archiveNamePattern $buildNumber $enableFailedTestsRpt $true $parallelRunnerConfig $rptFolders $mobileConfig -Verbose 

$ind = 1
foreach ($item in $rptFolders) {
	$rptFileNames.Add("${rptFileName}_${ind}.html")
	$zipFileNames.Add("${rptFileName}_Report_${ind}.zip")
	$ind += 1
}

#---------------------------------------------------------------------------------------------------
#upload artifacts to Azure storage
if ($uploadArtifact -eq "yes") {
	if ($artifactType -eq "onlyReport") { #upload only report
		UploadHtmlReport
	} elseif ($artifactType -eq "onlyArchive") { #upload only archive
		UploadArchive
	} else { #upload both report and archive
		UploadHtmlReport
		UploadArchive
	}
}

#---------------------------------------------------------------------------------------------------
# uploads report files to build artifacts
$all = "$resDir\all_" + $rerunIdx
if ((Test-Path $runSummary) -and (Test-Path $uftReport)) {
	$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
	$html = [System.Text.StringBuilder]""
	$html.Append("<div class=`"margin-right-8 margin-left-8 padding-8 depth-8`"><div class=`"body-xl`">Run Sumary</div>")
	$html.AppendLine((Get-Content -Path $runSummary))
	$html.AppendLine("</div><div class=`"margin-8 padding-8 depth-8`"><div class=`"body-xl`">UFT Report</div>")
	$html.AppendLine((Get-Content -Path $uftReport))
	$html.AppendLine("</div>")
	if (Test-Path $failedTests) {
		$html.AppendLine("<div class=`"margin-8 padding-8 depth-8`"><div class=`"body-xl`">Failed Tests</div>")
		$html.AppendLine((Get-Content -Path $failedTests))
		$html.AppendLine("</div>")
	}
	$html.ToString() >> $all
	if ($rerunIdx) {
		Write-Host "##vso[task.addattachment type=Distributedtask.Core.Summary;name=Reports ($rerunType $rerunIdx);]$all"
	} else {
		Write-Host "##vso[task.addattachment type=Distributedtask.Core.Summary;name=Reports;]$all"
	}
}

# read return code
if (Test-Path $retcodefile) {
	$content = Get-Content $retcodefile
	if ($content) {
		$sep = [Environment]::NewLine
		$option = [System.StringSplitOptions]::RemoveEmptyEntries
		$arr = $content.Split($sep, $option)
		[int]$retcode = [convert]::ToInt32($arr[-1], 10)
	
		if ($retcode -eq 0) {
			Write-Host "Test passed"
		}

		if ($retcode -eq -3) {
			Write-Error "Task Failed with message: Closed by user"
		} elseif ($retcode -ne 0) {
			Write-Error "Task Failed"
		}
	} else {
		Write-Error "The file [$retcodefile] is empty!"
	}
} else {
	Write-Error "The file [$retcodefile] is missing!"
}
