---
name: repo-info
description: 現在のリポジトリのオーナーとリポジトリ名を取得する
---

# リポジトリ情報の取得

`gh` CLI でリポジトリを操作する際、`--repo` フラグにオーナーとリポジトリ名が必要になる場合があります。
以下のコマンドで現在のリポジトリ情報を取得してください。

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

このコマンドは `owner/repo` 形式の文字列を返します（例: `runceel/copilot-task-management`）。

`gh issue` や `gh project` コマンドを実行する際は、取得した値を `--repo` フラグに渡してください。
