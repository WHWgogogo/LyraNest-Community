<#
.SYNOPSIS
Validates a deployed LyraNest Community server through its public HTTP API.

.DESCRIPTION
Checks the embedded web page, health endpoint, library APIs, streaming behavior,
and lyrics availability. Authenticated API checks require a token obtained from
a SecureString, environment variable, or secure prompt. Stateful library scan
validation and scrape validation are opt-in.
#>

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BaseUrl = 'http://192.168.0.107:8080',

    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 30,

    [ValidateRange(1, 10485760)]
    [int]$MaximumResponseBytes = 1048576,

    [ValidateRange(1, 10000)]
    [int]$LyricsSampleSize = 10,

    [ValidateRange(0, 2147483647)]
    [int]$ExpectedTrackCount = 0,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$AuthTokenEnvVar = 'HARMONY_VERIFY_AUTH_TOKEN',

    [Parameter()]
    [System.Security.SecureString]$AuthToken,

    [Parameter()]
    [switch]$PromptForAuthToken,

    [object]$SkipLibraryScan = $true,

    [object]$SkipScrape = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:PassedChecks = 0
$script:FailedChecks = 0
$script:SkippedChecks = 0
$script:NormalizedBaseUrl = $null
$script:AuthToken = $null

function Write-Verification {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'PASS', 'FAIL', 'SKIP')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Write-SkippedCheck {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:SkippedChecks++
    Write-Verification -Level 'SKIP' -Message $Message
}

function Test-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage,

        [string]$SuccessMessage = $Name
    )

    if ($Condition) {
        $script:PassedChecks++
        Write-Verification -Level 'PASS' -Message $SuccessMessage
        return $true
    }

    $script:FailedChecks++
    Write-Verification -Level 'FAIL' -Message ('{0}: {1}' -f $Name, $FailureMessage)
    return $false
}

function ConvertTo-NormalizedBaseUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $trimmedUrl = $Url.Trim()
    $uri = $null
    if (-not [System.Uri]::TryCreate($trimmedUrl, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "BaseUrl must be an absolute HTTP(S) URL: $Url"
    }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') {
        throw "BaseUrl must use HTTP or HTTPS: $Url"
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.Query) -or -not [string]::IsNullOrWhiteSpace($uri.Fragment)) {
        throw "BaseUrl must not include a query string or fragment: $Url"
    }

    return $uri.GetLeftPart([System.UriPartial]::Authority).TrimEnd('/')
}

function ConvertTo-BooleanValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [int] -or $Value -is [long]) {
        if ($Value -eq 1) {
            return $true
        }
        if ($Value -eq 0) {
            return $false
        }
    }

    $text = ([string]$Value).Trim()
    if ($text -match '^(?i:true|1)$') {
        return $true
    }
    if ($text -match '^(?i:false|0)$') {
        return $false
    }

    throw "$ParameterName must be true or false."
}

function ConvertFrom-SecureStringValue {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Value)

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-VerificationAuthToken {
    if ($null -ne $AuthToken -and $PromptForAuthToken) {
        throw 'Choose either -AuthToken or -PromptForAuthToken, not both.'
    }

    if ($null -ne $AuthToken) {
        $token = ConvertFrom-SecureStringValue -Value $AuthToken
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'The supplied authentication token is empty.'
        }
        return $token.Trim()
    }

    foreach ($target in @('Process', 'User', 'Machine')) {
        $token = [Environment]::GetEnvironmentVariable($AuthTokenEnvVar, $target)
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            return $token.Trim()
        }
    }

    if ($PromptForAuthToken) {
        $token = ConvertFrom-SecureStringValue -Value (Read-Host 'API authentication token' -AsSecureString)
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'The supplied authentication token is empty.'
        }
        return $token.Trim()
    }

    return $null
}

function Get-AuthenticatedHeaders {
    if ([string]::IsNullOrWhiteSpace($script:AuthToken)) {
        return @{}
    }

    return @{ Authorization = "Bearer $($script:AuthToken)" }
}

function New-RequestUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not $Path.StartsWith('/')) {
        throw "Request path must start with '/': $Path"
    }

    return [System.Uri]($script:NormalizedBaseUrl + $Path)
}

function Get-HeaderValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebHeaderCollection]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = $Headers[$Name]
    if ($null -eq $value) {
        return ''
    }

    return [string]$value
}

function Read-ResponseBody {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [int]$MaximumBytes
    )

    $buffer = New-Object byte[] 8192
    $output = New-Object System.IO.MemoryStream
    try {
        while ($true) {
            $read = $Stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) {
                break
            }
            if (($output.Length + $read) -gt $MaximumBytes) {
                throw "Response body exceeds the configured limit of $MaximumBytes bytes."
            }
            $output.Write($buffer, 0, $read)
        }
        return ,$output.ToArray()
    }
    finally {
        $output.Dispose()
    }
}

function Invoke-HttpRequest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'HEAD', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$Headers = @{},

        [string]$Body = '',

        [int]$ResponseLimitBytes = $MaximumResponseBytes
    )

    $request = [System.Net.HttpWebRequest]::Create((New-RequestUri -Path $Path))
    $request.Method = $Method
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
    $request.AllowAutoRedirect = $false
    $request.KeepAlive = $false
    $request.UserAgent = 'LyraNest Community-Deployment-Verification/1.0.0'
    $request.Accept = '*/*'

    foreach ($headerName in $Headers.Keys) {
        $headerValue = [string]$Headers[$headerName]
        switch -Regex ($headerName) {
            '^Accept$' { $request.Accept = $headerValue; break }
            '^Content-Type$' { $request.ContentType = $headerValue; break }
            '^Range$' {
                if ($headerValue -notmatch '^bytes=(\d+)-(\d+)$') {
                    throw "Only explicit byte ranges are supported by this verifier: $headerValue"
                }
                $request.AddRange([int64]$Matches[1], [int64]$Matches[2])
                break
            }
            default { $request.Headers[$headerName] = $headerValue; break }
        }
    }

    if ($Method -eq 'POST') {
        if ([string]::IsNullOrWhiteSpace($request.ContentType)) {
            $request.ContentType = 'application/json; charset=utf-8'
        }
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bodyBytes.Length
        $requestStream = $request.GetRequestStream()
        try {
            $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        }
        finally {
            $requestStream.Dispose()
        }
    }

    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
    }
    catch [System.Net.WebException] {
        if ($null -ne $_.Exception.Response) {
            $response = [System.Net.HttpWebResponse]$_.Exception.Response
        }
        else {
            throw ("{0} {1} failed: {2}" -f $Method, $Path, $_.Exception.Message)
        }
    }

    try {
        [byte[]]$responseBody = [byte[]]@()
        if ($Method -ne 'HEAD' -and $ResponseLimitBytes -gt 0) {
            $responseStream = $response.GetResponseStream()
            if ($null -ne $responseStream) {
                try {
                    $responseBody = [byte[]](Read-ResponseBody -Stream $responseStream -MaximumBytes $ResponseLimitBytes)
                }
                finally {
                    $responseStream.Dispose()
                }
            }
        }

        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Status      = [string]$response.StatusDescription
            Headers     = $response.Headers
            BodyBytes   = $responseBody
            BodyText    = [System.Text.Encoding]::UTF8.GetString($responseBody)
            Method      = $Method
            Path        = $Path
        }
    }
    finally {
        $response.Dispose()
    }
}

function ConvertFrom-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Response,

        [Parameter(Mandatory = $true)]
        [string]$CheckName
    )

    if ([string]::IsNullOrWhiteSpace($Response.BodyText)) {
        throw "$CheckName returned an empty response body."
    }

    try {
        return $Response.BodyText | ConvertFrom-Json
    }
    catch {
        throw "$CheckName returned invalid JSON: $($_.Exception.Message)"
    }
}

function Get-JsonPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-TracksResponse {
    param([Parameter(Mandatory = $true)][psobject]$Response)

    $body = ConvertFrom-JsonResponse -Response $Response -CheckName 'GET /api/v1/tracks'
    $tracks = @(Get-JsonPropertyValue -Object $body -Name 'tracks')
    $totalValue = Get-JsonPropertyValue -Object $body -Name 'total'
    if ($null -eq $totalValue -or -not ($totalValue -is [ValueType])) {
        throw 'GET /api/v1/tracks response must include numeric total.'
    }

    return [pscustomobject]@{
        Tracks = $tracks
        Total  = [int]$totalValue
    }
}

function Get-TrackIds {
    param([Parameter(Mandatory = $true)][object[]]$Tracks)

    $trackIds = New-Object System.Collections.Generic.List[string]
    $seenIds = @{}
    foreach ($track in $Tracks) {
        $id = [string](Get-JsonPropertyValue -Object $track -Name 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw 'Track list contains a track without a non-empty id.'
        }
        if ($seenIds.ContainsKey($id)) {
            throw "Track list contains duplicate id '$id'."
        }
        $seenIds[$id] = $true
        $trackIds.Add($id)
    }

    return @($trackIds)
}

function Get-EncodedTrackPath {
    param(
        [Parameter(Mandatory = $true)][string]$TrackId,
        [Parameter(Mandatory = $true)][string]$Suffix
    )

    return '/api/v1/tracks/{0}/{1}' -f [System.Uri]::EscapeDataString($TrackId), $Suffix
}

function Test-ResponseStatus {
    param(
        [Parameter(Mandatory = $true)][psobject]$Response,
        [Parameter(Mandatory = $true)][int[]]$ExpectedStatusCodes,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $expectedText = $ExpectedStatusCodes -join ' or '
    return Test-Condition -Condition ($ExpectedStatusCodes -contains $Response.StatusCode) -Name $Name -SuccessMessage ("$Name ($($Response.StatusCode))") -FailureMessage ("expected HTTP $expectedText, got HTTP $($Response.StatusCode): $($Response.BodyText)")
}

function Test-RootPage {
    $response = Invoke-HttpRequest -Method 'GET' -Path '/' -Headers @{ Accept = 'text/html' }
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'GET / accepts text/html'
    $contentType = Get-HeaderValue -Headers $response.Headers -Name 'Content-Type'
    $contentTypeOk = Test-Condition -Condition ($contentType -match '(?i)^text/html(?:;|$)') -Name 'GET / content type' -SuccessMessage "GET / Content-Type is $contentType" -FailureMessage "expected text/html, got '$contentType'."
    $bodyOk = Test-Condition -Condition (-not [string]::IsNullOrWhiteSpace($response.BodyText)) -Name 'GET / HTML body' -FailureMessage 'response body is empty.'
    return $statusOk -and $contentTypeOk -and $bodyOk
}

function Test-Health {
    $response = Invoke-HttpRequest -Method 'GET' -Path '/healthz'
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'GET /healthz'
    if (-not $statusOk) {
        return $false
    }

    $body = ConvertFrom-JsonResponse -Response $response -CheckName 'GET /healthz'
    $status = [string](Get-JsonPropertyValue -Object $body -Name 'status')
    return Test-Condition -Condition ($status -eq 'ok') -Name 'GET /healthz status' -SuccessMessage 'GET /healthz reports status=ok' -FailureMessage "expected status 'ok', got '$status'."
}

function Test-AuthenticatedApiAccess {
    $response = Invoke-HttpRequest -Method 'GET' -Path '/api/v1/auth/me' -Headers (Get-AuthenticatedHeaders)
    return Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'GET /api/v1/auth/me'
}

function Test-TrackList {
    $response = Invoke-HttpRequest -Method 'GET' -Path '/api/v1/tracks' -Headers (Get-AuthenticatedHeaders)
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'GET /api/v1/tracks'
    if (-not $statusOk) {
        return $null
    }

    $trackResponse = Get-TracksResponse -Response $response
    $ids = @(Get-TrackIds -Tracks $trackResponse.Tracks)
    $totalMatches = Test-Condition -Condition ($trackResponse.Total -eq $ids.Count) -Name 'Track total matches list' -SuccessMessage "track total is $($ids.Count)" -FailureMessage "response total is $($trackResponse.Total), but tracks contains $($ids.Count) entries."
    $hasTracks = Test-Condition -Condition ($ids.Count -gt 0) -Name 'Track list is non-empty' -SuccessMessage "found $($ids.Count) tracks" -FailureMessage 'no tracks were returned.'
    $expectedCountMatches = $true
    if ($ExpectedTrackCount -gt 0) {
        $expectedCountMatches = Test-Condition -Condition ($ids.Count -eq $ExpectedTrackCount) -Name 'Expected track count' -SuccessMessage "found expected $ExpectedTrackCount tracks" -FailureMessage "expected $ExpectedTrackCount tracks, found $($ids.Count)."
    }

    if (-not ($totalMatches -and $hasTracks -and $expectedCountMatches)) {
        return $null
    }

    return [pscustomobject]@{
        Tracks = $trackResponse.Tracks
        Ids    = $ids
    }
}

function Test-Stream {
    param([Parameter(Mandatory = $true)][string]$TrackId)

    $streamPath = Get-EncodedTrackPath -TrackId $TrackId -Suffix 'stream'
    $getResponse = Invoke-HttpRequest -Method 'GET' -Path $streamPath -Headers (Get-AuthenticatedHeaders) -ResponseLimitBytes 0
    $getOk = Test-ResponseStatus -Response $getResponse -ExpectedStatusCodes @(200) -Name 'First track stream GET'
    $contentLength = Get-HeaderValue -Headers $getResponse.Headers -Name 'Content-Length'
    $getBodyOk = Test-Condition -Condition ($contentLength -match '^\d+$' -and [int64]$contentLength -gt 0) -Name 'First track stream GET body' -SuccessMessage "stream Content-Length is $contentLength bytes" -FailureMessage "expected a positive Content-Length header, got '$contentLength'."
    $acceptRanges = Get-HeaderValue -Headers $getResponse.Headers -Name 'Accept-Ranges'
    $rangesOk = Test-Condition -Condition ($acceptRanges -match '(?i)bytes') -Name 'First track stream range support' -SuccessMessage "Accept-Ranges is $acceptRanges" -FailureMessage "expected Accept-Ranges: bytes, got '$acceptRanges'."

    $headResponse = Invoke-HttpRequest -Method 'HEAD' -Path $streamPath -Headers (Get-AuthenticatedHeaders)
    $headOk = Test-ResponseStatus -Response $headResponse -ExpectedStatusCodes @(200) -Name 'First track stream HEAD'
    $headBodyOk = Test-Condition -Condition ($headResponse.BodyBytes.Length -eq 0) -Name 'First track stream HEAD body' -SuccessMessage 'HEAD returned no body' -FailureMessage "HEAD returned $($headResponse.BodyBytes.Length) body bytes."

    $rangeHeaders = Get-AuthenticatedHeaders
    $rangeHeaders['Range'] = 'bytes=0-0'
    $rangeResponse = Invoke-HttpRequest -Method 'GET' -Path $streamPath -Headers $rangeHeaders -ResponseLimitBytes 1024
    $rangeOk = Test-ResponseStatus -Response $rangeResponse -ExpectedStatusCodes @(206) -Name 'First track stream Range GET'
    $rangeBodyOk = Test-Condition -Condition ($rangeResponse.BodyBytes.Length -eq 1) -Name 'First track Range body size' -SuccessMessage 'Range returned exactly one byte' -FailureMessage "expected one byte, got $($rangeResponse.BodyBytes.Length)."
    $contentRange = Get-HeaderValue -Headers $rangeResponse.Headers -Name 'Content-Range'
    $contentRangeOk = Test-Condition -Condition ($contentRange -match '^bytes 0-0/\d+$') -Name 'First track Content-Range' -SuccessMessage "Content-Range is $contentRange" -FailureMessage "expected 'bytes 0-0/<total>', got '$contentRange'."

    return $getOk -and $getBodyOk -and $rangesOk -and $headOk -and $headBodyOk -and $rangeOk -and $rangeBodyOk -and $contentRangeOk
}

function Test-Lyrics {
    param([Parameter(Mandatory = $true)][string[]]$TrackIds)

    $sampleCount = [Math]::Min($LyricsSampleSize, $TrackIds.Count)
    $lyricsFound = $false
    $unexpectedResponses = 0
    for ($index = 0; $index -lt $sampleCount; $index++) {
        $trackId = $TrackIds[$index]
        $lyricsPath = Get-EncodedTrackPath -TrackId $trackId -Suffix 'lyrics'
        $response = Invoke-HttpRequest -Method 'GET' -Path $lyricsPath -Headers (Get-AuthenticatedHeaders)
        if ($response.StatusCode -eq 404) {
            Write-Verification -Level 'INFO' -Message "Lyrics unavailable for track $trackId (HTTP 404 is allowed)."
            continue
        }
        if ($response.StatusCode -ne 200) {
            $unexpectedResponses++
            Test-Condition -Condition $false -Name "Lyrics for track $trackId" -FailureMessage "expected HTTP 200 or 404, got HTTP $($response.StatusCode): $($response.BodyText)" | Out-Null
            continue
        }

        $body = ConvertFrom-JsonResponse -Response $response -CheckName "Lyrics for track $trackId"
        $content = [string](Get-JsonPropertyValue -Object $body -Name 'content')
        $contentOk = Test-Condition -Condition (-not [string]::IsNullOrWhiteSpace($content)) -Name "Lyrics content for track $trackId" -SuccessMessage "lyrics content is non-empty for track $trackId" -FailureMessage 'HTTP 200 response has empty lyrics content.'
        if ($contentOk) {
            $lyricsFound = $true
        }
    }

    if ($sampleCount -lt $LyricsSampleSize) {
        Write-Verification -Level 'INFO' -Message "Only $sampleCount tracks are available for the requested $LyricsSampleSize-track lyrics sample."
    }

    $foundCheck = Test-Condition -Condition $lyricsFound -Name 'Lyrics sample' -SuccessMessage 'at least one sampled track returned non-empty lyrics' -FailureMessage "none of the $sampleCount sampled tracks returned non-empty lyrics."
    return ($unexpectedResponses -eq 0) -and $foundCheck
}

function Test-LibraryStatus {
    param([Parameter(Mandatory = $true)][int]$TrackCount)

    $response = Invoke-HttpRequest -Method 'GET' -Path '/api/v1/library/status' -Headers (Get-AuthenticatedHeaders)
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'GET /api/v1/library/status'
    if (-not $statusOk) {
        return $false
    }

    $body = ConvertFrom-JsonResponse -Response $response -CheckName 'GET /api/v1/library/status'
    $directory = [string](Get-JsonPropertyValue -Object $body -Name 'directory')
    $trackCountValue = Get-JsonPropertyValue -Object $body -Name 'track_count'
    $scanningValue = Get-JsonPropertyValue -Object $body -Name 'scanning'
    $directoryOk = Test-Condition -Condition (-not [string]::IsNullOrWhiteSpace($directory)) -Name 'Library status directory' -FailureMessage 'directory is missing or empty.'
    $countOk = Test-Condition -Condition ($null -ne $trackCountValue -and [int]$trackCountValue -eq $TrackCount) -Name 'Library status track count' -SuccessMessage "library status track_count is $TrackCount" -FailureMessage "expected track_count $TrackCount, got '$trackCountValue'."
    $notScanning = Test-Condition -Condition ($scanningValue -eq $false) -Name 'Library status scanning flag' -SuccessMessage 'library is not currently scanning' -FailureMessage "expected scanning=false, got '$scanningValue'."
    return $directoryOk -and $countOk -and $notScanning
}

function Test-LibraryScan {
    $response = Invoke-HttpRequest -Method 'POST' -Path '/api/v1/library/scan' -Headers (Get-AuthenticatedHeaders) -Body '{}'
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'POST /api/v1/library/scan'
    if (-not $statusOk) {
        return $null
    }

    $body = ConvertFrom-JsonResponse -Response $response -CheckName 'POST /api/v1/library/scan'
    $tracks = @(Get-JsonPropertyValue -Object $body -Name 'tracks')
    $totalValue = Get-JsonPropertyValue -Object $body -Name 'total'
    if ($null -eq $totalValue) {
        throw 'POST /api/v1/library/scan response must include total.'
    }
    $ids = @(Get-TrackIds -Tracks $tracks)
    $totalOk = Test-Condition -Condition ([int]$totalValue -eq $ids.Count) -Name 'Library scan total matches list' -SuccessMessage "library scan returned $($ids.Count) tracks" -FailureMessage "response total is $totalValue, but tracks contains $($ids.Count) entries."
    $hasTracks = Test-Condition -Condition ($ids.Count -gt 0) -Name 'Library scan finds tracks' -SuccessMessage "library scan found $($ids.Count) tracks" -FailureMessage 'library scan returned no tracks.'
    $expectedCountMatches = $true
    if ($ExpectedTrackCount -gt 0) {
        $expectedCountMatches = Test-Condition -Condition ($ids.Count -eq $ExpectedTrackCount) -Name 'Library scan expected track count' -SuccessMessage "library scan found expected $ExpectedTrackCount tracks" -FailureMessage "expected $ExpectedTrackCount tracks, found $($ids.Count)."
    }
    if (-not ($totalOk -and $hasTracks -and $expectedCountMatches)) {
        return $null
    }

    return [pscustomobject]@{
        Tracks = $tracks
        Ids    = $ids
    }
}

function Test-ScrapeSearch {
    param(
        [Parameter(Mandatory = $true)][string]$TrackId,
        [Parameter(Mandatory = $true)][object]$Track
    )

    $title = [string](Get-JsonPropertyValue -Object $Track -Name 'title')
    $requestBody = @{ query = $title } | ConvertTo-Json -Compress
    $path = Get-EncodedTrackPath -TrackId $TrackId -Suffix 'scrape/search'
    $response = Invoke-HttpRequest -Method 'POST' -Path $path -Headers (Get-AuthenticatedHeaders) -Body $requestBody
    $statusOk = Test-ResponseStatus -Response $response -ExpectedStatusCodes @(200) -Name 'POST first-track scrape search'
    if (-not $statusOk) {
        return $false
    }

    $body = ConvertFrom-JsonResponse -Response $response -CheckName 'POST first-track scrape search'
    $returnedTrackId = [string](Get-JsonPropertyValue -Object $body -Name 'track_id')
    return Test-Condition -Condition ($returnedTrackId -eq $TrackId) -Name 'Scrape search track id' -SuccessMessage 'scrape search returned the requested track id' -FailureMessage "expected '$TrackId', got '$returnedTrackId'."
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script:NormalizedBaseUrl = ConvertTo-NormalizedBaseUrl -Url $BaseUrl
    $script:AuthToken = Get-VerificationAuthToken
    $SkipLibraryScan = ConvertTo-BooleanValue -Value $SkipLibraryScan -ParameterName 'SkipLibraryScan'
    $SkipScrape = ConvertTo-BooleanValue -Value $SkipScrape -ParameterName 'SkipScrape'
    Write-Verification -Level 'INFO' -Message "Verifying deployment at $script:NormalizedBaseUrl"

    Test-RootPage | Out-Null
    Test-Health | Out-Null

    if ([string]::IsNullOrWhiteSpace($script:AuthToken)) {
        Write-SkippedCheck -Message "Authenticated API checks skipped because no token was provided. Use -PromptForAuthToken, -AuthToken, or the $AuthTokenEnvVar environment variable."
    }
    elseif (Test-AuthenticatedApiAccess) {
        $trackList = Test-TrackList
        if ($null -ne $trackList) {
            Test-Stream -TrackId $trackList.Ids[0] | Out-Null
            Test-Lyrics -TrackIds $trackList.Ids | Out-Null
            Test-LibraryStatus -TrackCount $trackList.Ids.Count | Out-Null

            if ($SkipLibraryScan) {
                Write-SkippedCheck -Message 'Library scan verification skipped by default because it changes persistent library state.'
            }
            else {
                Write-Verification -Level 'INFO' -Message 'Library scan verification is enabled and may change persistent library state.'
                $scanResult = Test-LibraryScan
                if ($null -ne $scanResult) {
                    Test-LibraryStatus -TrackCount $scanResult.Ids.Count | Out-Null
                }
            }

            if ($SkipScrape) {
                Write-Verification -Level 'INFO' -Message 'Scrape search skipped (-SkipScrape is true).'
            }
            else {
                Test-ScrapeSearch -TrackId $trackList.Ids[0] -Track $trackList.Tracks[0] | Out-Null
                Write-Verification -Level 'INFO' -Message 'Scrape verification only calls search; it never calls scrape apply.'
            }
        }
        else {
            Write-Verification -Level 'FAIL' -Message 'Dependent checks skipped because track-list validation failed.'
            $script:FailedChecks++
        }
    }
    else {
        Write-Verification -Level 'INFO' -Message 'Dependent authenticated API checks skipped because token validation failed.'
    }
}
catch {
    $script:FailedChecks++
    Write-Verification -Level 'FAIL' -Message $_.Exception.Message
}
finally {
    $script:AuthToken = $null
}

if ($script:FailedChecks -gt 0) {
    Write-Host ("FAIL: {0} passed, {1} failed, {2} skipped." -f $script:PassedChecks, $script:FailedChecks, $script:SkippedChecks)
    exit 1
}

Write-Host ("PASS: {0} checks passed, {1} skipped." -f $script:PassedChecks, $script:SkippedChecks)
exit 0
