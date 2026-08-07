param([int]$LatestYear = (Get-Date).Year)
$ErrorActionPreference = 'Stop'
$apiKey = $env:DART_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'DART_API_KEY is missing.' }
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$path = Join-Path $root 'data\financials.json'
$data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
$reportNames = @{ '11011'='Annual report'; '11012'='Half-year report'; '11013'='First-quarter report'; '11014'='Third-quarter report' }
$periodNames = @{ '11011'='Annual'; '11012'='H1 cumulative'; '11013'='Q1'; '11014'='Q3 cumulative' }
function Invoke-Dart([string]$corpCode,[int]$year,[string]$reportCode) {
  foreach ($fs in @('CFS','OFS')) {
    $uri = 'https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json?crtfc_key={0}&corp_code={1}&bsns_year={2}&reprt_code={3}&fs_div={4}' -f [uri]::EscapeDataString($apiKey),$corpCode,$year,$reportCode,$fs
    $response = Invoke-RestMethod -Uri $uri -TimeoutSec 60
    if ($response.status -eq '000' -and @($response.list).Count) { return $response }
    if ($response.status -notin @('000','013')) { throw "OpenDART error $($response.status): $($response.message)" }
  }
  return $null
}
function Amount($value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq '-') { return $null }
  [long]$n=0; if ([long]::TryParse(([string]$value).Replace(',','').Trim(),[ref]$n)) { return $n }; return $null
}
function Account($rows,[string[]]$ids) {
  foreach ($id in $ids) { $r=$rows|Where-Object { $_.account_id -eq $id }|Select-Object -First 1; if($r){return Amount $r.thstrm_amount} }
  return $null
}
$candidates=@()
foreach($year in @($LatestYear,($LatestYear-1),($LatestYear-2))){foreach($code in @('11014','11012','11013','11011')){$rank=switch($code){'11011'{4};'11014'{3};'11012'{2};'11013'{1}};$candidates+=[pscustomobject]@{year=$year;code=$code;sort=($year*10+$rank)}}}
$candidates=$candidates|Sort-Object sort -Descending
foreach($property in $data.stocks.PSObject.Properties){
  $stock=$property.Value;$reports=@()
  foreach($candidate in $candidates){
    if($reports.Count -ge 5){break};$finance=Invoke-Dart ([string]$stock.company.corpCode) $candidate.year $candidate.code;if(-not $finance){continue};$rows=@($finance.list)
    $reports += [ordered]@{
      businessYear=$candidate.year;reportCode=$candidate.code;reportName=$reportNames[$candidate.code];periodName=$periodNames[$candidate.code];fsDivision=[string]$rows[0].fs_div
      revenue=Account $rows @('ifrs-full_Revenue','ifrs_Revenue','dart_Revenue')
      operatingIncome=Account $rows @('dart_OperatingIncomeLoss')
      netIncome=Account $rows @('ifrs-full_ProfitLoss','ifrs_ProfitLoss')
      assets=Account $rows @('ifrs-full_Assets','ifrs_Assets')
      liabilities=Account $rows @('ifrs-full_Liabilities','ifrs_Liabilities')
      equity=Account $rows @('ifrs-full_Equity','ifrs_Equity')
      operatingCashFlow=Account $rows @('ifrs-full_CashFlowsFromUsedInOperatingActivities','ifrs_CashFlowsFromUsedInOperatingActivities')
    }
  }
  $annual=@($reports|Where-Object reportCode -eq '11011'|Select-Object -First 1);$quarters=@($reports|Where-Object reportCode -ne '11011'|Select-Object -First 4)
  $stock|Add-Member -NotePropertyName annualReport -NotePropertyValue ($annual|Select-Object -First 1) -Force
  $stock|Add-Member -NotePropertyName quarterlyReports -NotePropertyValue $quarters -Force
  Write-Host "[$($property.Name)] annual=$($annual.Count), quarterly=$($quarters.Count)"
}
$data.generatedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
[IO.File]::WriteAllText($path,($data|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Host "Done: $path"
