# Deploying NEFMP e-Billing API to Railway — Step by Step

This deploys the **minimal skeleton** (health checks + DB connectivity + a proof-of-life
endpoint reading from the Domain layer). The goal right now is to prove the pipeline
works end-to-end — GitHub → Railway → Docker build → live URL → connects to Postgres —
before we add the rest of the backend (Application/Infrastructure/API controllers).
Once this works, redeploying updated code is just a `git push`.

---

## Step 1 — Get the code into a GitHub repository

Railway deploys from a Git repo (this is the most reliable path — it also gives you
auto-redeploy on every push, and a history of what's deployed).

1. Download the `nefmp-backend` folder I'm sharing with this message.
2. Create a new **empty** repository on GitHub (e.g. `nefmp-ebilling`). Don't initialize
   it with a README — we already have files.
3. On your own machine, in the downloaded folder:
   ```bash
   git init
   git add .
   git commit -m "Initial e-Billing API skeleton"
   git branch -M main
   git remote add origin https://github.com/<your-username>/nefmp-ebilling.git
   git push -u origin main
   ```

---

## Step 2 — Create your Railway account

1. Go to https://railway.app and sign up (GitHub login is the fastest option — it also
   makes Step 3 simpler since Railway can already see your repos).
2. You land on the Railway dashboard once signed in.

---

## Step 3 — Create a new Project from your GitHub repo

1. Click **New Project** → **Deploy from GitHub repo**.
2. Authorize Railway to access your GitHub account if prompted, then select the
   `nefmp-ebilling` repo you just pushed.
3. Railway will detect the `Dockerfile` at the repo root automatically and start a build.
   (You'll see it fail on the first attempt — that's expected, because there's no
   database yet. We fix that in the next step.)

---

## Step 4 — Add a PostgreSQL database

1. Inside your Railway project, click **+ New** → **Database** → **Add PostgreSQL**.
2. Railway provisions a Postgres instance and automatically creates a `DATABASE_URL`
   variable containing the full connection string.
3. Click on your **API service** (not the database) → **Variables** tab → **New Variable**
   → **Add Reference** → select the Postgres service's `DATABASE_URL`.
   This makes `DATABASE_URL` available to your API container at runtime — which is
   exactly the environment variable `Program.cs` reads.

---

## Step 5 — Configure the health check (recommended)

1. In your API service → **Settings** tab → **Deploy** section → **Healthcheck Path**:
   set this to `/health`.
2. This tells Railway how to confirm your container is actually up before routing
   traffic to it, and to restart it automatically if it stops responding.

---

## Step 6 — Redeploy and get your public URL

1. Go back to your API service → **Deployments** tab → click **Redeploy** on the latest
   deployment (or just push a new commit — Railway rebuilds automatically on push).
2. Once the build succeeds and the container is healthy, go to **Settings** →
   **Networking** → click **Generate Domain**. Railway gives you a public URL like
   `nefmp-ebilling-production.up.railway.app`.

---

## Step 7 — Verify it's actually working

Open these three URLs in your browser (replace with your actual Railway domain):

```
https://<your-app>.up.railway.app/health
```
Expect: `{"status":"ok","service":"NEFMP e-Billing API","timestampUtc":"..."}`

```
https://<your-app>.up.railway.app/health/db
```
Expect: `{"status":"connected","postgresVersion":"PostgreSQL 16..."}`
— this confirms Railway's Postgres and your API are actually talking to each other.

```
https://<your-app>.up.railway.app/api/v1/meta/invoice-statuses
```
Expect: `["Draft","PendingApproval","Approved","Generated","Posted","Delivered","PartiallyPaid","Paid","Closed","Void"]`
— this confirms the Domain project reference compiled and is wired into the API.

If all three respond correctly, the entire pipeline is proven: GitHub → Railway →
Docker build → live container → connected to a real Postgres database.

---

## Step 8 — Load the actual NEFMP schema onto Railway's Postgres

Right now Railway's Postgres is empty. To load our validated schema:

1. In Railway, click your Postgres service → **Connect** tab → copy the
   **Postgres Connection URL** (external, for connecting from your own machine).
2. On your machine, using `psql` (or a GUI tool like DBeaver/pgAdmin):
   ```bash
   psql "<paste connection URL here>" -f 01_control_plane.sql
   psql "<paste connection URL here>" -f 02_core_tenant_platform.sql
   psql "<paste connection URL here>" -f 03_accounting_stub.sql
   psql "<paste connection URL here>" -f 04_ebilling.sql
   psql "<paste connection URL here>" -f 05_audit_and_future_module_stubs.sql
   ```
   (These are the same five files validated earlier in this project — run in this
   exact order, since each depends on schemas created by the ones before it.)
3. Note: Railway's Postgres needs the `pgcrypto` and `citext` extensions enabled —
   run this once, first, before the schema files:
   ```bash
   psql "<paste connection URL here>" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS citext; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
   ```

---

## What happens next

Once you confirm Step 7's three endpoints work, tell me and I'll continue building the
Application, Infrastructure, and API controller layers (Customer, Invoice, Receipt,
Credit/Debit Note endpoints per the API specification) — each addition just needs a
`git push` to redeploy automatically.

## Troubleshooting

- **Build fails at `dotnet restore`**: check the Railway build logs — this almost
  always means a typo in a `.csproj` package version. Railway's build environment has
  full internet access to nuget.org, so restore failures here are a code issue, not
  a network issue (unlike in the environment I developed this in).
- **`/health` works but `/health/db` returns an error**: double-check the `DATABASE_URL`
  variable reference was added correctly in Step 4 — it's the most common miss.
- **Container starts then immediately restarts/crashes**: check that `Program.cs` is
  reading the `PORT` environment variable correctly — Railway assigns this dynamically
  and the app must bind to it, not to a hardcoded port.
