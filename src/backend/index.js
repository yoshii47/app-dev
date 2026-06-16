// DB接続の設定
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

// .envを読む方法の手段
require('dotenv').config();

const express = require('express');
const app = express();
const port = 3000;

app.get('/users', (req, res) => {
  res.json(users);
});

let users = [
  { id: 1, name: '太郎' },
  { id: 2, name: '花子' },
];

// JSONデータを扱うためのミドルウェア
app.use(express.json());

app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});

app.get('/users/:id', (req, res) => {
  const id = Number(req.params.id);
  const user = users.find(u => u.id === id);
  if (user) {
    res.json(user);
  } else {
    res.status(404).send('ユーザーが見つかりません');
  }
});

