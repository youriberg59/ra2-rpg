import express from "express";
import http from "http";
import { WebSocketServer } from "ws";
import pg from "pg";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import crypto from "crypto";

const { Pool } = pg;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT || 8080);
const DATABASE_URL = process.env.DATABASE_URL || "postgres://ra2rpg:ra2rpg@localhost:5432/ra2rpg";
const pool = new Pool({ connectionString: DATABASE_URL });

const app = express();
app.use(express.json());

const clientDir = path.resolve(__dirname, "../../client/public");
app.use(express.static(clientDir));

const contentDir = path.resolve(__dirname, "../../content");

function loadJson(name) {
  return JSON.parse(fs.readFileSync(path.join(contentDir, name), "utf8"));
}

const quests = loadJson("quests.json");
const npcs = loadJson("npcs.json");
const enemyTypes = loadJson("enemies.json");

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

const sockets = new Map();
const onlinePlayers = new Map();
const enemies = new Map();

const WORLD = {
  width: 1600,
  height: 1000,
  town: { x: 220, y: 160, w: 620, h: 500 },
  radar: { x: 1080, y: 250, w: 330, h: 360 }
};

function randomId(prefix = "id") {
  return `${prefix}_${crypto.randomBytes(6).toString("hex")}`;
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function sanitizeName(value) {
  return String(value || "Player").trim().slice(0, 20).replace(/[^\p{L}\p{N}_ -]/gu, "") || "Player";
}

async function loadOrCreatePlayer(id, name) {
  const found = await pool.query("SELECT * FROM players WHERE id=$1", [id]);
  if (found.rowCount) {
    const r = found.rows[0];
    return {
      id: r.id,
      name: r.name,
      x: Number(r.x),
      y: Number(r.y),
      hp: r.hp,
      maxHp: r.max_hp,
      level: r.level,
      xp: r.xp,
      credits: r.credits,
      inventory: r.inventory || [],
      questState: r.quest_state || {}
    };
  }

  const player = {
    id,
    name: sanitizeName(name),
    x: 330,
    y: 290,
    hp: 100,
    maxHp: 100,
    level: 1,
    xp: 0,
    credits: 100,
    inventory: ["pistol"],
    questState: {}
  };

  await savePlayer(player);
  return player;
}

async function savePlayer(p) {
  await pool.query(
    `INSERT INTO players
      (id,name,x,y,hp,max_hp,level,xp,credits,inventory,quest_state,updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11::jsonb,NOW())
     ON CONFLICT (id) DO UPDATE SET
      name=EXCLUDED.name,x=EXCLUDED.x,y=EXCLUDED.y,hp=EXCLUDED.hp,
      max_hp=EXCLUDED.max_hp,level=EXCLUDED.level,xp=EXCLUDED.xp,
      credits=EXCLUDED.credits,inventory=EXCLUDED.inventory,
      quest_state=EXCLUDED.quest_state,updated_at=NOW()`,
    [
      p.id, p.name, p.x, p.y, p.hp, p.maxHp, p.level, p.xp, p.credits,
      JSON.stringify(p.inventory), JSON.stringify(p.questState)
    ]
  );
}

function publicPlayer(p) {
  return {
    id: p.id, name: p.name, x: p.x, y: p.y, hp: p.hp, maxHp: p.maxHp,
    level: p.level, xp: p.xp, credits: p.credits, inventory: p.inventory,
    questState: p.questState
  };
}

function spawnEnemy(typeId, x, y) {
  const t = enemyTypes.find(e => e.id === typeId);
  if (!t) return;
  const id = randomId("enemy");
  enemies.set(id, {
    id,
    type: typeId,
    name: t.name,
    x, y,
    hp: t.maxHp,
    maxHp: t.maxHp,
    alive: true,
    respawnAt: 0,
    spawnX: x,
    spawnY: y
  });
}

[
  [1140, 320], [1240, 350], [1320, 450], [1180, 500], [1360, 560],
  [1040, 420], [1270, 260]
].forEach(([x, y]) => spawnEnemy("bandit", x, y));

function statePayload() {
  return {
    type: "state",
    world: WORLD,
    players: [...onlinePlayers.values()].map(publicPlayer),
    npcs,
    enemies: [...enemies.values()],
    quests
  };
}

function send(ws, data) {
  if (ws.readyState === 1) ws.send(JSON.stringify(data));
}

function broadcast(data) {
  const str = JSON.stringify(data);
  for (const ws of sockets.values()) {
    if (ws.readyState === 1) ws.send(str);
  }
}

function requiredXp(level) {
  return level * 100;
}

function giveXp(player, amount) {
  player.xp += amount;
  while (player.xp >= requiredXp(player.level)) {
    player.xp -= requiredXp(player.level);
    player.level++;
    player.maxHp += 10;
    player.hp = player.maxHp;
    send(sockets.get(player.id), {
      type: "toast",
      text: `LEVEL UP! You are now level ${player.level}.`
    });
  }
}

function questById(id) {
  return quests.find(q => q.id === id);
}

function advanceKillQuest(player, enemyType) {
  for (const q of quests) {
    const qs = player.questState[q.id];
    if (!qs || qs.status !== "active") continue;

    let changed = false;
    q.objectives.forEach((obj, index) => {
      if (obj.type !== "kill" || obj.target !== enemyType) return;
      qs.progress ??= {};
      qs.progress[index] = Math.min(obj.count, (qs.progress[index] || 0) + 1);
      changed = true;
    });

    if (!changed) continue;

    const complete = q.objectives.every((obj, index) => {
      if (obj.type === "kill") return (qs.progress?.[index] || 0) >= obj.count;
      return false;
    });

    if (complete) {
      qs.status = "ready";
      send(sockets.get(player.id), {
        type: "toast",
        text: `Quest objective complete: ${q.title}. Return to ${q.giver}.`
      });
    }
  }
}

function finishQuest(player, q) {
  const qs = player.questState[q.id];
  if (!qs || qs.status !== "ready") return false;
  qs.status = "completed";
  giveXp(player, q.rewards.xp || 0);
  player.credits += q.rewards.credits || 0;
  for (const item of q.rewards.items || []) player.inventory.push(item);
  return true;
}

wss.on("connection", (ws) => {
  let playerId = null;

  ws.on("message", async (buf) => {
    let msg;
    try { msg = JSON.parse(buf.toString()); } catch { return; }

    try {
      if (msg.type === "hello") {
        playerId = String(msg.playerId || "").trim();
        if (!/^[a-zA-Z0-9_-]{3,64}$/.test(playerId)) {
          send(ws, { type: "error", text: "Invalid player ID." });
          return;
        }

        const player = await loadOrCreatePlayer(playerId, msg.name);
        onlinePlayers.set(playerId, player);
        sockets.set(playerId, ws);
        send(ws, { type: "welcome", player: publicPlayer(player), quests, npcs, world: WORLD });
        broadcast(statePayload());
        return;
      }

      if (!playerId || !onlinePlayers.has(playerId)) return;
      const player = onlinePlayers.get(playerId);

      if (msg.type === "move") {
        const dx = clamp(Number(msg.dx) || 0, -1, 1);
        const dy = clamp(Number(msg.dy) || 0, -1, 1);
        const len = Math.hypot(dx, dy) || 1;
        const speed = 7;
        player.x = clamp(player.x + (dx / len) * speed, 20, WORLD.width - 20);
        player.y = clamp(player.y + (dy / len) * speed, 20, WORLD.height - 20);
      }

      if (msg.type === "attack") {
        const enemy = enemies.get(msg.enemyId);
        if (!enemy || !enemy.alive || distance(player, enemy) > 165) return;
        const damage = 18 + Math.floor(player.level * 1.5);
        enemy.hp -= damage;

        if (enemy.hp <= 0) {
          enemy.hp = 0;
          enemy.alive = false;
          const t = enemyTypes.find(e => e.id === enemy.type);
          enemy.respawnAt = Date.now() + (t?.respawnSeconds || 8) * 1000;

          const credits = Math.floor((t?.creditsMin || 0) + Math.random() * ((t?.creditsMax || 0) - (t?.creditsMin || 0) + 1));
          player.credits += credits;
          giveXp(player, t?.xp || 0);
          advanceKillQuest(player, enemy.type);

          if (Math.random() < 0.20) player.inventory.push("medkit");

          send(ws, {
            type: "toast",
            text: `${enemy.name} defeated. +${t?.xp || 0} XP, +$${credits}`
          });
        }
      }

      if (msg.type === "interactNpc") {
        const npc = npcs.find(n => n.id === msg.npcId);
        if (!npc || distance(player, npc) > 145) return;
        const q = questById(npc.quest);
        const qs = q ? player.questState[q.id] : null;

        if (q && qs?.status === "ready") {
          if (finishQuest(player, q)) {
            send(ws, {
              type: "dialogue",
              npc: npc.name,
              text: `Good work. The radar station is safe again. Reward: $${q.rewards.credits} and ${q.rewards.xp} XP.`
            });
          }
        } else if (q && !qs) {
          send(ws, {
            type: "dialogue",
            npc: npc.name,
            text: npc.dialogue,
            questOffer: q
          });
        } else if (q && qs?.status === "active") {
          const progress = q.objectives.map((obj, i) => `${qs.progress?.[i] || 0}/${obj.count} ${obj.target}`).join(", ");
          send(ws, {
            type: "dialogue",
            npc: npc.name,
            text: `You're still working on "${q.title}". Progress: ${progress}.`
          });
        } else if (q && qs?.status === "completed") {
          send(ws, {
            type: "dialogue",
            npc: npc.name,
            text: "Thanks again. The town owes you one."
          });
        }
      }

      if (msg.type === "acceptQuest") {
        const q = questById(msg.questId);
        if (!q || player.questState[q.id]) return;
        player.questState[q.id] = { status: "active", progress: {} };
        send(ws, { type: "toast", text: `Quest accepted: ${q.title}` });
      }

      if (msg.type === "useItem") {
        const idx = player.inventory.indexOf(msg.item);
        if (idx < 0) return;
        if (msg.item === "medkit" && player.hp < player.maxHp) {
          player.inventory.splice(idx, 1);
          player.hp = Math.min(player.maxHp, player.hp + 40);
          send(ws, { type: "toast", text: "Medkit used. +40 HP" });
        }
      }

      await savePlayer(player);
      broadcast(statePayload());
    } catch (err) {
      console.error(err);
      send(ws, { type: "error", text: "Server error." });
    }
  });

  ws.on("close", async () => {
    if (!playerId) return;
    const player = onlinePlayers.get(playerId);
    if (player) {
      try { await savePlayer(player); } catch (e) { console.error(e); }
    }
    onlinePlayers.delete(playerId);
    sockets.delete(playerId);
    broadcast(statePayload());
  });
});

setInterval(() => {
  const now = Date.now();

  for (const enemy of enemies.values()) {
    if (!enemy.alive && enemy.respawnAt && now >= enemy.respawnAt) {
      enemy.alive = true;
      enemy.hp = enemy.maxHp;
      enemy.x = enemy.spawnX;
      enemy.y = enemy.spawnY;
      enemy.respawnAt = 0;
    }

    if (enemy.alive) {
      const nearest = [...onlinePlayers.values()]
        .map(p => ({ p, d: distance(p, enemy) }))
        .sort((a, b) => a.d - b.d)[0];

      if (nearest && nearest.d < 260 && nearest.d > 45) {
        const dx = nearest.p.x - enemy.x;
        const dy = nearest.p.y - enemy.y;
        const len = Math.hypot(dx, dy) || 1;
        enemy.x += dx / len * 1.1;
        enemy.y += dy / len * 1.1;
      }

      if (nearest && nearest.d < 55 && Math.random() < 0.04) {
        nearest.p.hp -= 5;
        if (nearest.p.hp <= 0) {
          nearest.p.hp = nearest.p.maxHp;
          nearest.p.x = 330;
          nearest.p.y = 290;
          send(sockets.get(nearest.p.id), { type: "toast", text: "You were defeated and returned to town." });
        }
      }
    }
  }

  broadcast(statePayload());
}, 100);

setInterval(async () => {
  for (const p of onlinePlayers.values()) {
    try { await savePlayer(p); } catch (e) { console.error(e); }
  }
}, 5000);

app.get("/api/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ ok: true, players: onlinePlayers.size, enemies: enemies.size });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e) });
  }
});

app.get("*", (_req, res) => {
  res.sendFile(path.join(clientDir, "index.html"));
});

server.listen(PORT, () => {
  console.log(`RA2 RPG prototype listening on http://0.0.0.0:${PORT}`);
});
