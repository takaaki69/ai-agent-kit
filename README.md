# ai-agent-kit

> 個人用のツールです。無保証で提供しており、使う場合は自己責任でお願いします。ライセンスは付けていないため、他の人への利用許可は出していません。

## このリポジトリでできること

AI に仕事を任せて、自分の時間と利用枠を守るための道具箱です。大きく2つあります。

1. **助手への委任**: Claude を司令塔にして、Codex・Cursor・Antigravity CLI（agy）に、調査・修正・下書きなどを任せます。使う枠を Claude・Codex・Cursor・agy に分散し、能力が要る部分にだけ Claude の枠を使うのが目的です。小さな作業は任せず、Claude 自身が行います。
2. **スケジュール・タスク管理の型**: 予定とタスクを台帳（スプレッドシート）とカレンダーに集め、AI が書記と見張り番になります。決まった時刻に短いまとめだけを届け、期日が近づくほど段階的に通知を強めるので、**通知が埋もれません**。全体像と使い方は [docs/TASK-SYSTEM.md](docs/TASK-SYSTEM.md)、台帳のつなぎ方は [docs/LEDGER-PATTERN.md](docs/LEDGER-PATTERN.md) にあります。

はじめて使う人は [docs/FIRST-TIME-GUIDE.md](docs/FIRST-TIME-GUIDE.md)（クラウド環境に取り込む手順を順に案内）から、用意するものの一覧は [docs/SETUP.md](docs/SETUP.md) で確認できます。AI エージェントは [AGENTS.md](AGENTS.md) から読み始めます。
このリポジトリは公開です。自分の台帳の ID、メール、実データ、他人の名前は置かず、環境変数や自分の文書に持ちます。

## 助手への委任（スクリプト一覧）

Claude を司令塔にして、Codex・Cursor・Antigravity CLI（agy、旧 Gemini CLI） に作業を任せるための共通スクリプト集。
どのプロジェクトからも同じ入口で使う。使い方の判断（何を誰に任せるか）はアカウントのスキルに置く。

| 入口 | 役割 | 認証 |
| --- | --- | --- |
| `codex/delegate.sh` | Codex CLI（ChatGPT プラン）に1回分の作業を任せる | `codex/login.sh`（デバイス認証、一度だけ） |
| `cursor/delegate.sh` | Cursor CLI に任せる（クラウドで CLI が無ければその場で入れる） | 環境変数 `CURSOR_API_KEY`（Mac は `agent login` でも可） |
| `agy/delegate.sh` | Antigravity CLI（Google AI Pro）に任せる | `agy/login_headless.py`（Google ログイン、一度だけ） |
| `install.sh [codex cursor agy]` | CLI のインストール | なし |
| `lib/auth_store.py` | Codex / agy のログインをセッション間で保存・復元 | 下記 |

共通の使い方: `bash <kit>/<tool>/delegate.sh [--write] [--model 名前] [--timeout 秒] "依頼文"`（`--file prompt.md` も可）。
`--write` なしは読み取り専用。コミットとプッシュは任せない。結果の検証は Claude が行う。
助手を起動するとき、その助手に要らない秘密（Drive の認証情報、トークンなど）は環境から外す（`lib/scrub_env.sh`、`AI_KIT_SCRUB_ENV=0` で無効）。
実行ログは対象プロジェクトの `.codex-runs/` `.cursor-runs/` `.agy-runs/` に残る（gitignore 推奨）。

## 利用記録

どの `delegate.sh` も、実行のたびに1行（日時・プロジェクト名・助手・終了状態・所要秒・読み取り/書き込み・モデル・依頼文と回答の文字数）を記録する。依頼文と回答の中身は保存しない。
Drive の認証情報があれば Drive の `<root>/_usage/usage.jsonl` に、なければ `~/.ai-agent-kit-usage.jsonl` に追記するので、キットを使うすべてのプロジェクトの分が同じファイルに集まる。
集計: `python3 lib/usage_log.py summary [日数]`。止めるには `AI_KIT_USAGE_LOG=0`。記録に失敗しても実行結果は変わらない。
記録されるのは「何をどこに任せたか」で、Claude の使用量そのものや節約量は測れない。

## プロジェクトから使う

1. 環境のセットアップスクリプトで `/home/user/ai-agent-kit` に clone し、`bash /home/user/ai-agent-kit/install.sh` を実行する（例は [docs/SETUP.md](docs/SETUP.md)）。キットだけを使う定期タスクなら、リポジトリとして追加してもよい。ただし、プロジェクトのリポジトリとしてキットを足すと複数リポジトリのセッションになり、下の SessionStart フックは読み込まれない。
2. 以降の手順は、この環境のセットアップが済んでいる前提。
3. Codex は `codex/login.sh`、agy は `agy/login_headless.py` で、初回だけログインする。以降は保存されたログインが自動で復元される。
4. Cursor は環境変数 `CURSOR_API_KEY` を入れる。

### 毎回のセッションで自動セットアップする

プロジェクトの `.claude/settings.json` に次を足すと、セッション開始時に `install.sh`（入っていれば何もしない）と `doctor.sh` が走り、未設定の項目だけ `TODO` として表示される。このリポジトリ自身の `.claude/settings.json` にも同じ設定を入れてある。

```json
"hooks": {"SessionStart": [{"hooks": [{"type": "command",
  "command": "bash /home/user/ai-agent-kit/install.sh >/dev/null 2>&1; bash /home/user/ai-agent-kit/doctor.sh 2>&1 | grep -A3 TODO || true"}]}]}
```

## ログインの保存先（`AI_KIT_STORE`）

Codex は約8日ごとに auth.json を更新し、古いものは使えなくなる。そのため保存先に置き、更新のたびに新しい方を書き戻す。
古いもので新しいものを上書きしない。中身はパスワードと同じ扱いで、出力しない。

- `AI_KIT_STORE=dir:/path/to/dir` : フォルダに保存（既定は `~/.ai-agent-kit-store`。セッションをまたぐなら同期・マウントされた場所を指定）
- `AI_KIT_STORE=drive` : Google ドライブ。キット自身の `lib/drive.py`（標準ライブラリだけ、pip 不要）で、ドライブの `<ルート>/_private/<tool>-auth.json` に置く。
- 認証情報は環境変数 4 つ（環境の設定画面に入れる。チャットには貼らない）:
  `AI_KIT_DRIVE_CLIENT_ID` / `AI_KIT_DRIVE_CLIENT_SECRET` / `AI_KIT_DRIVE_REFRESH_TOKEN` / `AI_KIT_DRIVE_ROOT_FOLDER_ID`。
  すでに `<PREFIX>_DRIVE_*` の名前で持っているプロジェクト（montage-studio の `OPENMONTAGE_DRIVE_*`）は、そのままで動く（保存場所も同じ）。
- 未設定のとき: Drive の認証情報があれば自動で `drive`。なければ `~/.ai-agent-kit-store`（セッションをまたいで残らない）。どちらが使われるかは `python3 lib/auth_store.py codex store` で分かる。

## 注意

- Gemini CLI は 2026-06-18 に個人の Google アカウント（AI Pro 含む）での提供が終わり、agy に置き換わった。Gemini CLI のログインは `IneligibleTierError` になる。
- agy の `--print` は、プロンプトを `--print="..."` の形で付ける（`--print "..."` だと次のフラグをプロンプトと誤解する）。delegate.sh は対応済み。
- agy のログインはクラウドで端末操作ができないため、`python3 agy/login_headless.py start` で URL を出し、ユーザーが取ったコードを `python3 agy/login_headless.py code <コード>` で渡す。2つのコマンドの間で agy を再起動しない（コードはその agy にだけ有効、約25分）。
- 同じログインを複数の場所で使うと、更新で片方が切れる。クラウド用は別にログインする。
- Cursor の読み取り専用（ask モード）でも `--force` を付けている。付けないと `-p` では承認を求められず、ウェブ検索が拒否される。ask モードなのでファイル編集とシェルは引き続き止まる。
- 「Codex plan limit reached」の警告は誤検知のことがある。回答が正常に返っていれば続行する。
