# ai-agent-kit

Claude を司令塔にして、Codex・Cursor・Gemini CLI に作業を任せるための共通スクリプト集。
どのプロジェクトからも同じ入口で使う。使い方の判断（何を誰に任せるか）はアカウントのスキルに置く。

| 入口 | 役割 | 認証 |
| --- | --- | --- |
| `codex/delegate.sh` | Codex CLI（ChatGPT プラン）に1回分の作業を任せる | `codex/login.sh`（デバイス認証、一度だけ） |
| `cursor/delegate.sh` | Cursor CLI に任せる | 環境変数 `CURSOR_API_KEY` |
| `gemini/delegate.sh` | Gemini CLI（Google AI Pro）に任せる | `gemini/login.sh`（Google ログイン、一度だけ） |
| `install.sh [codex cursor gemini]` | CLI のインストール | なし |
| `lib/auth_store.py` | Codex / Gemini のログインをセッション間で保存・復元 | 下記 |

共通の使い方: `bash <kit>/<tool>/delegate.sh [--write] [--model 名前] [--timeout 秒] "依頼文"`（`--file prompt.md` も可）。
`--write` なしは読み取り専用。コミットとプッシュは任せない。結果の検証は Claude が行う。
実行ログは対象プロジェクトの `.codex-runs/` `.cursor-runs/` `.gemini-runs/` に残る（gitignore 推奨）。

## プロジェクトから使う

1. プロジェクトにこのリポジトリを追加する（クラウドでは `/home/user/ai-agent-kit` にクローンされる）。
2. 環境のセットアップスクリプトか最初のコマンドで `bash /home/user/ai-agent-kit/install.sh` を実行する。
3. Codex / Gemini は初回だけ `login.sh` でログインする。以降は保存された login が自動で復元される。
4. Cursor は環境変数 `CURSOR_API_KEY` を入れる。

## ログインの保存先（`AI_KIT_STORE`）

Codex は約8日ごとに auth.json を更新し、古いものは使えなくなる。そのため保存先に置き、更新のたびに新しい方を書き戻す。
古いもので新しいものを上書きしない。中身はパスワードと同じ扱いで、出力しない。

- `AI_KIT_STORE=dir:/path/to/dir` : フォルダに保存（既定は `~/.ai-agent-kit-store`。セッションをまたぐなら同期・マウントされた場所を指定）
- `AI_KIT_STORE=drive` : Google ドライブ。プロジェクト側に `scripts/cloud/drive_store.py` と Drive 用の環境変数が必要（montage-studio 形式）。`_private/<tool>-auth.json` に置く。

## 注意

- Gemini は環境に `GEMINI_API_KEY` / `GOOGLE_API_KEY` があると API キーが優先され、AI Pro の枠を使わない。ログイン済みのときは delegate.sh が実行中だけそれらを外す。
- 同じログインを複数の場所で使うと、更新で片方が切れる。クラウド用は別にログインする。
- 「Codex plan limit reached」の警告は誤検知のことがある。回答が正常に返っていれば続行する。
