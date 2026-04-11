# OpenClaw Setup

## Prerequisites
- Docker Desktop (with GPU support enabled for NVIDIA)
- A Telegram account
- A Gmail account

## 1. Telegram Bot Setup

1. Open Telegram and message **@BotFather**
2. Send `/newbot` and follow the prompts to name your bot
3. Copy the bot token (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
4. Paste it into `.env` as `TELEGRAM_BOT_TOKEN`

## 2. Gmail Setup

Gmail uses OAuth2 — you authenticate via browser on first run:

1. Start the gateway: `docker compose up -d`
2. Open the control UI: http://localhost:18789/openclaw
3. Navigate to Channels → Gmail → Authenticate
4. Sign in with your Google account and grant permissions
5. The credentials are saved in `data/config/credentials/`

## 3. Start Everything

```bash
# Start Ollama + OpenClaw gateway
docker compose up -d

# First run: Qwen model will be pulled automatically (may take a few minutes)
# Watch progress with:
docker compose logs -f ollama-pull

# Check everything is healthy:
docker compose ps
```

## 4. Pair Your Telegram

Once the gateway is running:

1. Message your bot on Telegram — it will show a pairing code
2. Approve the pairing via CLI:
   ```bash
   docker compose --profile cli run openclaw-cli pairing list telegram
   docker compose --profile cli run openclaw-cli pairing approve telegram <CODE>
   ```
3. You're connected! Start chatting.

## 5. Using Task & Idea Prompts

In Telegram (or any connected channel):

| Command | What it does |
|---------|-------------|
| `task: fix the login bug on mobile` | AI parses and saves a new task |
| `/tasks` | List all open tasks by priority |
| `/review` | AI reviews your tasks with recommendations |
| `idea: build a weekly email digest` | Capture and categorize a new idea |
| `/ideas` | List all captured ideas |
| `/reviewideas` | AI reviews ideas for potential and next steps |
| `/standup` | Generate a daily standup summary |

## 6. Web UI

Open http://localhost:18789/openclaw for the full control panel.

## GPU Note

The docker-compose includes GPU passthrough for Ollama. If you don't have a GPU,
remove the `deploy.resources` block from the `ollama` service in `docker-compose.yml`.

## Changing the Model

Edit `data/config/openclaw.json` and change the model under `agents.defaults.model.primary`.
Options: `ollama/qwen2.5:3b` (lighter), `ollama/qwen2.5:7b` (default), `ollama/qwen2.5:14b` (heavier).
Also update the model name in the `ollama-pull` service in `docker-compose.yml`.
