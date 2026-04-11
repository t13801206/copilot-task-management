<#
.SYNOPSIS
    現在のリポジトリにリンクされた GitHub Project を自動検出して情報を返す
.DESCRIPTION
    gh repo view でリポジトリ情報を取得し、リンクされた Project を GraphQL で検索する。
    リンクされた Project が 1 件ならその情報を PSCustomObject で返す。
    0 件・複数件の場合はエラーを出力して終了する。
.PARAMETER ProjectNumber
    自動検出を使わず、プロジェクト番号を直接指定する。
.EXAMPLE
    $info = & "$PSScriptRoot\Resolve-ProjectNumber.ps1"
    $info.ProjectNumber   # => 7
    $info.ProjectOwner    # => "runceel"
    $info.RepoFullName    # => "runceel/copilot-task-management"
#>
param(
    [int]$ProjectNumber
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- リポジトリ情報の取得 ---
$repoJson = gh repo view --json owner,name 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "リポジトリ情報を取得できません。git リポジトリ内で gh CLI が認証済みか確認してください。"
    exit 1
}
$repo = ($repoJson | Out-String) | ConvertFrom-Json
$repoOwner = $repo.owner.login
$repoName = $repo.name
$repoFullName = "$repoOwner/$repoName"

# --- プロジェクト番号が指定されている場合 ---
if ($ProjectNumber -gt 0) {
    # 指定された番号のプロジェクトの owner を取得
    $query = @'
{
  repository(owner: "__REPO_OWNER__", name: "__REPO_NAME__") {
    projectsV2(first: 20) {
      nodes {
        number
        title
        owner { ... on User { login } ... on Organization { login } }
      }
    }
  }
}
'@
    $query = $query -replace '__REPO_OWNER__', $repoOwner -replace '__REPO_NAME__', $repoName
    $result = gh api graphql -f query=$query 2>&1
    $response = ($result | Out-String) | ConvertFrom-Json
    $projects = $response.data.repository.projectsV2.nodes

    $matched = $projects | Where-Object { $_.number -eq $ProjectNumber }
    if (-not $matched) {
        Write-Error "プロジェクト番号 $ProjectNumber はこのリポジトリにリンクされていません。"
        exit 1
    }

    return [PSCustomObject]@{
        RepoOwner      = $repoOwner
        RepoName       = $repoName
        RepoFullName   = $repoFullName
        ProjectOwner   = $matched.owner.login
        ProjectNumber  = $matched.number
        ProjectTitle   = $matched.title
    }
}

# --- 自動検出 ---
$query = @'
{
  repository(owner: "__REPO_OWNER__", name: "__REPO_NAME__") {
    projectsV2(first: 20) {
      nodes {
        number
        title
        owner { ... on User { login } ... on Organization { login } }
      }
    }
  }
}
'@
$query = $query -replace '__REPO_OWNER__', $repoOwner -replace '__REPO_NAME__', $repoName

$result = gh api graphql -f query=$query 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub API の呼び出しに失敗しました。gh auth refresh -s project でスコープを確認してください。"
    exit 1
}
$response = ($result | Out-String) | ConvertFrom-Json
$projects = $response.data.repository.projectsV2.nodes

if ($projects.Count -eq 0) {
    Write-Error @"
NO_LINKED_PROJECT: このリポジトリにリンクされた GitHub Project がありません。
Copilot の project-setup エージェントを使ってプロジェクトを作成してください:
  @project-setup このリポジトリ用のプロジェクトを作成して
"@
    exit 1
}

if ($projects.Count -gt 1) {
    Write-Error "このリポジトリに複数のプロジェクトがリンクされています。-ProjectNumber で指定してください:"
    foreach ($p in $projects) {
        Write-Error "  番号: $($p.number)  タイトル: $($p.title)  オーナー: $($p.owner.login)"
    }
    exit 1
}

$project = $projects[0]
return [PSCustomObject]@{
    RepoOwner      = $repoOwner
    RepoName       = $repoName
    RepoFullName   = $repoFullName
    ProjectOwner   = $project.owner.login
    ProjectNumber  = $project.number
    ProjectTitle   = $project.title
}
