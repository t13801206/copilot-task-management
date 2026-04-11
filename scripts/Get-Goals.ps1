<#
.SYNOPSIS
    GitHub Projects からゴール一覧を取得する
.PARAMETER Status
    フィルタするステータス（Todo, In Progress, Done）。省略時はすべて表示。
.PARAMETER ProjectNumber
    プロジェクト番号を直接指定する。省略時はリポジトリにリンクされたプロジェクトを自動検出。
.EXAMPLE
    .\scripts\Get-Goals.ps1
    .\scripts\Get-Goals.ps1 -Status "In Progress"
    .\scripts\Get-Goals.ps1 -Status "Todo","In Progress"
    .\scripts\Get-Goals.ps1 -ProjectNumber 7
#>
param(
    [ValidateSet("Todo", "In Progress", "Done")]
    [string[]]$Status,
    [int]$ProjectNumber
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- プロジェクト情報の自動検出 ---
$resolveArgs = @{}
if ($ProjectNumber -gt 0) { $resolveArgs["ProjectNumber"] = $ProjectNumber }
$projectInfo = & "$PSScriptRoot\Resolve-ProjectNumber.ps1" @resolveArgs
if (-not $projectInfo) { exit 1 }

$Owner = $projectInfo.ProjectOwner
$ProjNum = $projectInfo.ProjectNumber
$Repo = $projectInfo.RepoFullName
$Label = "goal"

$query = @'
{
  user(login: "__OWNER__") {
    projectV2(number: __PROJECT_NUMBER__) {
      items(first: 100) {
        nodes {
          fieldValues(first: 10) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
              ... on ProjectV2ItemFieldDateValue {
                date
                field { ... on ProjectV2Field { name } }
              }
            }
          }
          content {
            ... on Issue {
              number
              title
              state
              labels(first: 10) { nodes { name } }
              repository { nameWithOwner }
              body
            }
          }
        }
      }
    }
  }
}
'@

$query = $query -replace '__OWNER__', $Owner -replace '__PROJECT_NUMBER__', $ProjNum

$result = gh api graphql -f query=$query 2>&1
$response = ($result | Out-String) | ConvertFrom-Json
$items = $response.data.user.projectV2.items.nodes

$results = foreach ($item in $items) {
    $content = $item.content
    if (-not $content -or $content.repository.nameWithOwner -ne $Repo) { continue }

    $labelNames = @($content.labels.nodes | ForEach-Object { $_.name })
    if ($Label -notin $labelNames) { continue }

    $statusValue = ($item.fieldValues.nodes | Where-Object {
        $_.field.name -eq "Status"
    } | Select-Object -First 1).name

    if (-not $statusValue) { $statusValue = "(未設定)" }

    $dueDate = ($item.fieldValues.nodes | Where-Object {
        $_.field.name -eq "Due Date"
    } | Select-Object -First 1).date

    [PSCustomObject]@{
        Number  = $content.number
        Status  = $statusValue
        Title   = $content.title
        DueDate = if ($dueDate) { $dueDate } else { "" }
        State   = $content.state
    }
}

if ($Status) {
    $results = $results | Where-Object { $_.Status -in $Status }
}

$results | Sort-Object @{Expression = {
    switch ($_.Status) {
        "In Progress" { 1 }
        "Todo"        { 2 }
        "(未設定)"    { 3 }
        "Done"        { 4 }
        default       { 9 }
    }
}}, Number | Format-Table -AutoSize
