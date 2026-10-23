# 使い始めるために、人間が用意するもの

AI エージェント向けの注意: このファイルは「何を誰が用意するか」の一覧です。値そのものはここに無く、チャットにも貼らせません。
足りないものは `bash doctor.sh` が `TODO` として教えます。順を追った手順は [FIRST-TIME-GUIDE.md](FIRST-TIME-GUIDE.md) にあります。

## 前提

- Claude Code（クラウドセッション、または手元の CLI）が使えること。
- 使いたい助手ごとのアカウント: Codex（ChatGPT プラン）、Cursor、agy（Google AI Pro）。使わない助手は用意しなくてよい。

## 人間が用意するもの

| 項目 | 何のために | どこで用意するか | 誰が |
| --- | --- | --- | --- |
| クラウド環境のセットアップスクリプト | セッション開始時にキットを入れる | クラウド環境の設定 → Setup script | 人間 |
| `CURSOR_API_KEY` | Cursor CLI の認証 | Cursor のダッシュボードで API キーを作り、環境変数に登録 | 人間（値はチャットに貼らない） |
| `AI_KIT_DRIVE_CLIENT_ID` / `_CLIENT_SECRET` / `_REFRESH_TOKEN` / `_ROOT_FOLDER_ID` | Codex・agy のログインをセッション間で保存する（任意） | Google Cloud で OAuth クライアントを作り、リフレッシュトークンと保存先フォルダの ID を得て、環境変数に登録（既に `<PREFIX>_DRIVE_*` の名前で持っているなら、そのままで動く） | 人間 |
| Codex のログイン | Codex CLI の認証 | `bash /home/user/ai-agent-kit/codex/login.sh` をバックグラウンドで実行し、出たコードを人間が `https://auth.openai.com/codex/device` で承認（初回だけ） | エージェントが実行、人間が承認 |
| agy のログイン | agy の認証 | `python3 /home/user/ai-agent-kit/agy/login_headless.py start` が出す URL を人間が開き、得たコードを `python3 /home/user/ai-agent-kit/agy/login_headless.py code <コード>` で渡す（約25分以内、間に agy を再起動しない） | エージェントが実行、人間が承認 |

Drive の変数が無ければ、ログインは `~/.ai-agent-kit-store` に保存され、セッションが終わると消えます。毎回ログインし直したくなければ Drive の変数、または `AI_KIT_STORE=dir:<セッションをまたいで残るフォルダ>` を設定します。
ログイン保存の `TODO` は任意です。使わないなら、それ以外がすべて `OK` であれば使えます。

## 環境変数の扱い（安全面）

- 環境変数は、その環境を使う全員と、**任せた助手のプロセスからも読める**と考えてください。キットは助手を起動するとき環境変数を絞りません。
- Drive の認証は、このキット専用の Google アカウントや、最小の権限（保存先フォルダだけ）で作ることをおすすめします。
- 鍵のように重要な値は、環境変数ではなくネットワークシークレットに入れられるか検討します（宛先ホスト限定で、セッションからは見えない）。

## セットアップスクリプトの例

推奨は、**セットアップスクリプトで clone し、プロジェクトのリポジトリは1つのまま**にする方法です。

```bash
# 例: クラウド環境の Setup script
KIT=/home/user/ai-agent-kit
[ -d "$KIT/.git" ] || git clone https://github.com/<owner>/ai-agent-kit "$KIT"
bash "$KIT/install.sh"
```

最新の状態を保つには、プロジェクトの `.claude/settings.json` の SessionStart フックで毎回更新します。

```json
"hooks": {"SessionStart": [{"hooks": [{"type": "command",
  "command": "git -C /home/user/ai-agent-kit pull --ff-only -q 2>/dev/null; bash /home/user/ai-agent-kit/install.sh >/dev/null 2>&1; bash /home/user/ai-agent-kit/doctor.sh 2>&1 | grep -A3 TODO || true"}]}]}
```

注意:

- **ai-agent-kit をプロジェクトのリポジトリとして追加すると、セッションが複数リポジトリになり、どのリポジトリの `.claude/settings.json` のフックも読み込まれません。** フックを使いたいなら、キットはリポジトリとして追加せず、セットアップスクリプトで clone します。一方、定期タスクのようにキットだけを使う場合は、キットをリポジトリとして追加して構いません（キット自身の `.claude/settings.json` のフックが働く）。
- このリポジトリが**公開**なら、セットアップスクリプトから認証なしで clone できます。**非公開**にする場合、セッションに登録していないリポジトリを clone できるかは確認が必要です（プロキシが認証を付ける対象は、セッションに登録したリポジトリです）。非公開にする前に、新しいセッションで試してください。
- セットアップスクリプトの結果は保存され、約7日、またはスクリプトや許可するネットワーク先を変えるまで再利用されることがあります（約5分を超えると保存されません）。その間、キットは古いままなので、上のフックで更新します。
- セットアップスクリプトは、環境に保存した変数やシークレットを読めません。それらが読めるのはセッションが始まってからです。
- `install.sh` は、配布元のスクリプトを確認なしで実行します。他人が使う場合は、自分の fork を使うか、commit を固定してください。

## 確認

1. 診断したいプロジェクトのフォルダで、新しいセッションを開き `bash /home/user/ai-agent-kit/doctor.sh` を実行する（使わない助手は `doctor.sh codex` のように絞れる）。
2. すべて `OK` なら準備完了。`TODO` が出たら、その手順に従う。
3. 動作確認の例: `bash /home/user/ai-agent-kit/codex/delegate.sh "このリポジトリの README の見出しを列挙して"`（読み取り専用）。

## このリポジトリが前提にしないもの

特定の個人や組織のスプレッドシート、カレンダー、フォルダの情報は、このリポジトリに含まれません。
それらを使うときは、使う人が自分の環境変数やプロジェクトの文書で用意します（[LEDGER-PATTERN.md](LEDGER-PATTERN.md) を参照）。
