# LoL Replay Analyzer

**AI-powered League of Legends replay analyzer** that lets players upload `.rofl` files and get personalized match analysis, performance feedback, and strategic insights — all through a polished web app built with Rails 8 and ViewComponent.

## 🔥 Features

- 🎮 Upload `.rofl` files for instant parsing and match breakdown
- 📊 Performance metrics and player-specific recommendations
- 🧠 AI-based insights based on roles, builds, and decision-making
- 💳 Stripe integration for per-match monetization
- 🧩 Modular frontend powered by ViewComponent
- 🌐 Uses Riot Games API for champion data and metadata enrichment

## 🛠️ Tech Stack

- **Backend:** Ruby on Rails 8
- **Frontend:** ViewComponent, Turbo
- **Payments:** Stripe
- **Replay Parsing:** Custom `.rofl` parser
- **APIs:** Riot Games API
- **Database:** PostgreSQL

## 🚀 Getting Started

### Prerequisites

- Ruby 3.3+
- Rails 8+
- PostgreSQL
- Stripe API keys

### Setup

```bash
git clone https://github.com/yourusername/lol_replay_analyzer.git
cd lol_replay_analyzer
bundle install
rails db:setup