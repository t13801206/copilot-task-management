<#
.SYNOPSIS
    GitHub Projects 上の Issue のステータスを変更する
.DESCRIPTION
    指定した Issue 番号のステータスを GitHub Projects で更新する。
    Done に変更する場合は Issue も close し、Done 以外に変更する場合は
    Issue が closed なら reopen する。
.PARAMETER IssueNumber
    対象の Issue 番号
.PARAMETER Status
    設定するステータス（Todo, In Progress, Done）
.PARAMETER ProjectNumber
    プロジェクト番号を直接指定する。省略時はリポジトリにリンクされたプロジェクトを自動検出。
.EXAMPLE
    .\scripts\Set-ItemStatus.ps1 -IssueNumber 5 -Status "Done"
    .\scripts\Set-ItemStatus.ps1 -IssueNumber 8 -Status "In Progress"
    .\scripts\Set-ItemStatus.ps1 -IssueNumber 10 -Status "Todo"
#>
param(
    [Parameter(Mandatory)]
    [int]$IssueNumber,

    [Parameter(Mandatory)]
    [ValidateSet("Todo", "In Progress", "Done")]
    [string]$Status,

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

# --- プロジェクトの ID・Status フィールド・選択肢を取得 ---
$metaQuery = @'
{
  user(login: "__OWNER__") {
    projectV2(number: __PROJECT_NUMBER__) {
      id
      field(name: "Status") {
        ... on ProjectV2SingleSelectField {
          id
          options { id name }
        }
      }
    }
  }
}
'@
$metaQuery = $metaQuery -replace '__OWNER__', $Owner -replace '__PROJECT_NUMBER__', $ProjNum

$metaResult = gh api graphql -f query=$metaQuery 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "プロジェクトのメタ情報を取得できませんでした: $metaResult"
    exit 1
}
$metaResponse = ($metaResult | Out-String) | ConvertFrom-Json
$projectId = $metaResponse.data.user.projectV2.id
$fieldId = $metaResponse.data.user.projectV2.field.id
$options = $metaResponse.data.user.projectV2.field.options

$targetOption = $options | Where-Object { $_.name -eq $Status }
if (-not $targetOption) {
    Write-Error "ステータス '$Status' がプロジェクトに存在しません。利用可能: $($options.name -join ', ')"
    exit 1
}
$optionId = $targetOption.id

# --- Issue のプロジェクトアイテム ID を取得 ---
$itemQuery = @'
{
  repository(owner: "__REPO_OWNER__", name: "__REPO_NAME__") {
    issue(number: __ISSUE_NUMBER__) {
      title
      state
      projectItems(first: 20) {
        nodes {
          id
          project { id }
        }
      }
    }
  }
}
'@
$repoOwner = $projectInfo.RepoOwner
$repoName = $projectInfo.RepoName
$itemQuery = $itemQuery -replace '__REPO_OWNER__', $repoOwner `
    -replace '__REPO_NAME__', $repoName `
    -replace '__ISSUE_NUMBER__', $IssueNumber

$itemResult = gh api graphql -f query=$itemQuery 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Issue #$IssueNumber の情報を取得できませんでした: $itemResult"
    exit 1
}
$itemResponse = ($itemResult | Out-String) | ConvertFrom-Json
$issue = $itemResponse.data.repository.issue

if (-not $issue) {
    Write-Error "Issue #$IssueNumber が見つかりません。"
    exit 1
}

$projectItem = $issue.projectItems.nodes | Where-Object { $_.project.id -eq $projectId } | Select-Object -First 1
if (-not $projectItem) {
    Write-Error "Issue #$IssueNumber はプロジェクト '$($projectInfo.ProjectTitle)' に追加されていません。"
    exit 1
}

# --- ステータスを更新 ---
gh project item-edit --project-id $projectId --id $projectItem.id --field-id $fieldId --single-select-option-id $optionId 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "ステータスの更新に失敗しました。"
    exit 1
}

# --- Done なら close、Done 以外なら reopen ---
if ($Status -eq "Done" -and $issue.state -eq "OPEN") {
    gh issue close $IssueNumber 2>&1 | Out-Null
} elseif ($Status -ne "Done" -and $issue.state -eq "CLOSED") {
    gh issue reopen $IssueNumber 2>&1 | Out-Null
}

Write-Host "✅ #$IssueNumber「$($issue.title)」のステータスを $Status に変更しました。" -ForegroundColor Green
